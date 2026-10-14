--!strict
-- Runs a whole expedition instantly and returns the outcome plus a per-goblin event
-- timeline for the client to replay. Pure Luau: no Roblox APIs.

local Config = require("./Config")
local Goblin = require("./Goblin")
local Rng = require("./Rng")
local Rooms = require("./Rooms")

export type Event = Rooms.Event

export type Params = {
	seed: number,
	depth: number,
	goblins: { Goblin.Goblin },
}

export type GoblinResult = {
	id: string,
	survived: boolean,
	cause: string?, -- "trap" | "mimic" | "monster" | "starvation"
	causeName: string?, -- which trap / monster
	gold: number,
	items: { string },
	xp: number, -- XP earned (0 if dead)
	levelBefore: number,
	levelAfter: number,
	rooms: number, -- rooms entered
	finishedAt: number, -- seconds into playback
}

export type Result = {
	seed: number,
	depth: number,
	duration: number,
	totalGold: number,
	survivors: number,
	goblins: { GoblinResult }, -- same order as params.goblins
	timelines: { [string]: { Event } },
}

local Expedition = {}

local function chooseDoor(d: Rooms.Delver, shown: { string }, actual: { string }): number
	if d.goblin.trait == "Dumb" then
		return d.rng:int(1, #shown)
	end

	local weights = {}
	for i, hint in shown do
		-- A sharp goblin sometimes sees through a misleading hint.
		local seen = hint
		if hint ~= actual[i] and d.rng:chance(d.perception / 100) then
			seen = actual[i]
		end
		local weight = Config.HINT_PREFERENCE[seen]
		if d.goblin.trait == "Greedy" and seen == "glint" then
			weight *= 4
		elseif d.goblin.trait == "Coward" and seen == "growl" then
			weight *= 0.1
		end
		weights[tostring(i)] = weight
	end
	return tonumber(d.rng:weighted(weights)) :: number
end

local function delve(goblin: Goblin.Goblin, depth: number, rng: Rng.Rng): (GoblinResult, { Event })
	local stats = Goblin.stats(goblin)
	local d: Rooms.Delver = {
		goblin = goblin,
		stats = stats,
		rng = rng,
		events = {},
		depth = depth,
		room = 0,
		t = 0,
		hp = stats.maxHp,
		food = stats.food,
		perception = stats.perception,
		gold = 0,
		xp = 0,
		kills = 0,
		items = {},
		alive = true,
		cause = nil,
	}

	Rooms.emit(d, "enter", { amount = depth })

	local length = Config.floorLength(depth)
	local foodPerRoom = if goblin.trait == "Glutton" then 2 else Config.FOOD_PER_ROOM
	local causeName: string? = nil

	for room = 1, length do
		d.t += Config.ROOM_SECONDS
		d.room = room

		if d.food >= foodPerRoom then
			d.food -= foodPerRoom
		else
			d.food = 0
			Rooms.emit(d, "starving", { amount = Config.STARVE_DAMAGE, hp = math.max(0, d.hp - Config.STARVE_DAMAGE) })
			d.hp -= Config.STARVE_DAMAGE
			if d.hp <= 0 then
				d.hp = 0
				d.alive = false
				d.cause = "starvation"
				Rooms.emit(d, "death", { cause = "starvation" })
				break
			end
		end

		local doorCount = rng:int(Config.DOORS[1], Config.DOORS[2])
		local roomTypes, actual, shown = {}, {}, {}
		local weights = Config.roomWeights(depth)
		for i = 1, doorCount do
			roomTypes[i] = rng:weighted(weights)
			actual[i] = Config.ROOM_HINT[roomTypes[i]]
			shown[i] = if rng:chance(Config.MISLEADING_HINT_CHANCE) then rng:pick(Config.HINTS) else actual[i]
		end

		local choice = chooseDoor(d, shown, actual)
		Rooms.emit(d, "doors", { hints = shown, choice = choice })
		Rooms.emit(d, "room", { name = roomTypes[choice] })
		Rooms.resolve(d, roomTypes[choice])

		if not d.alive then
			local last = d.events[#d.events]
			causeName = last.name
			break
		end
	end

	local xp = 0
	if d.alive then
		d.t += Config.ROOM_SECONDS
		xp = d.xp + (Config.XP.perRoom * d.room + Config.XP.returnBonus) * depth
		Rooms.emit(d, "return", { amount = d.gold })
	end

	local levelAfter = Goblin.levelForXp(goblin.xp + xp)
	if levelAfter > goblin.level then
		Rooms.emit(d, "levelup", { amount = levelAfter })
	end

	return {
		id = goblin.id,
		survived = d.alive,
		cause = d.cause,
		causeName = causeName,
		gold = d.gold,
		items = d.items,
		xp = xp,
		levelBefore = goblin.level,
		levelAfter = levelAfter,
		rooms = d.room,
		finishedAt = d.t,
	},
		d.events
end

function Expedition.run(params: Params): Result
	assert(params.depth >= 1, "depth must be >= 1")
	local rng = Rng.new(params.seed)
	local result: Result = {
		seed = params.seed,
		depth = params.depth,
		duration = 0,
		totalGold = 0,
		survivors = 0,
		goblins = {},
		timelines = {},
	}

	for _, goblin in params.goblins do
		local goblinResult, events = delve(goblin, params.depth, rng:fork())
		table.insert(result.goblins, goblinResult)
		result.timelines[goblin.id] = events
		result.totalGold += goblinResult.gold
		result.duration = math.max(result.duration, goblinResult.finishedAt)
		if goblinResult.survived then
			result.survivors += 1
		end
	end

	return result
end

-- All events in playback order (for a single text feed).
function Expedition.merged(result: Result): { Event }
	local all = {}
	for order, goblinResult in result.goblins do
		for index, event in result.timelines[goblinResult.id] do
			table.insert(all, { event = event, order = order, index = index })
		end
	end
	table.sort(all, function(a, b)
		if a.event.t ~= b.event.t then
			return a.event.t < b.event.t
		elseif a.order ~= b.order then
			return a.order < b.order
		end
		return a.index < b.index
	end)
	local events = {}
	for _, entry in all do
		table.insert(events, entry.event)
	end
	return events
end

return Expedition
