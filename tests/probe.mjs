// A quick look at how luau-web passes values each way, before building on it.
setTimeout(() => { console.log("timed out"); process.exit(1); }, 30000);
import { LuauState } from "../play/vendor/luau-web/index.js";

const calls = [];
const state = await LuauState.createAsync({
	hostAdd: (a, b) => a + b,
	hostLog: (text) => calls.push(String(text)),
	hostPair: () => [3, 4],
	hostObject: () => ({ x: 1, y: 2 }),
});

const chunk = state.loadstring(
	`
	local list = {}
	for i = 1, 5 do list[i] = i * 2 end
	hostLog("sum " .. hostAdd(2, 3))
	local p1, p2 = hostPair()
	hostLog("pair " .. tostring(p1) .. "," .. tostring(p2))
	local object = hostObject()
	hostLog("object " .. typeof(object) .. " " .. tostring(object.x))
	local co = coroutine.create(function(x)
		local y = coroutine.yield(x + 1)
		return y * 2
	end)
	local _, a = coroutine.resume(co, 1)
	local _, b = coroutine.resume(co, 10)
	hostLog(("co %s %s"):format(a, b))
	hostLog(("interp %s"):format(\`{1 + 1}\`))
	local t = { a = 1 }
	t.a += 2
	hostLog("compound " .. t.a)
	return list, function(v) return v * 3 end, "done"
	`,
	"probe",
	true,
);
const result = await chunk();
console.log("calls", calls);
console.log("result type", Array.isArray(result), typeof result, result);

// Speed: a Luau loop calling into JS.
const timed = state.loadstring(
	`
	local start = os.clock()
	local n = 0
	for i = 1, 20000 do n = hostAdd(n, 1) end
	return n, os.clock() - start
	`,
	"timed",
	true,
);
console.log("timed", await timed());
process.exit(0);
