// Copies the library build and the example hub into play/lib for the demo.
//
//   node scripts/sync-library.mjs            from ../YaxUI, the library checkout
//   node scripts/sync-library.mjs --remote   from the library's main branch
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const RAW = "https://raw.githubusercontent.com/ScriptsForDays/Halcyon/main/";
const FILES = { "Halcyon.luau": "dist/Halcyon.luau", "Example.luau": "example/Example.luau" };
const remote = process.argv.includes("--remote");
const local = process.argv.find((arg, index) => index > 1 && !arg.startsWith("--")) || join(ROOT, "..", "YaxUI");

mkdirSync(join(ROOT, "play", "lib"), { recursive: true });
for (const [name, path] of Object.entries(FILES)) {
	let text;
	if (remote) {
		const response = await fetch(RAW + path);
		if (!response.ok) throw new Error(`${path}: ${response.status}`);
		text = await response.text();
	} else {
		text = readFileSync(join(local, path), "utf8");
	}
	writeFileSync(join(ROOT, "play", "lib", name), text.replace(/\r\n/g, "\n"));
	console.log(`${name}: ${text.length} characters`);
}
