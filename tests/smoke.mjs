// Boots the demo the way the page does, but under Node: the vendored
// luau-web runtime, the engine, and the library and example that
// scripts/sync-library.mjs put in play/lib. Fails on any Luau error, or if
// the hub never draws its tabs. The Pages workflow runs it before deploying.
//
//   node scripts/sync-library.mjs --remote && node tests/smoke.mjs
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { LuauState } from "../play/vendor/luau-web/index.js";
import { buildChunk } from "../play/chunk.js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(join(ROOT, path), "utf8");
const timer = setTimeout(() => {
	console.error("The demo did not finish booting within 60 seconds.");
	process.exit(1);
}, 60000);

const problems = [];
const state = await LuauState.createAsync({
	__host_log: (kind, text) => {
		if (kind === "error") problems.push(String(text));
	},
	__host_copy: () => {},
});

// The hub only builds after its key prompt, so skip the prompt here and
// check the whole hub instead.
const example = read("play/lib/Example.luau").replace(
	"KeySystem = {",
	'Tiers = { "Free", "Paid" }, Tier = "Free", UnusedKeySystem = {',
);
const chunk = state.loadstring(
	buildChunk({ engine: read("play/engine/roblox.luau"), library: read("play/lib/Halcyon.luau"), example }),
	"halcyon-demo",
	true,
);
const [start, step] = await chunk();
await start("", 1280, 800, false);

const texts = new Set();
let changes = 0;
for (let frame = 0; frame < 120; frame++) {
	const ops = JSON.parse(await step(1 / 60, JSON.stringify({ e: [] })));
	changes += ops.length;
	for (const op of ops) {
		if (op[0] === "p" && op[2] === "Text") texts.add(op[3]);
	}
}
clearTimeout(timer);

for (const tab of ["Dashboard", "Components", "Settings"]) {
	if (!texts.has(tab)) problems.push(`The ${tab} tab was never drawn.`);
}
if (problems.length > 0) {
	console.error(problems.join("\n"));
	process.exit(1);
}
console.log(`The demo booted: ${changes} changes over 120 frames, no errors.`);
