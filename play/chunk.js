// Joins the engine, the library and the example into one Luau chunk. The
// library and the example each run inside a function, so their locals stay
// their own while the engine's locals serve as their globals.
export function buildChunk({ engine, library, example }) {
	return [
		engine,
		"local __library = function()",
		library,
		"end",
		"local __example = function()",
		example,
		"end",
		"return function(stored, width, height, touch)",
		"\treturn Engine.start(__library, __example, stored, width, height, touch)",
		"end, Engine.step",
	].join("\n");
}
