// Starts the demo: loads Luau, runs the real Halcyon library and its example
// hub in it, and steps it once per animation frame. Each step sends what the
// player did and what the page measured, and gets back what changed.
import { LuauState } from "./vendor/luau-web/index.js";
import { Renderer } from "./render.js";
import { buildChunk } from "./chunk.js";

const STORE = "halcyon-demo-files";

function readStore() {
	try {
		return localStorage.getItem(STORE) || "";
	} catch {
		return "";
	}
}

function writeStore(files) {
	try {
		localStorage.setItem(STORE, JSON.stringify(files));
	} catch {
		// Private windows and blocked storage: the demo still runs, it just forgets.
	}
}

export function resetStore() {
	try {
		localStorage.removeItem(STORE);
	} catch {
		// Nothing saved, nothing to clear.
	}
}

export async function boot(stage, onStatus) {
	onStatus("Loading Luau");
	const [engine, library, example] = await Promise.all(
		["engine/roblox.luau", "lib/Halcyon.luau", "lib/Example.luau"].map((path) =>
			fetch(new URL(path, import.meta.url)).then((response) => {
				if (!response.ok) throw new Error(`Couldn't load ${path} (${response.status})`);
				return response.text();
			}),
		),
	);

	const state = await LuauState.createAsync({
		__host_log: (kind, text) => {
			const write = kind === "error" ? console.error : kind === "warn" ? console.warn : console.log;
			write(`[halcyon] ${text}`);
		},
		__host_copy: (text) => {
			navigator.clipboard?.writeText(String(text)).catch(() => {});
		},
	});

	onStatus("Building the hub");
	const chunk = state.loadstring(buildChunk({ engine, library, example }), "halcyon-demo", true);
	const [start, step] = await chunk();

	const events = [];
	const renderer = new Renderer(stage, (event) => events.push(event));
	const stored = readStore();
	const files = stored ? JSON.parse(stored) : {};
	const touch = matchMedia("(pointer: coarse)").matches;
	let width = stage.clientWidth;
	let height = stage.clientHeight;
	await start(stored, width, height, touch);

	let saveTimer = 0;
	const save = () => {
		clearTimeout(saveTimer);
		saveTimer = setTimeout(() => writeStore(files), 250);
	};

	let last = performance.now();
	let first = true;
	const frame = async (now) => {
		const dt = Math.min(Math.max((now - last) / 1000, 0), 0.1);
		last = now;
		renderer.flush();
		const payload = { e: events.splice(0) };
		const measured = renderer.measure();
		if (measured) {
			if (measured.m.length) payload.m = measured.m;
			if (measured.l.length) payload.l = measured.l;
		}
		if (stage.clientWidth !== width || stage.clientHeight !== height) {
			width = stage.clientWidth;
			height = stage.clientHeight;
			payload.w = width;
			payload.h = height;
		}
		let ops;
		try {
			ops = JSON.parse(await step(dt, JSON.stringify(payload)));
		} catch (error) {
			console.error("[halcyon] step failed", error);
			ops = [];
		}
		const drawn = [];
		for (const op of ops) {
			if (op[0] === "w") {
				if (op[2] === undefined || op[2] === null) delete files[op[1]];
				else files[op[1]] = op[2];
				save();
			} else {
				drawn.push(op);
			}
		}
		renderer.apply(drawn);
		// Style what just arrived before the browser paints, so new elements
		// never show for a frame as bare, unplaced text.
		renderer.flush();
		if (first && drawn.length) {
			first = false;
			onStatus(null);
		}
		requestAnimationFrame(frame);
	};
	requestAnimationFrame(frame);
}
