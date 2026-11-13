// Runs the demo's chunk under the standalone `luau` binary: boots the
// example, steps a few seconds of frames and reports errors and how much
// the page would be sent. Faster to iterate on than the browser.
//
//   node tests/engine-cli.mjs [path to the library repo]
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildChunk } from "../play/chunk.js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const LIBRARY = process.argv[2] || join(ROOT, "..", "YaxUI");
const read = (path) => readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const chunk = buildChunk({
	engine: read(join(ROOT, "play", "engine", "roblox.luau")),
	library: read(join(LIBRARY, "dist", "Halcyon.luau")),
	// The hub builds only after the key prompt; skip it so all of it is checked.
	example: read(join(LIBRARY, "example", "Example.luau")).replace("KeySystem = {", 'Tiers = { "Free", "Paid" }, Tier = "Free", UnusedKeySystem = {'),
});

const harness = [
	"local errors, warnings = 0, 0",
	"__host_log = function(kind, text)",
	"\tif kind == 'error' then errors += 1; print('ERROR', text) elseif kind == 'warn' then warnings += 1; print('WARN', text) end",
	"end",
	"__host_copy = function() end",
	"local start, step = (function()",
	chunk,
	"end)()",
	"local began = os.clock()",
	"start(nil, 1280, 720, false)",
	"local total, frames, kinds = 0, 0, {}",
	"for i = 1, 240 do",
	"\tlocal out = step(1 / 60, '')",
	"\tframes += 1",
	"\ttotal += #out",
	"end",
	"print(string.format('booted and stepped 240 frames in %.2fs; %d bytes of changes; %d errors, %d warnings', os.clock() - began, total, errors, warnings))",
].join("\n");

mkdirSync(join(ROOT, ".build"), { recursive: true });
const file = join(ROOT, ".build", "engine-cli.luau");
writeFileSync(file, harness);
try {
	const output = execFileSync(process.env.LUAU_BIN || "luau", [file], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
	process.stdout.write(output.split("\n").slice(-40).join("\n"));
} catch (error) {
	process.stdout.write(String(error.stdout || "").split("\n").slice(-40).join("\n"));
	process.stderr.write(String(error.stderr || error.message));
	process.exit(1);
}
