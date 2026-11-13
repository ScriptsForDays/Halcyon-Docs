-- A small Roblox for the browser demo. The page draws the instances as HTML;
-- calls between Luau and the page are slow, so changes cross in one batch a
-- frame. The page joins this file, the library and the example into one
-- chunk, so the library reads the locals below as its globals.

local Engine = { now = 0, frame = 0 }

-- Functions the page provides, as globals set before the chunk runs.
local hostLog, hostCopy = __host_log, __host_copy

local function typeof(value)
	local kind = type(value)
	if kind == "table" then
		local meta = getmetatable(value)
		if type(meta) == "table" and rawget(meta, "__type") then
			return meta.__type
		end
	end
	return kind
end

local function join(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring((select(index, ...)))
	end
	return table.concat(parts, " ")
end

local function print(...)
	hostLog("print", join(...))
end

local function warn(...)
	hostLog("warn", join(...))
end

-- Scheduler -----------------------------------------------------------------

local task = {}
local timers, deferred = {}, {}

-- Roblox's time(): seconds since the game started running.
local function time()
	return Engine.now
end
local cancelled = setmetatable({}, { __mode = "k" })

local function resume(thread, ...)
	if cancelled[thread] or coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, message = coroutine.resume(thread, ...)
	if not ok then
		hostLog("error", debug.traceback(thread, tostring(message)))
	end
end

local function toThread(target)
	return if type(target) == "thread" then target else coroutine.create(target)
end

function task.spawn(target, ...)
	local thread = toThread(target)
	resume(thread, ...)
	return thread
end

function task.defer(target, ...)
	local thread = toThread(target)
	table.insert(deferred, { thread = thread, args = table.pack(...) })
	return thread
end

function task.delay(seconds, target, ...)
	local thread = toThread(target)
	table.insert(timers, { at = Engine.now + (seconds or 0), thread = thread, args = table.pack(...), from = Engine.now })
	return thread
end

function task.wait(seconds)
	seconds = seconds or 0
	table.insert(timers, { at = Engine.now + seconds, thread = coroutine.running(), wait = true, from = Engine.now })
	return coroutine.yield()
end

function task.cancel(thread)
	cancelled[thread] = true
end

local function flushDeferred()
	local rounds = 0
	while #deferred > 0 and rounds < 100 do
		rounds += 1
		local batch = deferred
		deferred = {}
		for _, entry in batch do
			resume(entry.thread, table.unpack(entry.args, 1, entry.args.n))
		end
	end
end

-- Runs every timer that is due, oldest first.
local function runTimers()
	local due = {}
	local index = 1
	while index <= #timers do
		local timer = timers[index]
		if timer.at <= Engine.now then
			table.insert(due, timer)
			table.remove(timers, index)
		else
			index += 1
		end
	end
	table.sort(due, function(a, b)
		return a.at < b.at
	end)
	for _, timer in due do
		if timer.wait then
			resume(timer.thread, Engine.now - timer.from)
		else
			resume(timer.thread, table.unpack(timer.args, 1, timer.args.n))
		end
		flushDeferred()
	end
end

-- Signals -------------------------------------------------------------------

local SignalMeta = { __type = "RBXScriptSignal" }
SignalMeta.__index = SignalMeta
local ConnectionMeta = { __type = "RBXScriptConnection" }
ConnectionMeta.__index = ConnectionMeta

function ConnectionMeta:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local index = table.find(self.signal.list, self)
	if index then
		table.remove(self.signal.list, index)
	end
end

local function newSignal()
	return setmetatable({ list = {} }, SignalMeta)
end

function SignalMeta:Connect(handler)
	local connection = setmetatable({ signal = self, handler = handler, Connected = true }, ConnectionMeta)
	table.insert(self.list, connection)
	return connection
end

function SignalMeta:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function SignalMeta:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function SignalMeta:Fire(...)
	if #self.list == 0 then
		return
	end
	for _, connection in table.clone(self.list) do
		if connection.Connected then
			task.spawn(connection.handler, ...)
		end
	end
end

-- Datatypes -----------------------------------------------------------------

local function valueType(name)
	local meta = { __type = name }
	meta.__index = meta
	return meta
end

local Color3Meta = valueType("Color3")
local Color3 = {}

function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta)
end

function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

function Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	if #hex == 3 then
		hex = string.gsub(hex, ".", "%0%0")
	end
	assert(#hex == 6 and not string.find(hex, "%X"), "invalid hex colour")
	return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
end

function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local sector = i % 6
	if sector == 0 then
		return Color3.new(v, t, p)
	elseif sector == 1 then
		return Color3.new(q, v, p)
	elseif sector == 2 then
		return Color3.new(p, v, t)
	elseif sector == 3 then
		return Color3.new(p, q, v)
	elseif sector == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end

function Color3.toHSV(color)
	return color:ToHSV()
end

Color3Meta.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end

Color3Meta.__tostring = function(self)
	return string.format("%g, %g, %g", self.R, self.G, self.B)
end

function Color3Meta:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local high, low = math.max(r, g, b), math.min(r, g, b)
	local delta = high - low
	local h = 0
	if delta > 0 then
		if high == r then
			h = ((g - b) / delta) % 6
		elseif high == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end
	return h, if high == 0 then 0 else delta / high, high
end

function Color3Meta:ToHex()
	return string.format("%02x%02x%02x", math.round(self.R * 255), math.round(self.G * 255), math.round(self.B * 255))
end

function Color3Meta:Lerp(goal, alpha)
	return Color3.new(self.R + (goal.R - self.R) * alpha, self.G + (goal.G - self.G) * alpha, self.B + (goal.B - self.B) * alpha)
end

local Vector2Meta = valueType("Vector2")
local Vector2 = {}

function Vector2.new(x, y)
	x, y = x or 0, y or 0
	return setmetatable({ X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }, Vector2Meta)
end

Vector2Meta.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
Vector2Meta.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
Vector2Meta.__unm = function(a)
	return Vector2.new(-a.X, -a.Y)
end
Vector2Meta.__mul = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	elseif type(a) == "number" then
		return Vector2.new(a * b.X, a * b.Y)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
Vector2Meta.__div = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X / b, a.Y / b)
	end
	return Vector2.new(a.X / b.X, a.Y / b.Y)
end
Vector2Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2Meta.__tostring = function(self)
	return string.format("%g, %g", self.X, self.Y)
end
function Vector2Meta:Lerp(goal, alpha)
	return Vector2.new(self.X + (goal.X - self.X) * alpha, self.Y + (goal.Y - self.Y) * alpha)
end
function Vector2Meta:Dot(other)
	return self.X * other.X + self.Y * other.Y
end
function Vector2Meta:Min(other)
	return Vector2.new(math.min(self.X, other.X), math.min(self.Y, other.Y))
end
function Vector2Meta:Max(other)
	return Vector2.new(math.max(self.X, other.X), math.max(self.Y, other.Y))
end
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)
Vector2.xAxis = Vector2.new(1, 0)
Vector2.yAxis = Vector2.new(0, 1)

local Vector3Meta = valueType("Vector3")
local Vector3 = {}

function Vector3.new(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return setmetatable({ X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }, Vector3Meta)
end

Vector3Meta.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Meta.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Meta.__mul = function(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)

local UDimMeta = valueType("UDim")
local UDim = {}

function UDim.new(scale, offset)
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDimMeta)
end

UDimMeta.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDimMeta.__add = function(a, b)
	return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDimMeta.__sub = function(a, b)
	return UDim.new(a.Scale - b.Scale, a.Offset - b.Offset)
end

local UDim2Meta = valueType("UDim2")
local UDim2 = {}

function UDim2.new(xScale, xOffset, yScale, yOffset)
	if typeof(xScale) == "UDim" then
		return setmetatable({ X = xScale, Y = xOffset, Width = xScale, Height = xOffset }, UDim2Meta)
	end
	local x, y = UDim.new(xScale, xOffset), UDim.new(yScale, yOffset)
	return setmetatable({ X = x, Y = y, Width = x, Height = y }, UDim2Meta)
end

function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end

function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end

UDim2Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UDim2Meta.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UDim2Meta.__sub = function(a, b)
	return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UDim2Meta.__tostring = function(self)
	return string.format("{%g, %g}, {%g, %g}", self.X.Scale, self.X.Offset, self.Y.Scale, self.Y.Offset)
end
function UDim2Meta:Lerp(goal, alpha)
	return UDim2.new(
		self.X.Scale + (goal.X.Scale - self.X.Scale) * alpha,
		self.X.Offset + (goal.X.Offset - self.X.Offset) * alpha,
		self.Y.Scale + (goal.Y.Scale - self.Y.Scale) * alpha,
		self.Y.Offset + (goal.Y.Offset - self.Y.Offset) * alpha
	)
end

local CFrameMeta = valueType("CFrame")
local CFrame = {}

function CFrame.new(x, y, z)
	local position = if typeof(x) == "Vector3" then x else Vector3.new(x, y, z)
	return setmetatable({ Position = position, LookVector = Vector3.new(0, 0, -1) }, CFrameMeta)
end
CFrame.Angles = function()
	return CFrame.new()
end
CFrame.lookAt = function(origin)
	return CFrame.new(origin)
end
CFrameMeta.__mul = function(a, b)
	if typeof(b) == "Vector3" then
		return a.Position + b
	end
	return CFrame.new(a.Position + b.Position)
end

local RectMeta = valueType("Rect")
local Rect = {}
function Rect.new(a, b, c, d)
	if typeof(a) == "Vector2" then
		return setmetatable({ Min = a, Max = b, Width = b.X - a.X, Height = b.Y - a.Y }, RectMeta)
	end
	a, b, c, d = a or 0, b or 0, c or 0, d or 0
	return setmetatable({ Min = Vector2.new(a, b), Max = Vector2.new(c, d), Width = c - a, Height = d - b }, RectMeta)
end

local NumberRangeMeta = valueType("NumberRange")
local NumberRange = {}
function NumberRange.new(min, max)
	return setmetatable({ Min = min, Max = max or min }, NumberRangeMeta)
end

local KeypointMeta = valueType("NumberSequenceKeypoint")
local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(time, value, envelope)
	return setmetatable({ Time = time, Value = value, Envelope = envelope or 0 }, KeypointMeta)
end

local NumberSequenceMeta = valueType("NumberSequence")
local NumberSequence = {}
function NumberSequence.new(a, b)
	local keypoints
	if type(a) == "table" then
		keypoints = a
	else
		keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, if b == nil then a else b) }
	end
	return setmetatable({ Keypoints = keypoints }, NumberSequenceMeta)
end

local ColorKeypointMeta = valueType("ColorSequenceKeypoint")
local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(time, value)
	return setmetatable({ Time = time, Value = value }, ColorKeypointMeta)
end

local ColorSequenceMeta = valueType("ColorSequence")
local ColorSequence = {}
function ColorSequence.new(a, b)
	local keypoints
	if typeof(a) == "Color3" then
		keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	else
		keypoints = a
	end
	return setmetatable({ Keypoints = keypoints }, ColorSequenceMeta)
end

local FontMeta = valueType("Font")
local Font = {}

function Font.new(family, weight, style)
	return setmetatable({ Family = family, Weight = weight, Style = style }, FontMeta)
end

function Font.fromEnum(font)
	return Font.new("rbxasset://fonts/families/" .. font.Name .. ".json")
end

function Font.fromName(name, weight, style)
	return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end

FontMeta.__eq = function(a, b)
	return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end

-- Enums ---------------------------------------------------------------------

local Enum
do
local KEY_NAMES = string.split(
	"Unknown,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,Zero,One,Two,Three,Four,Five,Six,Seven,Eight,Nine,"
		.. "F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11,F12,LeftShift,RightShift,LeftControl,RightControl,LeftAlt,RightAlt,"
		.. "Space,Return,Escape,Backspace,Tab,Insert,Delete,Home,End,PageUp,PageDown,Up,Down,Left,Right,"
		.. "Minus,Equals,LeftBracket,RightBracket,Semicolon,Quote,Comma,Period,Slash,BackSlash,Backquote,CapsLock,"
		.. "ButtonA,ButtonB,ButtonX,ButtonY,ButtonSelect,ButtonStart,DPadUp,DPadDown,DPadLeft,DPadRight",
	","
)
-- Values the page needs to read back as numbers.
local ENUM_VALUES = {
	FontWeight = { Thin = 100, ExtraLight = 200, Light = 300, Regular = 400, Medium = 500, SemiBold = 600, Bold = 700, ExtraBold = 800, Heavy = 900 },
}
local EnumItemMeta = valueType("EnumItem")
EnumItemMeta.__tostring = function(self)
	return "Enum." .. self.EnumType.Name .. "." .. self.Name
end

local function newEnumType(name)
	local items, order = {}, {}
	local enumType = { Name = name }
	local values = ENUM_VALUES[name]
	local function item(itemName)
		if not items[itemName] then
			items[itemName] = setmetatable({ Name = itemName, EnumType = enumType, Value = if values and values[itemName] then values[itemName] else #order }, EnumItemMeta)
			table.insert(order, items[itemName])
		end
		return items[itemName]
	end
	if name == "KeyCode" then
		for _, keyName in KEY_NAMES do
			item(keyName)
		end
	end
	function enumType.GetEnumItems()
		return table.clone(order)
	end
	function enumType.FromName(_, itemName)
		return item(itemName)
	end
	return setmetatable(enumType, {
		__type = "Enum",
		__index = function(_, key)
			return item(key)
		end,
		__tostring = function()
			return name
		end,
	})
end

Enum = setmetatable({}, {
	__index = function(self, name)
		local enumType = newEnumType(name)
		rawset(self, name, enumType)
		return enumType
	end,
})
end

-- JSON ----------------------------------------------------------------------

local jsonEncode, jsonDecode
do
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function escapeString(value)
	return '"' .. string.gsub(value, '[%c"\\]', function(character)
		return ESCAPES[character] or string.format("\\u%04x", string.byte(character))
	end) .. '"'
end

function jsonEncode(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		-- No limit (math.huge, as in UISizeConstraint.MaxSize) goes as a large number.
		if value ~= value then
			return "null"
		elseif value == math.huge then
			return "1e9"
		elseif value == -math.huge then
			return "-1e9"
		end
		return if value == math.floor(value) and math.abs(value) < 1e15 then string.format("%d", value) else string.format("%.6g", value)
	elseif kind == "string" then
		return escapeString(value)
	end
	assert(kind == "table", "cannot encode " .. typeof(value))
	local parts = {}
	local count = #value
	if count > 0 or next(value) == nil then
		for index = 1, count do
			parts[index] = jsonEncode(value[index])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, key in keys do
		table.insert(parts, escapeString(tostring(key)) .. ":" .. jsonEncode(value[key]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local UNESCAPES = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" }

function jsonDecode(text)
	local position = 1
	local parseValue

	local function skip()
		position = string.find(text, "%S", position) or #text + 1
	end

	local function parseString()
		local out = {}
		position += 1
		while true do
			local stop = string.find(text, '["\\]', position)
			assert(stop, "unterminated string")
			table.insert(out, string.sub(text, position, stop - 1))
			position = stop
			if string.sub(text, position, position) == '"' then
				position += 1
				return table.concat(out)
			end
			local escaped = string.sub(text, position + 1, position + 1)
			if escaped == "u" then
				table.insert(out, utf8.char(tonumber(string.sub(text, position + 2, position + 5), 16)))
				position += 6
			else
				table.insert(out, UNESCAPES[escaped] or escaped)
				position += 2
			end
		end
	end

	function parseValue()
		skip()
		local character = string.sub(text, position, position)
		if character == "{" then
			local object = {}
			position += 1
			skip()
			if string.sub(text, position, position) == "}" then
				position += 1
				return object
			end
			while true do
				skip()
				local key = parseString()
				skip()
				assert(string.sub(text, position, position) == ":", "expected ':'")
				position += 1
				object[key] = parseValue()
				skip()
				local separator = string.sub(text, position, position)
				position += 1
				if separator == "}" then
					return object
				end
				assert(separator == ",", "expected ',' in object")
			end
		elseif character == "[" then
			local array = {}
			position += 1
			skip()
			if string.sub(text, position, position) == "]" then
				position += 1
				return array
			end
			while true do
				table.insert(array, parseValue())
				skip()
				local separator = string.sub(text, position, position)
				position += 1
				if separator == "]" then
					return array
				end
				assert(separator == ",", "expected ',' in array")
			end
		elseif character == '"' then
			return parseString()
		end
		for literal, result in { ["true"] = true, ["false"] = false } do
			if string.sub(text, position, position + #literal - 1) == literal then
				position += #literal
				return result
			end
		end
		if string.sub(text, position, position + 3) == "null" then
			position += 4
			return nil
		end
		local number = string.match(text, "^-?%d+%.?%d*[eE]?[+-]?%d*", position)
		assert(number and number ~= "", "unexpected character in JSON")
		position += #number
		return tonumber(number)
	end

	local result = parseValue()
	skip()
	return result
end
end

-- Instances -----------------------------------------------------------------

local EVENTS = {}
for _, name in
	string.split(
		"Activated,MouseEnter,MouseLeave,MouseButton1Down,MouseButton1Up,MouseButton1Click,MouseButton2Click,MouseButton2Down,"
			.. "MouseButton2Up,InputBegan,InputChanged,InputEnded,FocusLost,Focused,Destroying,ChildAdded,ChildRemoved,Changed,"
			.. "Heartbeat,RenderStepped,Stepped,CharacterAdded,Completed,SelectionGained,SelectionLost,TouchTap,TouchLongPress,"
			.. "ReturnPressedFromOnScreenKeyboard,PlayerAdded,PlayerRemoving,DescendantAdded,DescendantRemoving,AncestryChanged,"
			.. "MouseWheelForward,MouseWheelBackward,WindowFocused,WindowFocusReleased,LastInputTypeChanged,TextChanged,"
			.. "JumpRequest,CharacterRemoving,Idled,TextBoxFocused,TextBoxFocusReleased",
		","
	)
do
	EVENTS[name] = true
end

local GUI_OBJECTS = {}
for _, name in string.split("Frame,TextLabel,TextButton,TextBox,ImageLabel,ImageButton,ScrollingFrame,CanvasGroup,ViewportFrame,VideoFrame", ",") do
	GUI_OBJECTS[name] = true
end
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }
local IMAGE_CLASSES = { ImageLabel = true, ImageButton = true }
local BUTTON_CLASSES = { TextButton = true, ImageButton = true }
-- Instances the page draws or reads: the GUI objects, the ScreenGuis that
-- hold them, and the UI components that change how they look.
local DRAWN = {
	ScreenGui = true,
	UICorner = true,
	UIStroke = true,
	UIPadding = true,
	UIListLayout = true,
	UIGridLayout = true,
	UIFlexItem = true,
	UISizeConstraint = true,
	UITextSizeConstraint = true,
	UIAspectRatioConstraint = true,
	UIScale = true,
	UIGradient = true,
}
for name in GUI_OBJECTS do
	DRAWN[name] = true
end

-- Roblox's own defaults for a new instance of each class.
local function defaults(className, props)
	if GUI_OBJECTS[className] then
		local textual = TEXT_CLASSES[className]
		-- Instance.new gives 0 by 0; only Studio's insert menu sizes new objects.
		props.Size = UDim2.new(0, 0, 0, 0)
		props.Position = UDim2.new(0, 0, 0, 0)
		props.AnchorPoint = Vector2.zero
		props.Visible = true
		props.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
		props.BackgroundTransparency = 0
		props.BorderSizePixel = 1
		props.ZIndex = 1
		props.LayoutOrder = 0
		props.Rotation = 0
		props.ClipsDescendants = false
		props.AutomaticSize = Enum.AutomaticSize.None
		props.Active = BUTTON_CLASSES[className] == true or className == "TextBox" or className == "ScrollingFrame"
		props.AbsoluteSize = Vector2.zero
		props.AbsolutePosition = Vector2.zero
		props.Selectable = BUTTON_CLASSES[className] == true or className == "TextBox"
		props.Interactable = true
		if textual then
			props.Text = if className == "TextLabel" then "Label" elseif className == "TextButton" then "Button" else ""
			props.TextColor3 = Color3.fromRGB(27, 42, 53)
			props.TextTransparency = 0
			props.TextSize = 14
			props.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
			props.TextWrapped = false
			props.TextScaled = false
			props.RichText = false
			props.TextTruncate = Enum.TextTruncate.None
			props.TextXAlignment = Enum.TextXAlignment.Center
			props.TextYAlignment = Enum.TextYAlignment.Center
			props.LineHeight = 1
			props.TextBounds = Vector2.zero
			props.TextFits = true
			props.MaxVisibleGraphemes = -1
		end
		if className == "TextBox" then
			props.PlaceholderText = ""
			props.PlaceholderColor3 = Color3.fromRGB(178, 178, 178)
			props.ClearTextOnFocus = true
			props.MultiLine = false
			props.TextEditable = true
			props.CursorPosition = -1
		end
		if IMAGE_CLASSES[className] then
			props.Image = ""
			props.ImageColor3 = Color3.new(1, 1, 1)
			props.ImageTransparency = 0
			props.ScaleType = Enum.ScaleType.Stretch
			props.ImageRectOffset = Vector2.zero
			props.ImageRectSize = Vector2.zero
			props.SliceCenter = Rect.new(0, 0, 0, 0)
		end
		if BUTTON_CLASSES[className] then
			props.AutoButtonColor = true
		end
		if className == "ScrollingFrame" then
			props.CanvasSize = UDim2.new(0, 0, 2, 0)
			props.CanvasPosition = Vector2.zero
			props.AbsoluteCanvasSize = Vector2.zero
			props.AbsoluteWindowSize = Vector2.zero
			props.ScrollBarThickness = 12
			props.ScrollBarImageColor3 = Color3.new(0, 0, 0)
			props.ScrollBarImageTransparency = 0
			props.ScrollingDirection = Enum.ScrollingDirection.XY
			props.ScrollingEnabled = true
			props.AutomaticCanvasSize = Enum.AutomaticSize.None
			props.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		end
	elseif className == "ScreenGui" then
		props.Enabled = true
		props.DisplayOrder = 0
		props.IgnoreGuiInset = false
		props.ResetOnSpawn = true
		props.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		props.AbsoluteSize = Vector2.zero
		props.AbsolutePosition = Vector2.zero
	elseif className == "UICorner" then
		props.CornerRadius = UDim.new(0, 8)
	elseif className == "UIStroke" then
		props.Color = Color3.new(0, 0, 0)
		props.Thickness = 1
		props.Transparency = 0
		props.Enabled = true
		props.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		props.LineJoinMode = Enum.LineJoinMode.Round
	elseif className == "UIPadding" then
		props.PaddingLeft, props.PaddingRight, props.PaddingTop, props.PaddingBottom = UDim.new(), UDim.new(), UDim.new(), UDim.new()
	elseif className == "UIListLayout" then
		props.FillDirection = Enum.FillDirection.Vertical
		props.Padding = UDim.new()
		props.HorizontalAlignment = Enum.HorizontalAlignment.Left
		props.VerticalAlignment = Enum.VerticalAlignment.Top
		props.SortOrder = Enum.SortOrder.Name
		props.Wraps = false
		props.HorizontalFlex = Enum.UIFlexAlignment.None
		props.VerticalFlex = Enum.UIFlexAlignment.None
		props.ItemLineAlignment = Enum.ItemLineAlignment.Automatic
		props.AbsoluteContentSize = Vector2.zero
	elseif className == "UIGridLayout" then
		props.CellSize = UDim2.fromOffset(100, 100)
		props.CellPadding = UDim2.fromOffset(5, 5)
		props.FillDirection = Enum.FillDirection.Horizontal
		props.FillDirectionMaxCells = 0
		props.HorizontalAlignment = Enum.HorizontalAlignment.Left
		props.VerticalAlignment = Enum.VerticalAlignment.Top
		props.SortOrder = Enum.SortOrder.Name
		props.StartCorner = Enum.StartCorner.TopLeft
		props.AbsoluteContentSize = Vector2.zero
		props.AbsoluteCellSize = Vector2.zero
	elseif className == "UIFlexItem" then
		props.FlexMode = Enum.UIFlexMode.None
		props.GrowRatio = 1
		props.ShrinkRatio = 1
		props.ItemLineAlignment = Enum.ItemLineAlignment.Automatic
	elseif className == "UISizeConstraint" then
		props.MinSize = Vector2.zero
		props.MaxSize = Vector2.new(math.huge, math.huge)
	elseif className == "UITextSizeConstraint" then
		props.MinTextSize = 1
		props.MaxTextSize = 100
	elseif className == "UIAspectRatioConstraint" then
		props.AspectRatio = 1
	elseif className == "UIScale" then
		props.Scale = 1
	elseif className == "UIGradient" then
		props.Color = ColorSequence.new(Color3.new(1, 1, 1))
		props.Transparency = NumberSequence.new(0)
		props.Rotation = 0
		props.Offset = Vector2.zero
		props.Enabled = true
	elseif className == "BlurEffect" then
		props.Size = 24
		props.Enabled = true
	elseif className == "Sound" then
		props.SoundId = ""
		props.Volume = 0.5
		props.Playing = false
	end
end

local InstanceMeta = { __type = "Instance" }
local Methods = {}
local services = {}
-- The page's size, set from the page on every step.
local viewport = Vector2.new(1280, 720)

-- Render bridge: ids for drawn instances and the changes waiting to be sent.
local nextId = 0
local ops = {}
local byId = {}

local function idOf(instance)
	return rawget(instance, "rid")
end

local function queue(op)
	table.insert(ops, op)
end

-- Encodes a property value for the page: numbers, strings and booleans as
-- they are, datatypes as small arrays, enums by name.
local function encodeValue(value)
	local kind = typeof(value)
	if kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif kind == "UDim" then
		return { value.Scale, value.Offset }
	elseif kind == "Vector2" then
		return { value.X, value.Y }
	elseif kind == "Color3" then
		return { math.round(value.R * 255), math.round(value.G * 255), math.round(value.B * 255) }
	elseif kind == "EnumItem" then
		return value.Name
	elseif kind == "Font" then
		return { value.Family, if value.Weight then value.Weight.Value else 400, if value.Style then value.Style.Name else "Normal" }
	elseif kind == "Rect" then
		return { value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }
	elseif kind == "NumberSequence" then
		local points = {}
		for _, point in value.Keypoints do
			table.insert(points, { point.Time, point.Value })
		end
		return points
	elseif kind == "ColorSequence" then
		local points = {}
		for _, point in value.Keypoints do
			local color = point.Value
			table.insert(points, { point.Time, math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255) })
		end
		return points
	elseif kind == "number" then
		if value == math.huge then
			return 1e9
		elseif value == -math.huge then
			return -1e9
		end
		return value
	elseif kind == "string" or kind == "boolean" then
		return value
	end
	return nil
end

-- Properties the page never needs.
local SKIPPED = {
	ClassName = true,
	Parent = true,
	AbsoluteSize = true,
	AbsolutePosition = true,
	AbsoluteContentSize = true,
	AbsoluteCanvasSize = true,
	AbsoluteWindowSize = true,
	AbsoluteCellSize = true,
	TextBounds = true,
	TextFits = true,
	SelectionImageObject = true,
}

local function sendProperty(instance, key, value)
	if SKIPPED[key] then
		return
	end
	local id = idOf(instance)
	if id then
		local encoded = encodeValue(value)
		if encoded ~= nil then
			queue({ "p", id, key, encoded })
		end
	end
end

-- Whether `instance` sits under the PlayerGui, where the page can see it.
local function onScreen(instance)
	local node = rawget(instance, "props").Parent
	while node do
		if rawget(node, "props").ClassName == "PlayerGui" then
			return true
		end
		node = rawget(node, "props").Parent
	end
	return false
end

local track, untrack

-- Gives `instance` (and everything drawn inside it) an id and sends it,
-- with all its properties, to the page.
function track(instance)
	local props = rawget(instance, "props")
	if not DRAWN[props.ClassName] or idOf(instance) then
		return
	end
	nextId += 1
	local id = nextId
	rawset(instance, "rid", id)
	byId[id] = instance
	local parent = props.Parent
	queue({ "c", id, props.ClassName, if parent then idOf(parent) or 0 else 0, props.Name })
	for key, value in props do
		sendProperty(instance, key, value)
	end
	for name, value in rawget(instance, "attributes") do
		queue({ "a", id, name, encodeValue(value) })
	end
	for _, child in rawget(instance, "children") do
		track(child)
	end
end

function untrack(instance)
	local id = idOf(instance)
	if not id then
		return
	end
	for _, child in rawget(instance, "children") do
		untrack(child)
	end
	rawset(instance, "rid", nil)
	byId[id] = nil
	queue({ "d", id })
end

InstanceMeta.__index = function(self, key)
	local props = rawget(self, "props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	local method = Methods[key]
	if method then
		return method
	end
	if EVENTS[key] then
		local signals = rawget(self, "signals")
		signals[key] = signals[key] or newSignal()
		return signals[key]
	end
	for _, child in rawget(self, "children") do
		if rawget(child, "props").Name == key then
			return child
		end
	end
	return nil
end

InstanceMeta.__tostring = function(self)
	return rawget(self, "props").Name
end

local function fireChanged(self, key)
	local signal = rawget(self, "changed")[key]
	if signal then
		signal:Fire()
	end
	local changed = rawget(self, "signals").Changed
	if changed then
		changed:Fire(key)
	end
end

local function setParent(self, parent)
	local props = rawget(self, "props")
	local previous = props.Parent
	if previous == parent then
		return
	end
	if rawget(self, "destroyed") and parent ~= nil then
		error("The Parent property of " .. tostring(props.Name) .. " is locked", 3)
	end
	if previous then
		local siblings = rawget(previous, "children")
		local index = table.find(siblings, self)
		if index then
			table.remove(siblings, index)
		end
		local removed = rawget(previous, "signals").ChildRemoved
		if removed then
			removed:Fire(self)
		end
	end
	props.Parent = parent
	if parent then
		table.insert(rawget(parent, "children"), self)
	end
	-- The page follows the instance: drawn under its new parent, moved, or
	-- dropped when it leaves the screen.
	local shown = parent ~= nil and onScreen(self)
	if idOf(self) then
		if shown and idOf(parent) then
			queue({ "m", idOf(self), idOf(parent) })
		elseif shown and rawget(parent, "props").ClassName == "PlayerGui" then
			queue({ "m", idOf(self), 0 })
		else
			untrack(self)
		end
	elseif shown and (idOf(parent) or rawget(parent, "props").ClassName == "PlayerGui") then
		track(self)
	end
	if parent then
		local added = rawget(parent, "signals").ChildAdded
		if added then
			added:Fire(self)
		end
		-- DescendantAdded reaches every ancestor, for this instance and
		-- everything already inside it.
		local ancestor = parent
		while ancestor do
			local descendant = rawget(ancestor, "signals").DescendantAdded
			if descendant then
				descendant:Fire(self)
				for _, inner in self:GetDescendants() do
					descendant:Fire(inner)
				end
			end
			ancestor = rawget(ancestor, "props").Parent
		end
	end
	fireChanged(self, "Parent")
	local ancestry = rawget(self, "signals").AncestryChanged
	if ancestry then
		ancestry:Fire(self, parent)
	end
end

InstanceMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local props = rawget(self, "props")
	if props[key] == value then
		return
	end
	props[key] = value
	sendProperty(self, key, value)
	fireChanged(self, key)
end

-- Sets a property from the page (a measured size, typed text, a scroll):
-- the page already shows it, so nothing is sent back.
local function setFromPage(instance, key, value)
	local props = rawget(instance, "props")
	if props[key] == value then
		return
	end
	props[key] = value
	fireChanged(instance, key)
end

local function newInstance(className)
	local props = { ClassName = className, Name = className }
	defaults(className, props)
	return setmetatable({ props = props, signals = {}, changed = {}, children = {}, attributes = {} }, InstanceMeta)
end

function Methods:GetChildren()
	return table.clone(rawget(self, "children"))
end

function Methods:GetDescendants()
	local found = {}
	local function visit(instance)
		for _, child in rawget(instance, "children") do
			table.insert(found, child)
			visit(child)
		end
	end
	visit(self)
	return found
end

function Methods:FindFirstChild(name, recursive)
	for _, child in if recursive then self:GetDescendants() else rawget(self, "children") do
		if rawget(child, "props").Name == name then
			return child
		end
	end
	return nil
end

function Methods:WaitForChild(name)
	local found = self:FindFirstChild(name)
	while not found do
		task.wait()
		found = self:FindFirstChild(name)
	end
	return found
end

function Methods:FindFirstAncestor(name)
	local node = self.Parent
	while node do
		if node.Name == name then
			return node
		end
		node = node.Parent
	end
	return nil
end

function Methods:FindFirstAncestorOfClass(className)
	local node = self.Parent
	while node do
		if node.ClassName == className then
			return node
		end
		node = node.Parent
	end
	return nil
end

function Methods:FindFirstAncestorWhichIsA(className)
	local node = self.Parent
	while node do
		if node:IsA(className) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local ANCESTRY = {
	GuiObject = GUI_OBJECTS,
	GuiButton = BUTTON_CLASSES,
	GuiBase2d = setmetatable({ ScreenGui = true }, { __index = GUI_OBJECTS }),
	LayerCollector = { ScreenGui = true },
	UIComponent = DRAWN,
	BasePart = { Part = true, MeshPart = true },
	PostEffect = { BlurEffect = true },
}

function Methods:IsA(className)
	local own = self.ClassName
	if own == className or className == "Instance" then
		return true
	end
	local group = ANCESTRY[className]
	return group ~= nil and group[own] == true
end

function Methods:FindFirstChildOfClass(className)
	for _, child in rawget(self, "children") do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function Methods:FindFirstChildWhichIsA(className, recursive)
	for _, child in if recursive then self:GetDescendants() else rawget(self, "children") do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end

function Methods:IsDescendantOf(ancestor)
	local parent = self.Parent
	while parent do
		if parent == ancestor then
			return true
		end
		parent = parent.Parent
	end
	return false
end

function Methods:IsAncestorOf(descendant)
	return descendant:IsDescendantOf(self)
end

function Methods:GetFullName()
	local names = {}
	local node = self
	while node and node.ClassName ~= "DataModel" do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, ".")
end

function Methods:GetPropertyChangedSignal(property)
	local changed = rawget(self, "changed")
	changed[property] = changed[property] or newSignal()
	return changed[property]
end

function Methods:GetAttribute(name)
	return rawget(self, "attributes")[name]
end

function Methods:GetAttributes()
	return table.clone(rawget(self, "attributes"))
end

function Methods:SetAttribute(name, value)
	local attributes = rawget(self, "attributes")
	if attributes[name] == value then
		return
	end
	attributes[name] = value
	local id = idOf(self)
	if id then
		queue({ "a", id, name, encodeValue(value) })
	end
	local signals = rawget(self, "attributeSignals")
	if signals and signals[name] then
		signals[name]:Fire()
	end
end

function Methods:GetAttributeChangedSignal(name)
	local signals = rawget(self, "attributeSignals")
	if not signals then
		signals = {}
		rawset(self, "attributeSignals", signals)
	end
	signals[name] = signals[name] or newSignal()
	return signals[name]
end

function Methods:Destroy()
	if rawget(self, "destroyed") then
		return
	end
	local destroying = rawget(self, "signals").Destroying
	if destroying then
		destroying:Fire()
	end
	setParent(self, nil)
	rawset(self, "destroyed", true)
	for _, child in table.clone(rawget(self, "children")) do
		child:Destroy()
	end
	for _, group in { rawget(self, "signals"), rawget(self, "changed") } do
		for _, signal in group do
			for _, connection in table.clone(signal.list) do
				connection:Disconnect()
			end
		end
	end
end

function Methods:ClearAllChildren()
	for _, child in table.clone(rawget(self, "children")) do
		child:Destroy()
	end
end

function Methods:Clone()
	local copy = newInstance(self.ClassName)
	for key, value in rawget(self, "props") do
		if key ~= "Parent" then
			rawget(copy, "props")[key] = value
		end
	end
	for name, value in rawget(self, "attributes") do
		rawget(copy, "attributes")[name] = value
	end
	for _, child in rawget(self, "children") do
		child:Clone().Parent = copy
	end
	return copy
end

-- Text boxes: the page owns the real focus; these keep the instance in step.
local focusedBox

function Methods:CaptureFocus()
	if focusedBox and focusedBox ~= self then
		focusedBox:ReleaseFocus(false)
	end
	focusedBox = self
	rawset(self, "focused", true)
	local id = idOf(self)
	if id then
		queue({ "f", id, true })
	end
	self.Focused:Fire()
end

function Methods:ReleaseFocus(submitted)
	if not rawget(self, "focused") then
		return
	end
	rawset(self, "focused", false)
	if focusedBox == self then
		focusedBox = nil
	end
	local id = idOf(self)
	if id then
		queue({ "f", id, false })
	end
	self.FocusLost:Fire(submitted == true)
end

function Methods:IsFocused()
	return rawget(self, "focused") == true
end

function Methods:GetService(name)
	if not services[name] then
		local service = newInstance(name)
		services[name] = service
		service.Parent = Engine.game
	end
	return services[name]
end
Methods.FindService = Methods.GetService

-- Tweens ---------------------------------------------------------------------

local ease
do
local EASING = {}
function EASING.Linear(t)
	return t
end
function EASING.Sine(t)
	return 1 - math.cos(t * math.pi / 2)
end
function EASING.Quad(t)
	return t * t
end
function EASING.Cubic(t)
	return t ^ 3
end
function EASING.Quart(t)
	return t ^ 4
end
function EASING.Quint(t)
	return t ^ 5
end
function EASING.Exponential(t)
	return if t == 0 then 0 else 2 ^ (10 * t - 10)
end
function EASING.Circular(t)
	return 1 - math.sqrt(1 - t * t)
end
function EASING.Back(t)
	local s = 1.70158
	return t * t * ((s + 1) * t - s)
end
function EASING.Elastic(t)
	if t == 0 or t == 1 then
		return t
	end
	return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * (2 * math.pi) / 3)
end

function ease(style, direction, t)
	local curve = EASING[style] or EASING.Quad
	if direction == "In" then
		return curve(t)
	elseif direction == "InOut" then
		if t < 0.5 then
			return curve(t * 2) / 2
		end
		return 1 - curve((1 - t) * 2) / 2
	end
	return 1 - curve(1 - t)
end
end

local function lerp(from, goal, alpha)
	local kind = typeof(goal)
	if kind == "number" then
		return from + (goal - from) * alpha
	elseif kind == "UDim2" or kind == "Color3" or kind == "Vector2" then
		return from:Lerp(goal, alpha)
	elseif kind == "UDim" then
		return UDim.new(from.Scale + (goal.Scale - from.Scale) * alpha, from.Offset + (goal.Offset - from.Offset) * alpha)
	end
	return if alpha >= 1 then goal else from
end

local TweenInfoMeta = valueType("TweenInfo")
local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	return setmetatable({
		Time = time or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = direction or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses == true,
		DelayTime = delayTime or 0,
	}, TweenInfoMeta)
end

-- Running tweens, and which tween drives each property of each instance, so
-- a newer tween on the same property takes it over from an older one.
local running = {}
local owners = setmetatable({}, { __mode = "k" })

function Methods:Create(target, info, goals)
	local tween = newInstance("Tween")
	rawset(tween, "target", target)
	rawset(tween, "info", info or TweenInfo.new())
	rawset(tween, "goals", table.clone(goals))
	rawget(tween, "props").PlaybackState = Enum.PlaybackState.Begin
	return tween
end

local function finishTween(tween, state)
	local index = table.find(running, tween)
	if index then
		table.remove(running, index)
	end
	rawget(tween, "props").PlaybackState = state
	tween.Completed:Fire(state)
end

-- Play is a tween's (Sound:Play does nothing here).
function Methods:Play()
	local target, info = rawget(self, "target"), rawget(self, "info")
	if not target or rawget(target, "destroyed") then
		return
	end
	local starts = {}
	local claimed = owners[target] or {}
	owners[target] = claimed
	for key in rawget(self, "goals") do
		starts[key] = target[key]
		local previous = claimed[key]
		if previous and previous ~= self and table.find(running, previous) then
			rawget(previous, "goals")[key] = nil
		end
		claimed[key] = self
	end
	rawset(self, "starts", starts)
	rawset(self, "started", Engine.now + (info.DelayTime or 0))
	if not table.find(running, self) then
		table.insert(running, self)
	end
	rawget(self, "props").PlaybackState = Enum.PlaybackState.Playing
end

function Methods:Cancel()
	if table.find(running, self) then
		finishTween(self, Enum.PlaybackState.Cancelled)
	end
end

function Methods:Pause()
	self:Cancel()
end

local function stepTweens()
	for _, tween in table.clone(running) do
		local target, info = rawget(tween, "target"), rawget(tween, "info")
		if rawget(target, "destroyed") then
			finishTween(tween, Enum.PlaybackState.Cancelled)
			continue
		end
		local elapsed = Engine.now - rawget(tween, "started")
		if elapsed < 0 then
			continue
		end
		local t = if info.Time <= 0 then 1 else math.clamp(elapsed / info.Time, 0, 1)
		local alpha = ease(info.EasingStyle.Name, info.EasingDirection.Name, t)
		local starts = rawget(tween, "starts")
		for key, goal in rawget(tween, "goals") do
			target[key] = if t >= 1 then goal else lerp(starts[key], goal, alpha)
		end
		if t >= 1 then
			finishTween(tween, Enum.PlaybackState.Completed)
		end
	end
end

-- Services -------------------------------------------------------------------

local guids = 0
function Methods:GenerateGUID(braces)
	guids += 1
	local text = string.format("%08x-%04x-4%03x-%04x-%012x", math.random(0, 0x7fffffff), math.random(0, 0xffff), math.random(0, 0xfff), 0x8000 + math.random(0, 0x3fff), guids)
	return if braces == false then text else "{" .. text .. "}"
end

function Methods:JSONEncode(value)
	return jsonEncode(value)
end

function Methods:JSONDecode(text)
	return jsonDecode(text)
end

function Methods:GetUserThumbnailAsync(userId)
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150", true
end

function Methods:GetGuiInset()
	return Vector2.zero, Vector2.zero
end

function Methods:IsStudio()
	return false
end

function Methods:GetFocusedTextBox()
	return focusedBox
end

function Methods:GetNetworkPing()
	return 0.04
end

-- The page has no Roblox client, so this reports what the Luau VM itself uses.
function Methods:GetTotalMemoryUsageMb()
	return gcinfo() / 1024
end

local mouse = Vector2.new(-1, -1)
local held = {}

function Methods:GetMouseLocation()
	return mouse
end

function Methods:IsKeyDown(keyCode)
	return held[keyCode.Name] == true
end

function Methods:IsMouseButtonPressed(button)
	return held[button.Name] == true
end

function Methods:GetLastInputType()
	return Enum.UserInputType.MouseMovement
end

function Methods:GetPlayers()
	local list = {}
	for _, child in self:GetChildren() do
		if child.ClassName == "Player" then
			table.insert(list, child)
		end
	end
	return list
end

-- An estimate close enough for code that sizes boxes before they are drawn.
function Methods:GetTextSize(text, size)
	local width = 0
	for _ in utf8.graphemes(text) do
		width += size * 0.55
	end
	return Vector2.new(math.ceil(width), math.ceil(size * 1.25))
end

function Methods:PlayLocalSound() end
function Methods:SetCore() end
function Methods:GetCore()
	return nil
end

function Methods:HttpGet(url)
	error("This demo runs offline: " .. tostring(url), 2)
end

local Instance = {}

function Instance.new(className, parent)
	local instance = newInstance(className)
	if parent then
		instance.Parent = parent
	end
	return instance
end

local game = newInstance("DataModel")
rawget(game, "props").Name = "Halcyon"
rawget(game, "props").PlaceId = 0
rawget(game, "props").GameId = 0
rawget(game, "props").JobId = "browser"
Engine.game = game
local workspace = game:GetService("Workspace")
workspace.CurrentCamera = newInstance("Camera")
workspace.CurrentCamera.ViewportSize = viewport
workspace.CurrentCamera.FieldOfView = 70

local localPlayer
do
	local players = game:GetService("Players")
	local player = newInstance("Player")
	player.Name = "guest"
	player.DisplayName = "Guest"
	player.UserId = 1
	player.AccountAge = 365
	player.MembershipType = Enum.MembershipType.None
	local playerGui = newInstance("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player
	player.Parent = players
	players.LocalPlayer = player
	localPlayer = player

	-- A few other people, so player lists have someone to show.
	for index, names in { { "kite_runner", "Kite" }, { "nova_builds", "Nova" }, { "rook42", "Rook" } } do
		local other = newInstance("Player")
		other.Name = names[1]
		other.DisplayName = names[2]
		other.UserId = 100 + index
		other.Parent = players
	end

	local input = game:GetService("UserInputService")
	input.TouchEnabled = false
	input.KeyboardEnabled = true
	input.MouseEnabled = true
	input.GamepadEnabled = false
	input.MouseIconEnabled = true
end

-- Executor functions --------------------------------------------------------

-- Files live in the browser's storage: the page loads them before the chunk
-- runs and saves whatever changes. These and `require` below look unused
-- here; the library and the example, later in the same chunk, call them.
local files, folders = {}, {}

local function writefile(path, content)
	files[path] = tostring(content)
	queue({ "w", path, files[path] })
end

local function readfile(path)
	assert(files[path] ~= nil, "file not found: " .. tostring(path))
	return files[path]
end

local function isfile(path)
	return files[path] ~= nil
end

local function isfolder(path)
	return folders[path] == true
end

local function makefolder(path)
	folders[path] = true
end

local function delfile(path)
	files[path] = nil
	queue({ "w", path })
end

local function listfiles(folder)
	local found = {}
	for path in files do
		if string.sub(path, 1, #folder + 1) == folder .. "/" and not string.find(path, "/", #folder + 2, true) then
			table.insert(found, path)
		end
	end
	table.sort(found)
	return found
end

local function setclipboard(text)
	hostCopy(tostring(text))
end

local function identifyexecutor()
	return "Browser", "demo"
end

local genv = {}
local function getgenv()
	return genv
end

-- The library ------------------------------------------------------------------

-- `require` for the one module the example asks for: the library itself,
-- found as a ModuleScript in ReplicatedStorage.
local loaders = setmetatable({}, { __mode = "k" })
local loaded = setmetatable({}, { __mode = "k" })

local function require(module)
	if loaded[module] == nil then
		local loader = loaders[module]
		assert(loader, "this demo can only require the Halcyon module")
		loaded[module] = loader()
	end
	return loaded[module]
end

-- Steps ------------------------------------------------------------------------

local runService = game:GetService("RunService")
local userInput = game:GetService("UserInputService")

local function inputObject(kind, keyName, x, y)
	return {
		UserInputType = Enum.UserInputType[kind],
		KeyCode = Enum.KeyCode[keyName or "Unknown"],
		Position = Vector3.new(x or mouse.X, y or mouse.Y, 0),
		Delta = Vector3.zero,
		UserInputState = Enum.UserInputState.Begin,
	}
end

-- One input event from the page. `chain` lists the drawn instances under the
-- pointer from the innermost out, already cut where Roblox stops a press
-- (at the first button or other active object); `button` is the button the
-- press belongs to, if any.
local function applyInput(event)
	local kind = event.t
	if kind == "move" then
		mouse = Vector2.new(event.x, event.y)
		local input = inputObject(if event.touch then "Touch" else "MouseMovement", nil, event.x, event.y)
		input.UserInputState = Enum.UserInputState.Change
		userInput.InputChanged:Fire(input, event.sunk == true)
		for _, id in event.chain or {} do
			local instance = byId[id]
			if instance then
				instance.InputChanged:Fire(input)
			end
		end
	elseif kind == "enter" or kind == "leave" then
		local instance = byId[event.id]
		if instance then
			if kind == "enter" then
				instance.MouseEnter:Fire(event.x, event.y)
			else
				instance.MouseLeave:Fire(event.x, event.y)
			end
		end
	elseif kind == "down" or kind == "up" then
		mouse = Vector2.new(event.x, event.y)
		local name = if event.b == 2 then "MouseButton2" else "MouseButton1"
		local input = inputObject(if event.touch then "Touch" else name, nil, event.x, event.y)
		input.UserInputState = if kind == "down" then Enum.UserInputState.Begin else Enum.UserInputState.End
		held[name] = kind == "down"
		if kind == "down" then
			userInput.InputBegan:Fire(input, event.sunk == true)
		else
			userInput.InputEnded:Fire(input, event.sunk == true)
		end
		for _, id in event.chain or {} do
			local instance = byId[id]
			if instance then
				if kind == "down" then
					instance.InputBegan:Fire(input)
				else
					instance.InputEnded:Fire(input)
				end
			end
		end
		local target = event.button and byId[event.button]
		if target then
			if event.b == 2 then
				if kind == "down" then
					target.MouseButton2Down:Fire(event.x, event.y)
				else
					target.MouseButton2Up:Fire(event.x, event.y)
					if event.click then
						target.MouseButton2Click:Fire()
					end
				end
			elseif kind == "down" then
				target.MouseButton1Down:Fire(event.x, event.y)
			else
				target.MouseButton1Up:Fire(event.x, event.y)
				if event.click then
					target.MouseButton1Click:Fire()
					target.Activated:Fire(input, 1)
				end
			end
		end
	elseif kind == "key" then
		local input = inputObject("Keyboard", event.k)
		held[event.k] = event.down
		input.UserInputState = if event.down then Enum.UserInputState.Begin else Enum.UserInputState.End
		local typing = focusedBox ~= nil
		if event.down then
			userInput.InputBegan:Fire(input, typing)
		else
			userInput.InputEnded:Fire(input, typing)
		end
	elseif kind == "text" then
		local box = byId[event.id]
		if box then
			setFromPage(box, "Text", event.v)
		end
	elseif kind == "focus" then
		local box = byId[event.id]
		if box then
			if event.on then
				if focusedBox and focusedBox ~= box then
					focusedBox:ReleaseFocus(false)
				end
				focusedBox = box
				rawset(box, "focused", true)
				box.Focused:Fire()
			elseif rawget(box, "focused") then
				rawset(box, "focused", false)
				if focusedBox == box then
					focusedBox = nil
				end
				box.FocusLost:Fire(event.enter == true)
			end
		end
	elseif kind == "scroll" then
		local frame = byId[event.id]
		if frame then
			setFromPage(frame, "CanvasPosition", Vector2.new(event.x, event.y))
		end
	end
end

-- Sizes and positions measured by the page: { id, x, y, w, h, textW, textH,
-- canvasW, canvasH }; the text and canvas pairs are there when they apply.
local function applyMeasures(list)
	for _, entry in list do
		local instance = byId[entry[1]]
		if instance then
			setFromPage(instance, "AbsolutePosition", Vector2.new(entry[2], entry[3]))
			setFromPage(instance, "AbsoluteSize", Vector2.new(entry[4], entry[5]))
			if entry[6] then
				setFromPage(instance, "TextBounds", Vector2.new(entry[6], entry[7]))
			end
			if entry[8] then
				setFromPage(instance, "AbsoluteCanvasSize", Vector2.new(entry[8], entry[9]))
				setFromPage(instance, "AbsoluteWindowSize", Vector2.new(entry[4], entry[5]))
			end
		end
	end
end

-- Content sizes of list and grid layouts: { id, w, h }.
local function applyContent(list)
	for _, entry in list do
		local layout = byId[entry[1]]
		if layout then
			setFromPage(layout, "AbsoluteContentSize", Vector2.new(entry[2], entry[3]))
		end
	end
end

local function resize(width, height)
	local size = Vector2.new(width, height)
	if size == viewport then
		return
	end
	viewport = size
	setFromPage(workspace.CurrentCamera, "ViewportSize", size)
	for _, gui in localPlayer.PlayerGui:GetChildren() do
		if gui.ClassName == "ScreenGui" then
			setFromPage(gui, "AbsoluteSize", size)
		end
	end
end

-- A ScreenGui is the size of the page from the moment it is made.
localPlayer.PlayerGui.ChildAdded:Connect(function(child)
	if child.ClassName == "ScreenGui" then
		setFromPage(child, "AbsoluteSize", viewport)
	end
end)

-- One frame: apply what the page measured and what the player did, run the
-- scheduler, tweens and frame events, then return every change as JSON.
function Engine.step(dt, payload)
	local incoming = if payload and payload ~= "" then jsonDecode(payload) else {}
	if incoming.w then
		resize(incoming.w, incoming.h)
	end
	if incoming.m then
		applyMeasures(incoming.m)
	end
	if incoming.l then
		applyContent(incoming.l)
	end
	flushDeferred()
	for _, event in incoming.e or {} do
		applyInput(event)
		flushDeferred()
	end
	Engine.now += dt
	Engine.frame += 1
	runTimers()
	stepTweens()
	runService.RenderStepped:Fire(dt)
	runService.Heartbeat:Fire(dt)
	runService.Stepped:Fire(Engine.now, dt)
	flushDeferred()
	local out = ops
	ops = {}
	return jsonEncode(out)
end

-- Starts the library and the example. `stored` is the saved files as JSON.
function Engine.start(library, example, stored, width, height, touch)
	viewport = Vector2.new(width or 1280, height or 720)
	workspace.CurrentCamera.ViewportSize = viewport
	userInput.TouchEnabled = touch == true
	userInput.MouseEnabled = touch ~= true
	if stored and stored ~= "" then
		for path, content in jsonDecode(stored) do
			files[path] = content
			local folder = string.match(path, "^(.*)/[^/]*$")
			while folder do
				folders[folder] = true
				folder = string.match(folder, "^(.*)/[^/]*$")
			end
		end
	end
	local module = newInstance("ModuleScript")
	module.Name = "Halcyon"
	loaders[module] = library
	module.Parent = game:GetService("ReplicatedStorage")
	task.spawn(example)
	flushDeferred()
	return true
end
