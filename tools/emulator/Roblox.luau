--!nocheck
-- A tiny fake of the Roblox engine, good enough to run the game's UI and server code
-- in Lune: instances with properties/children/signals, a few services, require() over
-- the Rojo sourcemap, and remotes that call straight into the server.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Emu = {}

-- Signals ------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local entry = { fn = fn }
	table.insert(self.handlers, entry)
	return {
		Connected = true,
		Disconnect = function()
			local index = table.find(self.handlers, entry)
			if index then
				table.remove(self.handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, entry in table.clone(self.handlers) do
		entry.fn(...)
	end
end

Emu.Signal = Signal

-- Instances ----------------------------------------------------------------------

local EVENTS = {
	Activated = true,
	MouseButton1Click = true,
	InputBegan = true,
	Heartbeat = true,
	PlayerAdded = true,
	PlayerRemoving = true,
}

local Methods = {}
local meta = {}
local created = 0

local function new(className: string, name: string?)
	created += 1
	local self = {
		__class = className,
		__props = { Name = name or className, ClassName = className },
		__children = {},
		__parent = nil,
		__signals = {},
		__propSignals = {},
		__order = created,
	}
	return setmetatable(self, meta)
end

meta.__index = function(self, key)
	if Methods[key] then
		return Methods[key]
	end
	if key == "Parent" then
		return self.__parent
	end
	if EVENTS[key] then
		self.__signals[key] = self.__signals[key] or Signal.new()
		return self.__signals[key]
	end
	local value = self.__props[key]
	if value ~= nil then
		return value
	end
	for _, child in self.__children do
		if child.__props.Name == key then
			return child
		end
	end
	if key == "AbsoluteSize" then
		return roblox.Vector2.new(1280, 720)
	end
	return nil
end

meta.__newindex = function(self, key, value)
	if key == "Parent" then
		if self.__parent then
			local siblings = self.__parent.__children
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		self.__parent = value
		if value then
			table.insert(value.__children, self)
		end
		return
	end
	self.__props[key] = value
	local signal = self.__propSignals[key]
	if signal then
		signal:Fire()
	end
end

meta.__tostring = function(self)
	return self.__props.Name
end

function Methods:Destroy()
	self.Parent = nil
	self.__destroyed = true
end

function Methods:ClearAllChildren()
	for _, child in table.clone(self.__children) do
		child:Destroy()
	end
end

function Methods:GetChildren()
	return table.clone(self.__children)
end

function Methods:FindFirstChild(name)
	for _, child in self.__children do
		if child.__props.Name == name then
			return child
		end
	end
	return nil
end

function Methods:WaitForChild(name)
	return self:FindFirstChild(name) or error(`WaitForChild: {name} not found in {self.Name}`)
end

function Methods:GetDescendants()
	local all = {}
	for _, child in self.__children do
		table.insert(all, child)
		for _, descendant in child:GetDescendants() do
			table.insert(all, descendant)
		end
	end
	return all
end

function Methods:SetAttribute(name, value)
	self.__attributes = self.__attributes or {}
	self.__attributes[name] = value
end

function Methods:GetAttribute(name)
	return self.__attributes and self.__attributes[name]
end

function Methods:IsA(className)
	return self.__class == className
end

function Methods:GetPropertyChangedSignal(prop)
	self.__propSignals[prop] = self.__propSignals[prop] or Signal.new()
	return self.__propSignals[prop]
end

function Methods:GetService(name)
	return self:FindFirstChild(name) or error(`No service {name}`)
end

function Methods:GetPlayers()
	return self:GetChildren()
end

function Methods:BindToClose() end

-- Sounds are silent here.
function Methods:Play() end
function Methods:Stop() end

function Methods:GetServerTimeNow()
	return Emu.now
end

function Methods:GetDataStore()
	error("DataStores are not available in the emulator")
end

function Methods:InvokeServer(...)
	local handler = self.__props.OnServerInvoke
	assert(handler, "No OnServerInvoke")
	-- Remotes copy their arguments/results.
	local args = Emu.deepCopy({ ... })
	return Emu.deepCopy(handler(Emu.player, table.unpack(args)))
end

Emu.new = new

function Emu.deepCopy(value)
	if type(value) ~= "table" or getmetatable(value) == meta then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = Emu.deepCopy(v)
	end
	return copy
end

-- Globals --------------------------------------------------------------------------

local FakeRandom = {}
function FakeRandom.new()
	return {
		NextInteger = function(_, a, b)
			return math.random(a, b)
		end,
	}
end

Emu.now = 1_700_000_000

-- Builds game from a Rojo sourcemap (rojo sourcemap --include-non-scripts).
function Emu.boot(sourcemapPath: string)
	local map = require("@lune/serde").decode("json", fs.readFile(sourcemapPath))
	local game = new("DataModel", "game")

	local function build(node, parent)
		local instance = new(node.className, node.name)
		if node.filePaths then
			for _, path in node.filePaths do
				if string.match(path, "%.luau?$") then
					instance.__source = path
				end
			end
		end
		instance.Parent = parent
		for _, child in node.children or {} do
			build(child, instance)
		end
		return instance
	end
	for _, child in map.children or {} do
		build(child, game)
	end

	for _, service in { "Players", "RunService", "UserInputService", "DataStoreService", "Workspace", "StarterPlayer", "SoundService" } do
		if not game:FindFirstChild(service) then
			new(service, service).Parent = game
		end
	end
	Emu.game = game
	Emu.byPath = {}
	local function index(instance)
		if instance.__source then
			Emu.byPath[instance.__source] = instance
		end
		for _, child in instance.__children do
			index(child)
		end
	end
	index(game)
	return game
end

local cache = {}

local function dirname(path)
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function normalize(path)
	local parts = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

function Emu.run(instance)
	if cache[instance] ~= nil then
		return cache[instance]
	end
	local path = instance.__source
	assert(path, `{instance.Name} has no source`)
	local env = {
		game = Emu.game,
		workspace = Emu.game.Workspace,
		script = instance,
		Instance = { new = function(className)
			return new(className)
		end },
		Enum = roblox.Enum,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Color3 = roblox.Color3,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		Random = FakeRandom,
		task = task,
		warn = function(...)
			print("[warn]", ...)
		end,
		require = function(target)
			if type(target) == "string" then
				local resolved = normalize(dirname(path) .. "/" .. target)
				for _, ext in { ".luau", ".lua", "/init.luau" } do
					local module = Emu.byPath[resolved .. ext]
					if module then
						return Emu.run(module)
					end
				end
				error(`cannot resolve {target} from {path}`)
			end
			return Emu.run(target)
		end,
	}
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local result = chunk()
	cache[instance] = result
	return result
end

-- Finds a descendant (depth first) matching a predicate.
function Emu.find(root, predicate)
	for _, child in root.__children do
		if predicate(child) then
			return child
		end
		local found = Emu.find(child, predicate)
		if found then
			return found
		end
	end
	return nil
end

function Emu.findText(root, pattern)
	return Emu.find(root, function(instance)
		local text = instance.__props.Text
		return (instance.__class == "TextButton") and type(text) == "string" and string.find(text, pattern) ~= nil
	end) or error(`no button matching {pattern}`)
end

function Emu.click(button)
	local signal = button.__signals.Activated
	assert(signal, `button {button.Text} has no handler`)
	signal:Fire()
end

-- Serializes a GUI tree to plain JSON-friendly tables.
local function plain(value)
	local kind = typeof(value)
	if kind == "UDim2" then
		return { t = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset }
	elseif kind == "UDim" then
		return { t = "UDim", s = value.Scale, o = value.Offset }
	elseif kind == "Vector2" then
		return { t = "Vector2", x = value.X, y = value.Y }
	elseif kind == "Color3" then
		return { t = "Color3", hex = value:ToHex() }
	elseif kind == "EnumItem" then
		return { t = "Enum", name = value.Name }
	elseif kind == "boolean" or kind == "number" or kind == "string" then
		return value
	end
	return nil
end

function Emu.snapshot(instance)
	local props = {}
	for key, value in instance.__props do
		props[key] = plain(value)
	end
	local children = {}
	for _, child in instance.__children do
		table.insert(children, Emu.snapshot(child))
	end
	return { class = instance.__class, order = instance.__order, props = props, children = children }
end

return Emu
