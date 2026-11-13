// Draws the engine's instances as HTML and reports back what the library
// reads: sizes, positions, text bounds, typed text, scrolling and input.
//
// Layout follows Roblox's rules. A GuiObject's children stack in one grid
// cell and are offset by their Position, so a parent with AutomaticSize
// grows to fit them. A UIListLayout makes the parent a flex box, and a
// UIGridLayout a CSS grid. Sizes are calc() of scale and offset, so they
// track the parent the way UDim2 does.

import { icon, ICONS, ASSETS } from "./icons.js";

const hasIcon = (name) => Object.prototype.hasOwnProperty.call(ICONS, name);

const COMPONENT = new Set([
	"UICorner",
	"UIStroke",
	"UIPadding",
	"UIListLayout",
	"UIGridLayout",
	"UIFlexItem",
	"UISizeConstraint",
	"UITextSizeConstraint",
	"UIAspectRatioConstraint",
	"UIScale",
	"UIGradient",
]);
const TEXT = new Set(["TextLabel", "TextButton", "TextBox"]);
const IMAGE = new Set(["ImageLabel", "ImageButton"]);
const BUTTON = new Set(["TextButton", "ImageButton"]);
// The window shadow image, drawn as a soft CSS shadow instead.
const SHADOW_ASSETS = new Set(["rbxassetid://8992230677"]);
const DISCORD_DECAL = "132364423955781";

const rgb = (c, alpha = 1) => (c ? `rgba(${c[0]},${c[1]},${c[2]},${alpha})` : `rgba(0,0,0,${alpha})`);
const px = (n) => `${Math.round(n * 1000) / 1000}px`;
// "scale * size + offset" as CSS, for a UDim against a length like 100%.
const udim = (scale, offset, whole = "100%") => {
	if (!scale) return px(offset || 0);
	if (!offset) return scale === 1 ? whole : `calc(${whole} * ${scale})`;
	return `calc(${whole} * ${scale} + ${px(offset)})`;
};

export class Renderer {
	constructor(stage, onEvent) {
		this.stage = stage;
		this.onEvent = onEvent;
		this.nodes = new Map();
		this.dirty = new Set();
		this.measureAll = true;
		this.rects = new Map();
		this.content = new Map();
		this.hovered = new Set();
		this.pressed = null;
		this.pendingFocus = null;
		// Roblox lays a new object out before it draws it, so code that reads
		// AbsoluteSize to place a popup never shows it in the wrong spot. The
		// page measures after drawing, so new elements stay hidden until the
		// engine has had one frame to read their size and move them.
		this.fresh = [];
		this.waiting = [];
		this.root = document.createElement("div");
		this.root.className = "hc-root";
		stage.append(this.root);
		this.bindInput();
	}

	// Applies one frame of changes from the engine.
	apply(ops) {
		for (const op of ops) {
			switch (op[0]) {
				case "c":
					this.create(op[1], op[2], op[3], op[4]);
					break;
				case "p":
					this.setProperty(op[1], op[2], op[3]);
					break;
				case "a":
					this.setAttribute(op[1], op[2], op[3]);
					break;
				case "m":
					this.move(op[1], op[2]);
					break;
				case "d":
					this.destroy(op[1]);
					break;
				case "f":
					this.focus(op[1], op[2]);
					break;
			}
		}
		if (ops.length) this.measureAll = true;
		for (const node of this.waiting) node.el.style.visibility = "";
		this.waiting = this.fresh;
		this.fresh = [];
		const box = this.pendingFocus;
		if (box && this.nodes.has(box.id) && getComputedStyle(box.input).visibility !== "hidden") {
			this.pendingFocus = null;
			box.input.focus();
		}
	}

	create(id, cls, parentId, name) {
		const node = { id, cls, name, parent: null, children: [], props: {}, attrs: {}, comps: {} };
		this.nodes.set(id, node);
		if (!COMPONENT.has(cls)) {
			const el = document.createElement("div");
			el.dataset.id = id;
			if (name) el.dataset.name = name;
			el.className = cls === "ScreenGui" ? "hc-layer" : "hc";
			el.style.visibility = "hidden";
			this.fresh.push(node);
			node.el = el;
			node.box = el;
			if (TEXT.has(cls)) {
				if (cls === "TextBox") {
					node.input = document.createElement("input");
					node.input.className = "hc-input";
					node.input.spellcheck = false;
					node.input.autocomplete = "off";
					this.bindTextBox(node, node.input);
					el.append(node.input);
				} else {
					node.text = document.createElement("span");
					node.text.className = "hc-text";
					node.inner = document.createElement("span");
					node.inner.className = "hc-run";
					node.text.append(node.inner);
					el.append(node.text);
				}
			} else if (IMAGE.has(cls)) {
				node.image = document.createElement("span");
				node.image.className = "hc-image";
				el.append(node.image);
			} else if (cls === "ScrollingFrame") {
				el.classList.add("hc-scroll");
				node.canvas = document.createElement("div");
				node.canvas.className = "hc-canvas";
				el.append(node.canvas);
				node.box = node.canvas;
				el.addEventListener("scroll", () => {
					this.onEvent({ t: "scroll", id, x: el.scrollLeft, y: el.scrollTop });
					this.measureAll = true;
				});
			}
		}
		this.move(id, parentId);
	}

	move(id, parentId) {
		const node = this.nodes.get(id);
		if (!node) return;
		if (node.parent) {
			const siblings = node.parent.children;
			const index = siblings.indexOf(node);
			if (index >= 0) siblings.splice(index, 1);
			this.detachComponent(node);
			this.markLayout(node.parent);
		}
		const parent = parentId ? this.nodes.get(parentId) : null;
		node.parent = parent;
		if (parent) {
			parent.children.push(node);
			if (COMPONENT.has(node.cls)) {
				this.attachComponent(node);
			} else if (parent.box) {
				parent.box.append(node.el);
			}
			this.markLayout(parent);
		} else if (node.el) {
			this.root.append(node.el);
		}
		this.markTree(node);
	}

	destroy(id) {
		const node = this.nodes.get(id);
		if (!node) return;
		if (node.parent) {
			const siblings = node.parent.children;
			const index = siblings.indexOf(node);
			if (index >= 0) siblings.splice(index, 1);
			this.detachComponent(node);
			this.markLayout(node.parent);
		}
		const drop = (n) => {
			for (const child of n.children) drop(child);
			this.nodes.delete(n.id);
			this.rects.delete(n.id);
			this.hovered.delete(n.id);
		};
		drop(node);
		node.el?.remove();
	}

	// A UI component changes how its parent looks or lays out.
	attachComponent(node) {
		const parent = node.parent;
		const key = node.cls;
		parent.comps[key] = node;
	}

	detachComponent(node) {
		const parent = node.parent;
		if (parent && parent.comps[node.cls] === node) {
			delete parent.comps[node.cls];
		}
	}

	setProperty(id, key, value) {
		const node = this.nodes.get(id);
		if (!node) return;
		node.props[key] = value;
		if (COMPONENT.has(node.cls)) {
			if (node.parent) this.markLayout(node.parent);
			return;
		}
		this.dirty.add(node);
		// What a parent lays out depends on its children's sizes and order.
		if (key === "Size" || key === "LayoutOrder" || key === "Visible" || key === "AutomaticSize") {
			if (node.parent) this.dirty.add(node.parent);
		}
		if (key === "Text" || key === "RichText") {
			this.renderText(node);
			this.dirty.add(node);
		}
		if (key === "Image" || key === "ImageColor3" || key === "ImageTransparency") this.renderImage(node);
		if (key === "GroupTransparency") this.dirty.add(node);
	}

	setAttribute(id, name, value) {
		const node = this.nodes.get(id);
		if (!node) return;
		node.attrs[name] = value;
		if (name === "HalcyonIcon") this.renderImage(node);
	}

	focus(id, on) {
		const node = this.nodes.get(id);
		if (!node?.input) return;
		if (!on) {
			if (this.pendingFocus === node) this.pendingFocus = null;
			node.input.blur();
			return;
		}
		// A box made this frame is still hidden, and hidden inputs can't
		// take focus; it gets it once it shows.
		if (getComputedStyle(node.input).visibility === "hidden") this.pendingFocus = node;
		else node.input.focus();
	}

	markLayout(node) {
		this.dirty.add(node);
		for (const child of node.children) if (child.el) this.dirty.add(child);
	}

	markTree(node) {
		this.dirty.add(node);
		for (const child of node.children) this.markTree(child);
	}

	// Brings every changed element's style up to date.
	flush() {
		if (!this.dirty.size) return;
		const list = [...this.dirty];
		this.dirty.clear();
		for (const node of list) {
			if (!node.el || !this.nodes.has(node.id)) continue;
			if (node.cls === "ScreenGui") this.styleLayer(node);
			else this.style(node);
		}
	}

	styleLayer(node) {
		const p = node.props;
		const s = node.el.style;
		s.display = p.Enabled === false ? "none" : "";
		s.zIndex = String(p.DisplayOrder || 0);
	}

	// The parent's way of placing children: "list", "grid" or "stack".
	modeOf(parent) {
		if (!parent || parent.cls === "ScreenGui") return "stack";
		if (parent.comps.UIListLayout) return "list";
		if (parent.comps.UIGridLayout) return "grid";
		return "stack";
	}

	style(node) {
		const p = node.props;
		const el = node.el;
		const s = el.style;
		const parent = node.parent;
		const mode = this.modeOf(parent);
		const auto = p.AutomaticSize || "None";
		const autoX = auto === "X" || auto === "XY";
		const autoY = auto === "Y" || auto === "XY";
		const size = p.Size || [0, 0, 0, 0];
		const constraint = node.comps.UISizeConstraint?.props;

		s.display = p.Visible === false ? "none" : "";
		// Width and height as UDims of the parent, with AutomaticSize growing
		// from the given size to fit what is inside.
		let width = udim(size[0], size[1]);
		let height = udim(size[2], size[3]);
		const flex = node.comps.UIFlexItem?.props;
		if (mode === "grid") {
			s.width = "";
			s.height = "";
			s.minWidth = "";
			s.minHeight = "";
		} else {
			s.width = autoX ? "max-content" : width;
			s.height = autoY ? "max-content" : height;
			let minW = autoX ? width : "";
			let minH = autoY ? height : "";
			if (constraint) {
				const min = constraint.MinSize || [0, 0];
				const max = constraint.MaxSize || [1e9, 1e9];
				if (min[0]) minW = minW ? `max(${minW}, ${px(min[0])})` : px(min[0]);
				if (min[1]) minH = minH ? `max(${minH}, ${px(min[1])})` : px(min[1]);
				s.maxWidth = max[0] < 1e8 ? px(max[0]) : "";
				s.maxHeight = max[1] < 1e8 ? px(max[1]) : "";
			} else {
				s.maxWidth = "";
				s.maxHeight = "";
			}
			s.minWidth = minW;
			s.minHeight = minH;
		}

		// Placement in the parent.
		const anchor = p.AnchorPoint || [0, 0];
		const position = p.Position || [0, 0, 0, 0];
		const scale = node.comps.UIScale?.props.Scale ?? 1;
		const rotation = p.Rotation || 0;
		if (mode === "stack") {
			s.gridArea = "1 / 1";
			s.justifySelf = "start";
			s.alignSelf = "start";
			s.order = "";
			s.flex = "";
			// Offsets as margins, so a parent that grows with its children
			// counts them; scale as a relative shift.
			s.marginLeft = px(position[1]);
			s.marginTop = px(position[3]);
			s.left = position[0] ? `${position[0] * 100}%` : "";
			s.top = position[2] ? `${position[2] * 100}%` : "";
			// The origin is the anchor point: Position places it, and UIScale
			// scales from it. Rotation turns about the centre, as Roblox
			// does, so the turn is wrapped in a shift to the centre and back.
			const shift = anchor[0] || anchor[1] ? `translate(${-anchor[0] * 100}%, ${-anchor[1] * 100}%)` : "";
			const grow = scale !== 1 ? ` scale(${scale})` : "";
			let spin = "";
			if (rotation) {
				const dx = (0.5 - anchor[0]) * 100;
				const dy = (0.5 - anchor[1]) * 100;
				spin = dx || dy ? ` translate(${dx}%, ${dy}%) rotate(${rotation}deg) translate(${-dx}%, ${-dy}%)` : ` rotate(${rotation}deg)`;
			}
			s.transform = `${shift}${grow}${spin}`.trim();
			s.transformOrigin = `${anchor[0] * 100}% ${anchor[1] * 100}%`;
		} else {
			s.gridArea = "";
			s.marginLeft = "";
			s.marginTop = "";
			s.left = "";
			s.top = "";
			s.justifySelf = "";
			s.alignSelf = "";
			s.order = String(p.LayoutOrder || 0);
			const spin = rotation ? `rotate(${rotation}deg)` : "";
			const grow = scale !== 1 ? ` scale(${scale})` : "";
			s.transform = `${spin}${grow}`.trim();
			s.transformOrigin = "50% 50%";
			if (mode === "list") {
				const layout = parent.comps.UIListLayout.props;
				const horizontal = layout.FillDirection === "Horizontal";
				const mainFill = horizontal ? layout.HorizontalFlex === "Fill" : layout.VerticalFlex === "Fill";
				const crossFill = horizontal ? layout.VerticalFlex === "Fill" : layout.HorizontalFlex === "Fill";
				let grow = 0;
				let shrink = 0;
				if (flex) {
					const modeName = flex.FlexMode;
					if (modeName === "Fill") (grow = 1), (shrink = 1);
					else if (modeName === "Grow") grow = 1;
					else if (modeName === "Shrink") shrink = 1;
					else if (modeName === "Custom") (grow = flex.GrowRatio ?? 1), (shrink = flex.ShrinkRatio ?? 1);
				}
				if (mainFill) (grow = Math.max(grow, 1)), (shrink = Math.max(shrink, 1));
				const basis = horizontal ? (autoX ? "auto" : width) : autoY ? "auto" : height;
				s.flex = `${grow} ${shrink} ${grow || shrink ? basis : "auto"}`;
				if (grow || shrink) {
					if (horizontal) s.minWidth = s.minWidth || "0";
					else s.minHeight = s.minHeight || "0";
				}
				s.alignSelf = crossFill ? "stretch" : "";
				if (crossFill) {
					if (horizontal) s.height = "auto";
					else s.width = "auto";
				}
			} else {
				s.flex = "";
			}
		}

		// Background, corners, outline and gradient.
		const transparency = p.BackgroundTransparency ?? 0;
		const gradient = node.comps.UIGradient?.props;
		if (gradient && gradient.Enabled !== false && transparency < 1) {
			const angle = 90 + (gradient.Rotation || 0);
			const base = p.BackgroundColor3 || [255, 255, 255];
			const colors = (gradient.Color || [[0, 255, 255, 255]]).map(
				(k) => `${rgb([(k[1] * base[0]) / 255, (k[2] * base[1]) / 255, (k[3] * base[2]) / 255], 1 - transparency)} ${k[0] * 100}%`,
			);
			s.backgroundColor = "transparent";
			s.backgroundImage = `linear-gradient(${angle}deg, ${colors.join(", ")})`;
			const fades = gradient.Transparency || [];
			s.maskImage = fades.length ? `linear-gradient(${angle}deg, ${fades.map((k) => `rgba(0,0,0,${1 - k[1]}) ${k[0] * 100}%`).join(", ")})` : "";
		} else {
			s.backgroundImage = "";
			s.maskImage = "";
			s.backgroundColor = transparency >= 1 ? "transparent" : rgb(p.BackgroundColor3, 1 - transparency);
		}
		const corner = node.comps.UICorner?.props.CornerRadius;
		s.borderRadius = corner ? (corner[0] >= 0.5 ? "9999px" : corner[0] ? `${corner[0] * 100}%` : px(corner[1])) : "";
		const stroke = node.comps.UIStroke?.props;
		const strokesText = stroke && TEXT.has(node.cls) && stroke.ApplyStrokeMode !== "Border" && p.Text;
		s.boxShadow =
			stroke && stroke.Enabled !== false && !strokesText && (stroke.Transparency ?? 0) < 1
				? `0 0 0 ${px(stroke.Thickness ?? 1)} ${rgb(stroke.Color, 1 - (stroke.Transparency ?? 0))}`
				: "";
		// A CanvasGroup draws its children into one picture, so it always clips.
		s.overflow = p.ClipsDescendants || node.cls === "ScrollingFrame" || node.cls === "CanvasGroup" ? "hidden" : "";
		s.opacity = node.cls === "CanvasGroup" ? String(1 - (p.GroupTransparency ?? 0)) : "";
		s.zIndex = String(p.ZIndex ?? 1);
		const aspect = node.comps.UIAspectRatioConstraint?.props.AspectRatio;
		s.aspectRatio = aspect ? String(aspect) : "";

		// How this element places its own children.
		this.styleBox(node, autoX, autoY);
		if (node.cls === "ScrollingFrame") this.styleScroll(node);
		if (TEXT.has(node.cls)) this.styleText(node, strokesText ? stroke : null);
		if (IMAGE.has(node.cls) && node.image) {
			node.image.style.zIndex = "0";
		}
		s.cursor = BUTTON.has(node.cls) ? "pointer" : "";
	}

	// Padding and the child layout of an element's box.
	styleBox(node, autoX, autoY) {
		const box = node.box;
		const s = box.style;
		const pad = node.comps.UIPadding?.props;
		const side = (u) => (u ? udim(u[0], u[1]) : "0px");
		const padding = pad ? `${side(pad.PaddingTop)} ${side(pad.PaddingRight)} ${side(pad.PaddingBottom)} ${side(pad.PaddingLeft)}` : "";
		if (node.cls !== "ScrollingFrame") s.padding = padding;
		const list = node.comps.UIListLayout?.props;
		const grid = node.comps.UIGridLayout?.props;
		if (list) {
			const horizontal = list.FillDirection === "Horizontal";
			s.display = "flex";
			s.flexDirection = horizontal ? "row" : "column";
			s.flexWrap = list.Wraps ? "wrap" : "nowrap";
			const gap = list.Padding ? udim(list.Padding[0], list.Padding[1]) : "0px";
			s.gap = gap;
			const hAlign = { Left: "flex-start", Center: "center", Right: "flex-end" }[list.HorizontalAlignment] || "flex-start";
			const vAlign = { Top: "flex-start", Center: "center", Bottom: "flex-end" }[list.VerticalAlignment] || "flex-start";
			s.justifyContent = horizontal ? hAlign : vAlign;
			s.alignItems = horizontal ? vAlign : hAlign;
			s.alignContent = list.Wraps ? (horizontal ? vAlign : hAlign) : "";
			s.gridTemplateColumns = "";
			s.gridTemplateRows = "";
		} else if (grid) {
			const cell = grid.CellSize || [0, 100, 0, 100];
			const pad = grid.CellPadding || [0, 5, 0, 5];
			s.display = "grid";
			const max = grid.FillDirectionMaxCells || 0;
			const cellW = udim(cell[0], cell[1]);
			const cellH = udim(cell[2], cell[3]);
			s.gridTemplateColumns = max > 0 ? `repeat(${max}, ${cellW})` : `repeat(auto-fill, ${cellW})`;
			s.gridAutoRows = cellH;
			s.gridTemplateRows = "";
			s.columnGap = udim(pad[0], pad[1]);
			s.rowGap = udim(pad[2], pad[3]);
			s.justifyContent = { Left: "start", Center: "center", Right: "end" }[grid.HorizontalAlignment] || "start";
			s.alignContent = { Top: "start", Center: "center", Bottom: "end" }[grid.VerticalAlignment] || "start";
			s.flexDirection = "";
			s.gap = "";
			for (const child of node.children) {
				if (child.el) {
					child.el.style.width = cellW;
					child.el.style.height = cellH;
				}
			}
		} else {
			s.display = node.props.Visible === false ? "none" : "grid";
			s.gridTemplateColumns = autoX ? "max-content" : "minmax(0, 1fr)";
			s.gridTemplateRows = autoY ? "max-content" : "minmax(0, 1fr)";
			s.flexDirection = "";
			s.gap = "";
			s.justifyContent = "";
			s.alignItems = "";
		}
		if (node.box === node.el && node.props.Visible === false) s.display = "none";
	}

	styleScroll(node) {
		const p = node.props;
		const s = node.el.style;
		const direction = p.ScrollingDirection || "XY";
		s.overflowX = direction === "Y" || p.ScrollingEnabled === false ? "hidden" : "auto";
		s.overflowY = direction === "X" || p.ScrollingEnabled === false ? "hidden" : "auto";
		node.el.classList.toggle("hc-nobar", (p.ScrollBarThickness ?? 12) <= 0);
		const canvas = node.canvas.style;
		const auto = p.AutomaticCanvasSize || "None";
		const size = p.CanvasSize || [0, 0, 2, 0];
		const pad = node.comps.UIPadding?.props;
		const side = (u) => (u ? udim(u[0], u[1]) : "0px");
		canvas.padding = pad ? `${side(pad.PaddingTop)} ${side(pad.PaddingRight)} ${side(pad.PaddingBottom)} ${side(pad.PaddingLeft)}` : "";
		const autoX = auto === "X" || auto === "XY";
		const autoY = auto === "Y" || auto === "XY";
		canvas.width = autoX ? "max-content" : size[0] || size[1] ? udim(size[0], size[1]) : "100%";
		canvas.height = autoY ? "max-content" : size[2] || size[3] ? udim(size[2], size[3]) : "100%";
		canvas.minWidth = "100%";
		canvas.minHeight = "100%";
		if (p.CanvasPosition && !node.scrolling) {
			const [x, y] = p.CanvasPosition;
			if (Math.abs(node.el.scrollLeft - x) > 0.5 || Math.abs(node.el.scrollTop - y) > 0.5) {
				node.el.scrollLeft = x;
				node.el.scrollTop = y;
			}
		}
	}

	styleText(node, stroke) {
		const p = node.props;
		const target = node.text || node.input;
		const s = target.style;
		const font = p.FontFace || ["", 400, "Normal"];
		s.fontWeight = String(font[1] || 400);
		s.fontStyle = font[2] === "Italic" ? "italic" : "";
		s.fontSize = px(p.TextSize ?? 14);
		const transparency = p.TextTransparency ?? 0;
		s.color = rgb(p.TextColor3, 1 - transparency);
		s.lineHeight = String(1.2 * (p.LineHeight ?? 1));
		if (node.input) {
			node.input.placeholder = p.PlaceholderText || "";
			node.input.style.setProperty("--placeholder", rgb(p.PlaceholderColor3 || [178, 178, 178], 1));
			s.textAlign = { Left: "left", Center: "center", Right: "right" }[p.TextXAlignment] || "center";
			if (document.activeElement !== node.input && node.input.value !== (p.Text ?? "")) node.input.value = p.Text ?? "";
			node.input.readOnly = p.TextEditable === false;
			return;
		}
		// The text sits in the element's own grid cell, so it sizes an element
		// that grows with its content. When the element lays out children
		// instead, the text lies over them and stays out of the layout.
		const laidOut = node.comps.UIListLayout || node.comps.UIGridLayout;
		s.position = laidOut ? "absolute" : "";
		s.inset = laidOut ? "0" : "";
		s.display = (p.Text ?? "") === "" ? "none" : "flex";
		const wrapped = p.TextWrapped === true;
		const truncate = p.TextTruncate && p.TextTruncate !== "None";
		s.whiteSpace = wrapped ? "pre-wrap" : "pre";
		s.justifyContent = { Left: "flex-start", Center: "center", Right: "flex-end" }[p.TextXAlignment] || "center";
		s.alignItems = { Top: "flex-start", Center: "center", Bottom: "flex-end" }[p.TextYAlignment] || "center";
		s.textAlign = { Left: "left", Center: "center", Right: "right" }[p.TextXAlignment] || "center";
		s.overflow = truncate ? "hidden" : "";
		node.inner.style.overflow = truncate ? "hidden" : "";
		node.inner.style.textOverflow = truncate ? "ellipsis" : "";
		node.inner.style.whiteSpace = truncate && !wrapped ? "pre" : "";
		node.inner.style.maxWidth = truncate ? "100%" : "";
		s.webkitTextStroke = stroke ? `${px(stroke.Thickness ?? 1)} ${rgb(stroke.Color, 1 - (stroke.Transparency ?? 0))}` : "";
	}

	renderText(node) {
		if (node.input) {
			if (document.activeElement !== node.input) node.input.value = node.props.Text ?? "";
			return;
		}
		if (!node.inner) return;
		const text = node.props.Text ?? "";
		if (node.props.RichText) node.inner.innerHTML = richText(text);
		else node.inner.textContent = text;
	}

	renderImage(node) {
		if (!node.image) return;
		const p = node.props;
		const name = node.attrs.HalcyonIcon;
		const image = p.Image || "";
		const color = rgb(p.ImageColor3 || [255, 255, 255], 1);
		const opacity = 1 - (p.ImageTransparency ?? 0);
		const el = node.image;
		el.style.opacity = String(opacity);
		el.style.color = color;
		if (image.includes(DISCORD_DECAL)) {
			el.innerHTML = icon("discord");
			el.className = "hc-image hc-icon hc-brand";
		} else if (ASSETS[image] || (name && image && hasIcon(name))) {
			el.innerHTML = icon(ASSETS[image] || name);
			el.className = "hc-image hc-icon";
		} else if (SHADOW_ASSETS.has(image)) {
			el.innerHTML = "";
			el.className = "hc-image hc-shadow";
		} else if (image.startsWith("rbxthumb://type=AvatarHeadShot")) {
			el.innerHTML = icon("user-round");
			el.className = "hc-image hc-icon hc-avatar";
		} else if (/^https?:\/\//.test(image)) {
			el.innerHTML = "";
			el.className = "hc-image hc-picture";
			el.style.backgroundImage = `url("${image.replace(/"/g, "%22")}")`;
		} else {
			el.innerHTML = "";
			el.className = "hc-image";
			el.style.backgroundImage = "";
		}
	}

	// Measures what the library reads back: every drawn element's place and
	// size, text bounds, canvas sizes, and each layout's content size.
	measure() {
		if (!this.measureAll) return null;
		this.measureAll = false;
		const origin = this.stage.getBoundingClientRect();
		const changed = [];
		const content = [];
		for (const node of this.nodes.values()) {
			if (!node.el) {
				if (node.cls === "UIListLayout" || node.cls === "UIGridLayout") {
					const parent = node.parent;
					if (parent?.box) {
						const size = contentSize(parent);
						const key = `${size[0]},${size[1]}`;
						if (this.content.get(node.id) !== key) {
							this.content.set(node.id, key);
							content.push([node.id, size[0], size[1]]);
						}
					}
				}
				continue;
			}
			// Roblox keeps a hidden object's size and text bounds; the page has
			// nothing to measure for it, so the last values stand. Hidden text
			// that changed is measured on a canvas instead.
			if (node.el.getClientRects().length === 0) {
				if (node.inner && node.measuredText !== node.props.Text) {
					node.measuredText = node.props.Text;
					const previous = this.rects.get(node.id);
					if (previous) {
						const bounds = textBounds(node);
						const entry = previous.split(",").map(Number);
						entry[5] = bounds[0];
						entry[6] = bounds[1];
						this.rects.set(node.id, entry.join(","));
						changed.push(entry);
					}
				}
				continue;
			}
			const r = node.el.getBoundingClientRect();
			const entry = [node.id, round(r.left - origin.left), round(r.top - origin.top), round(r.width), round(r.height)];
			if (node.inner) {
				const t = node.inner.getBoundingClientRect();
				node.measuredText = node.props.Text;
				entry.push(round(t.width), round(t.height));
			} else if (node.cls === "ScrollingFrame") {
				entry.push(null, null);
			}
			if (node.cls === "ScrollingFrame") entry.push(node.el.scrollWidth, node.el.scrollHeight);
			const key = entry.join(",");
			if (this.rects.get(node.id) !== key) {
				this.rects.set(node.id, key);
				changed.push(entry);
			}
		}
		return { m: changed, l: content };
	}

	// Input -----------------------------------------------------------------

	point(event) {
		const r = this.stage.getBoundingClientRect();
		return { x: Math.round(event.clientX - r.left), y: Math.round(event.clientY - r.top) };
	}

	// Every drawn element under the point, topmost first.
	under(event) {
		const found = [];
		const seen = new Set();
		for (const el of document.elementsFromPoint(event.clientX, event.clientY)) {
			const host = el.closest("[data-id]");
			if (!host || !this.root.contains(host)) continue;
			const id = Number(host.dataset.id);
			if (seen.has(id)) continue;
			seen.add(id);
			found.push(this.nodes.get(id));
		}
		return found.filter(Boolean);
	}

	// Where a press goes: down through elements that let input pass, to the
	// first button or other active element, which takes it.
	chain(event) {
		const chain = [];
		let button = null;
		let sunk = false;
		for (const node of this.under(event)) {
			if (node.cls === "ScreenGui") continue;
			chain.push(node.id);
			const active = node.props.Active === true || BUTTON.has(node.cls) || node.cls === "TextBox";
			if (BUTTON.has(node.cls) && !button) button = node.id;
			if (active) {
				sunk = true;
				break;
			}
		}
		return { chain, button, sunk };
	}

	hover(event) {
		const now = new Set(this.under(event).filter((n) => n.cls !== "ScreenGui").map((n) => n.id));
		const { x, y } = this.point(event);
		for (const id of this.hovered) if (!now.has(id)) this.onEvent({ t: "leave", id, x, y });
		for (const id of now) if (!this.hovered.has(id)) this.onEvent({ t: "enter", id, x, y });
		this.hovered = now;
	}

	bindInput() {
		const stage = this.stage;
		stage.addEventListener("pointermove", (event) => {
			const { x, y } = this.point(event);
			const { chain, sunk } = this.chain(event);
			this.onEvent({ t: "move", x, y, chain, sunk, touch: event.pointerType === "touch" });
			this.hover(event);
		});
		stage.addEventListener("pointerleave", (event) => {
			const { x, y } = this.point(event);
			for (const id of this.hovered) this.onEvent({ t: "leave", id, x, y });
			this.hovered = new Set();
		});
		stage.addEventListener("pointerdown", (event) => {
			const { x, y } = this.point(event);
			const target = this.chain(event);
			this.pressed = target.button;
			// A press on a text box focuses it even when a see-through frame
			// lies over it, as Roblox lets the press pass through.
			const last = this.nodes.get(target.chain[target.chain.length - 1]);
			if (last?.input && document.activeElement !== last.input) {
				event.preventDefault();
				last.input.focus();
			}
			// Keep receiving moves while dragging, even outside the stage.
			if (!event.target.closest(".hc-input")) stage.setPointerCapture?.(event.pointerId);
			this.onEvent({ t: "down", x, y, b: event.button === 2 ? 2 : 1, ...target, touch: event.pointerType === "touch" });
		});
		stage.addEventListener("pointerup", (event) => {
			const { x, y } = this.point(event);
			const target = this.chain(event);
			const click = target.button !== null && target.button === this.pressed;
			this.onEvent({ t: "up", x, y, b: event.button === 2 ? 2 : 1, ...target, button: this.pressed, click, touch: event.pointerType === "touch" });
			this.pressed = null;
			stage.releasePointerCapture?.(event.pointerId);
		});
		stage.addEventListener("contextmenu", (event) => event.preventDefault());
		// The wheel scrolls the topmost scrolling frame under the pointer that
		// can still move that way, through any see-through frames above it.
		stage.addEventListener(
			"wheel",
			(event) => {
				event.preventDefault();
				for (const node of this.under(event)) {
					if (node.cls !== "ScrollingFrame" || node.props.ScrollingEnabled === false) continue;
					const el = node.el;
					const vertical = Math.abs(event.deltaY) >= Math.abs(event.deltaX);
					const delta = vertical ? event.deltaY : event.deltaX;
					const room = vertical ? el.scrollHeight - el.clientHeight : el.scrollWidth - el.clientWidth;
					if (room <= 0) continue;
					const at = vertical ? el.scrollTop : el.scrollLeft;
					if ((delta > 0 && at >= room - 0.5) || (delta < 0 && at <= 0.5)) continue;
					if (vertical) el.scrollTop += delta;
					else el.scrollLeft += delta;
					break;
				}
			},
			{ passive: false },
		);
		const key = (down) => (event) => {
			const name = keyName(event);
			if (!name) return;
			const typing = event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement;
			if (!typing && (name === "Space" || name === "Tab" || name.startsWith("F") || name === "Up" || name === "Down")) {
				if (stage.matches(":hover")) event.preventDefault();
			}
			this.onEvent({ t: "key", k: name, down });
		};
		window.addEventListener("keydown", key(true));
		window.addEventListener("keyup", key(false));
	}

	bindTextBox(node, input) {
		input.addEventListener("input", () => this.onEvent({ t: "text", id: node.id, v: input.value }));
		input.addEventListener("focus", () => {
			if (node.props.ClearTextOnFocus) {
				input.value = "";
				this.onEvent({ t: "text", id: node.id, v: "" });
			}
			this.onEvent({ t: "focus", id: node.id, on: true });
		});
		input.addEventListener("blur", () => {
			this.onEvent({ t: "focus", id: node.id, on: false, enter: input.dataset.enter === "1" });
			input.dataset.enter = "";
		});
		input.addEventListener("keydown", (event) => {
			if (event.key === "Enter") {
				input.dataset.enter = "1";
				input.blur();
			}
		});
	}
}

function round(n) {
	return Math.round(n * 100) / 100;
}

let measuringContext = null;

// The width and height of a label's words on one line, for a label that
// isn't on screen to be measured.
function textBounds(node) {
	measuringContext ||= document.createElement("canvas").getContext("2d");
	const p = node.props;
	const size = p.TextSize ?? 14;
	const weight = (p.FontFace && p.FontFace[1]) || 400;
	measuringContext.font = `${weight} ${size}px Inter, system-ui, sans-serif`;
	const text = String(p.Text ?? "");
	return [round(text ? measuringContext.measureText(text).width : 0), round(text ? size * 1.2 : 0)];
}

// The size of everything a layout arranges inside `parent`.
function contentSize(parent) {
	const box = parent.box;
	const r = box.getBoundingClientRect();
	let right = 0;
	let bottom = 0;
	for (const child of parent.children) {
		if (!child.el || child.props.Visible === false) continue;
		const c = child.el.getBoundingClientRect();
		right = Math.max(right, c.right - r.left);
		bottom = Math.max(bottom, c.bottom - r.top);
	}
	const cs = getComputedStyle(box);
	const left = parseFloat(cs.paddingLeft) || 0;
	const top = parseFloat(cs.paddingTop) || 0;
	return [round(Math.max(right - left, 0)), round(Math.max(bottom - top, 0))];
}

const KEYS = {
	Space: "Space",
	Enter: "Return",
	Escape: "Escape",
	Backspace: "Backspace",
	Tab: "Tab",
	Delete: "Delete",
	Insert: "Insert",
	Home: "Home",
	End: "End",
	PageUp: "PageUp",
	PageDown: "PageDown",
	ArrowUp: "Up",
	ArrowDown: "Down",
	ArrowLeft: "Left",
	ArrowRight: "Right",
	ShiftLeft: "LeftShift",
	ShiftRight: "RightShift",
	ControlLeft: "LeftControl",
	ControlRight: "RightControl",
	AltLeft: "LeftAlt",
	AltRight: "RightAlt",
	Minus: "Minus",
	Equal: "Equals",
	BracketLeft: "LeftBracket",
	BracketRight: "RightBracket",
	Semicolon: "Semicolon",
	Quote: "Quote",
	Comma: "Comma",
	Period: "Period",
	Slash: "Slash",
	Backslash: "BackSlash",
	Backquote: "Backquote",
	CapsLock: "CapsLock",
};
const DIGITS = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"];

function keyName(event) {
	const code = event.code;
	if (KEYS[code]) return KEYS[code];
	if (/^Key[A-Z]$/.test(code)) return code.slice(3);
	if (/^Digit[0-9]$/.test(code)) return DIGITS[Number(code.slice(5))];
	if (/^F([1-9]|1[0-2])$/.test(code)) return code;
	return null;
}

// Roblox rich text to HTML: only the tags Roblox supports, everything else
// escaped, so text from a hub can never inject markup into the page.
function richText(text) {
	const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
	let out = "";
	const pattern = /<(\/?)(b|i|u|s|br|font|stroke|uc|sc)([^>]*)>/gi;
	let last = 0;
	let match;
	while ((match = pattern.exec(text))) {
		out += escape(text.slice(last, match.index));
		last = pattern.lastIndex;
		const closing = match[1] === "/";
		const tag = match[2].toLowerCase();
		if (tag === "br") {
			out += "<br>";
		} else if (tag === "font") {
			if (closing) out += "</span>";
			else {
				const attrs = match[3];
				const color = /color="(#[0-9a-f]{3,6}|rgb\(\d+,\s*\d+,\s*\d+\))"/i.exec(attrs)?.[1];
				const size = /size="(\d+)"/i.exec(attrs)?.[1];
				const fade = /transparency="([0-9.]+)"/i.exec(attrs)?.[1];
				const weight = /weight="(\w+)"/i.exec(attrs)?.[1];
				const styles = [];
				if (color) styles.push(`color:${color}`);
				if (size) styles.push(`font-size:${Number(size)}px`);
				if (fade) styles.push(`opacity:${1 - Number(fade)}`);
				if (weight) styles.push(`font-weight:${/^\d+$/.test(weight) ? weight : { bold: 700, medium: 500, semibold: 600, regular: 400, light: 300 }[weight.toLowerCase()] || 400}`);
				out += `<span style="${styles.join(";")}">`;
			}
		} else if (["b", "i", "u", "s"].includes(tag)) {
			out += closing ? `</${tag}>` : `<${tag}>`;
		} else {
			out += closing ? "</span>" : "<span>";
		}
	}
	return out + escape(text.slice(last));
}
