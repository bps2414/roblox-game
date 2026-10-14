--!strict
-- Server entry point: owns every player's Profile and answers the client's requests.
-- All game rules live in Shared.Sim.Profile; this file only handles players, saving,
-- randomness and the network.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profile = require(ReplicatedStorage.Shared.Sim.Profile)
local Store = require(script.Store)

local Request = ReplicatedStorage.Remotes.Request :: RemoteFunction

-- Nobody needs an avatar in a 2D UI game.
Players.CharacterAutoLoads = false

type Session = {
	profile: Profile.Profile,
	canSave: boolean,
	dirty: boolean,
	lastRequests: { number },
}

local sessions: { [Player]: Session } = {}
local random = Random.new()

local AUTOSAVE_SECONDS = 60
local MAX_REQUESTS_PER_SECOND = 15

local function newSeed(): number
	return random:NextInteger(1, 2 ^ 31 - 1)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function save(player: Player)
	local session = sessions[player]
	if session and session.canSave and session.dirty then
		session.dirty = false
		Store.save(player.UserId, session.profile)
	end
end

local function onPlayerAdded(player: Player)
	local data, canSave = Store.load(player.UserId)
	if not player.Parent then
		return
	end
	if not canSave then
		warn(`[Server] Could not load {player.Name}'s save; this session will not be saved.`)
	end
	sessions[player] = {
		profile = Profile.migrate(data, newSeed()),
		canSave = canSave,
		dirty = data == nil,
		lastRequests = {},
	}
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	for player in sessions do
		task.spawn(save, player)
	end
	task.wait(3)
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for player in sessions do
			task.spawn(save, player)
		end
	end
end)

local function rateLimited(session: Session): boolean
	local t = os.clock()
	local recent = {}
	for _, stamp in session.lastRequests do
		if t - stamp < 1 then
			table.insert(recent, stamp)
		end
	end
	table.insert(recent, t)
	session.lastRequests = recent
	return #recent > MAX_REQUESTS_PER_SECOND
end

type Response = { [string]: any }
type Handler = (profile: Profile.Profile, payload: any) -> (boolean, string?, Response?)

local handlers: { [string]: Handler } = {
	state = function(profile)
		return true, nil, { run = profile.activeRun, result = Profile.activeResult(profile) }
	end,
	recruit = function(profile, payload)
		return Profile.recruit(profile, payload.index, newSeed())
	end,
	sellGoblin = function(profile, payload)
		return Profile.sellGoblin(profile, payload.id)
	end,
	buyItem = function(profile, payload)
		return Profile.buyItem(profile, payload.id)
	end,
	sellItem = function(profile, payload)
		return Profile.sellItem(profile, payload.id)
	end,
	equip = function(profile, payload)
		return Profile.equip(profile, payload.goblinId, payload.slot, payload.itemId)
	end,
	send = function(profile, payload)
		local result, err = Profile.startRun(profile, payload.ids, payload.depth, now(), newSeed())
		if not result then
			return false, err
		end
		return true, nil, { run = profile.activeRun, result = result }
	end,
	collect = function(profile)
		local summary, err = Profile.collectRun(profile, now(), newSeed())
		if not summary then
			return false, err
		end
		return true, nil, { summary = summary }
	end,
}

Request.OnServerInvoke = function(player: Player, action: any, payload: any): Response
	-- The profile may still be loading right after joining.
	local deadline = os.clock() + 15
	while not sessions[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	local session = sessions[player]
	if not session then
		return { ok = false, err = "Profile not loaded" }
	end
	if rateLimited(session) then
		return { ok = false, err = "Slow down!" }
	end

	local handler = if type(action) == "string" then handlers[action] else nil
	if not handler then
		return { ok = false, err = "Unknown action" }
	end
	if type(payload) ~= "table" then
		payload = {}
	end

	local ok, err, extra = handler(session.profile, payload)
	if ok and action ~= "state" then
		session.dirty = true
	end
	local response: Response = extra or {}
	response.ok = ok
	response.err = err
	response.profile = session.profile
	response.serverNow = now()
	return response
end
