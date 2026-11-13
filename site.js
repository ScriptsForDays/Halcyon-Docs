(() => {
	const root = document.documentElement;
	root.classList.remove("no-js");

	const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
	const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)");

	// Theme: follows the system until the visitor picks one, then remembers it.
	const THEME_KEY = "halcyon-docs-theme";
	const readTheme = () => {
		try {
			return localStorage.getItem(THEME_KEY);
		} catch {
			return null;
		}
	};
	const saved = readTheme();
	if (saved === "light" || saved === "dark") {
		root.dataset.theme = saved;
	}
	const currentTheme = () =>
		root.dataset.theme || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
	const syncThemeMeta = () => {
		const meta = document.querySelector('meta[name="theme-color"]');
		if (meta) {
			meta.content = currentTheme() === "dark" ? "#0d0f13" : "#f8f9fb";
		}
	};
	syncThemeMeta();
	document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
		button.addEventListener("click", () => {
			const next = currentTheme() === "dark" ? "light" : "dark";
			root.dataset.theme = next;
			try {
				localStorage.setItem(THEME_KEY, next);
			} catch {
				// Private windows can refuse storage; the choice still holds for this visit.
			}
			syncThemeMeta();
			button.setAttribute("aria-label", next === "dark" ? "Switch to light theme" : "Switch to dark theme");
		});
	});

	// Copy buttons on code blocks: the label confirms in place, no toast.
	document.querySelectorAll(".code").forEach((block) => {
		const button = block.querySelector(".copy");
		const source = block.querySelector("pre");
		if (!button || !source) {
			return;
		}
		let timer;
		button.addEventListener("click", async () => {
			const text = source.innerText.trimEnd();
			try {
				await navigator.clipboard.writeText(text);
			} catch {
				const range = document.createRange();
				range.selectNodeContents(source);
				const selection = window.getSelection();
				selection.removeAllRanges();
				selection.addRange(range);
				return;
			}
			button.dataset.copied = "";
			button.querySelector(".copy__label").textContent = "Copied";
			clearTimeout(timer);
			timer = setTimeout(() => {
				delete button.dataset.copied;
				button.querySelector(".copy__label").textContent = "Copy";
			}, 1600);
		});
	});

	// Reveal sections as they enter the viewport, once each.
	const revealables = document.querySelectorAll("[data-reveal]");
	if (reducedMotion.matches || !("IntersectionObserver" in window)) {
		revealables.forEach((element) => (element.dataset.shown = ""));
	} else {
		const observer = new IntersectionObserver(
			(entries) => {
				entries.forEach((entry) => {
					if (entry.isIntersecting) {
						entry.target.dataset.shown = "";
						observer.unobserve(entry.target);
					}
				});
			},
			{ rootMargin: "0px 0px -8% 0px", threshold: 0.12 }
		);
		revealables.forEach((element) => observer.observe(element));
	}

	// The hero switcher: each tab shows a real screenshot of that look.
	const switcher = document.querySelector("[data-switcher]");
	if (switcher) {
		const tabs = [...switcher.querySelectorAll("[role=tab]")];
		const frame = document.querySelector("[data-shots]");
		const caption = document.querySelector("[data-shot-caption]");
		const show = (tab, focus) => {
			tabs.forEach((other) => {
				const active = other === tab;
				other.setAttribute("aria-selected", String(active));
				other.tabIndex = active ? 0 : -1;
			});
			frame.querySelectorAll("img").forEach((image) => {
				if (image.dataset.look === tab.dataset.look) {
					image.dataset.active = "";
					frame.setAttribute("aria-label", image.alt);
				} else {
					delete image.dataset.active;
				}
			});
			if (caption) {
				caption.textContent = tab.dataset.caption || "";
			}
			if (focus) {
				tab.focus();
			}
		};
		tabs.forEach((tab, index) => {
			tab.addEventListener("click", () => show(tab));
			tab.addEventListener("keydown", (event) => {
				const step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
				if (step) {
					event.preventDefault();
					show(tabs[(index + step + tabs.length) % tabs.length], true);
				}
			});
		});
	}

	// The product shot leans a few degrees toward the pointer.
	const tilt = document.querySelector("[data-tilt]");
	if (tilt && finePointer.matches && !reducedMotion.matches) {
		const area = tilt.parentElement;
		area.addEventListener("pointermove", (event) => {
			const box = area.getBoundingClientRect();
			const x = (event.clientX - box.left) / box.width - 0.5;
			const y = (event.clientY - box.top) / box.height - 0.5;
			tilt.style.setProperty("--tilt-y", `${(x * 5).toFixed(2)}deg`);
			tilt.style.setProperty("--tilt-x", `${(-y * 4).toFixed(2)}deg`);
		});
		area.addEventListener("pointerleave", () => {
			tilt.style.setProperty("--tilt-y", "0deg");
			tilt.style.setProperty("--tilt-x", "0deg");
		});
	}

	// Docs: the table of contents follows the section being read.
	const tocLinks = [...document.querySelectorAll(".toc__list a[href^='#']")];
	if (tocLinks.length) {
		const sections = tocLinks
			.map((link) => [link, document.getElementById(link.getAttribute("href").slice(1))])
			.filter(([, section]) => section);
		let queued = false;
		// The current section is the last one whose top has passed the nav.
		const mark = () => {
			queued = false;
			let current = sections[0];
			for (const entry of sections) {
				if (entry[1].getBoundingClientRect().top <= 140) {
					current = entry;
				}
			}
			tocLinks.forEach((link) => link.removeAttribute("aria-current"));
			current[0].setAttribute("aria-current", "true");
		};
		window.addEventListener(
			"scroll",
			() => {
				if (!queued) {
					queued = true;
					requestAnimationFrame(mark);
				}
			},
			{ passive: true }
		);
		mark();
	}

	const toc = document.querySelector(".toc");
	const tocToggle = document.querySelector(".toc__toggle");
	if (toc && tocToggle) {
		tocToggle.addEventListener("click", () => {
			const open = toc.toggleAttribute("data-open");
			tocToggle.setAttribute("aria-expanded", String(open));
		});
		toc.querySelectorAll(".toc__list a").forEach((link) =>
			link.addEventListener("click", () => {
				if (toc.hasAttribute("data-open")) {
					toc.removeAttribute("data-open");
					tocToggle.setAttribute("aria-expanded", "false");
				}
			})
		);
	}

	// Tap: a soft circle grows out from wherever a link, button or tab is
	// pressed and fades, like a touch on a phone. The pointer itself is
	// left alone. Nothing plays when the visitor asks for less motion.
	const pressable = "a, button, [role=tab], summary, label, .shot__frame";
	document.addEventListener(
		"pointerdown",
		(event) => {
			if (reducedMotion.matches || event.button !== 0) {
				return;
			}
			const target = event.target instanceof Element ? event.target.closest(pressable) : null;
			if (!target) {
				return;
			}
			const tap = document.createElement("span");
			tap.className = "tap";
			tap.setAttribute("aria-hidden", "true");
			tap.style.left = `${event.clientX}px`;
			tap.style.top = `${event.clientY}px`;
			tap.addEventListener("animationend", () => tap.remove(), { once: true });
			document.body.append(tap);
		},
		{ passive: true }
	);
})();
