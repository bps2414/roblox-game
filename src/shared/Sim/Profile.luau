--!strict
-- Player save data and every action the player can take. Pure Luau: the server wraps
-- it with remotes + DataStore, tests drive it directly. Every action validates its input
-- (it comes from the client) and returns ok, err.
--
-- Randomness that the client must not predict (run seeds, tavern rolls) is passed in
-- by the server as `seed`.

local Config = require("./Config")
local Expedition = require("./Expedition")
local Goblin = require("./Goblin")
local Items = require("./Items")
local Rng = require("./Rng")

export type ActiveRun = {
	seed: number,
	depth: number,
	startedAt: number,
	duration: number,
	party: { Goblin.Goblin }, -- snapshot at send time (result is recomputed from it)
}

export type Profile = {
	version: number,
	gold: number,
	unlockedDepth: number,
	nextId: number,
	goblins: { Goblin.Goblin },
	inventory: { [string]: number },
	tavern: { Goblin.Goblin },
	activeRun: ActiveRun?,
	stats: {
		runs: number,
		sent: number,
		deaths: number,
		goldEarned: number,
		deepest: number,
	},
}

export type RunSummary = {
	result: Expedition.Result,
	unlockedDepth: number?, -- set when this run unlocked a new floor
	levelUps: { [string]: number },
	pityGoblin: string?, -- name of the free goblin given to a broke, empty barracks
}

local Profile = {}

Profile.VERSION = 1

local function nameTaken(profile: Profile, name: string): boolean
	for _, list in { profile.goblins, profile.tavern } do
		for _, goblin in list do
			if goblin.name == name then
				return true
			end
		end
	end
	return false
end

local function newGoblin(profile: Profile, rng: Rng.Rng): Goblin.Goblin
	local goblin = Goblin.new(rng, `G{profile.nextId}`)
	profile.nextId += 1
	-- Two goblins called Snix is one too many.
	for _ = 1, 20 do
		if not nameTaken(profile, goblin.name) then
			break
		end
		goblin.name = Goblin.randomName(rng)
	end
	return goblin
end

local function rollTavern(profile: Profile, seed: number)
	local rng = Rng.new(seed)
	profile.tavern = {}
	for _ = 1, Config.TAVERN_OFFERS do
		table.insert(profile.tavern, newGoblin(profile, rng))
	end
end

function Profile.new(seed: number): Profile
	local profile: Profile = {
		version = Profile.VERSION,
		gold = Config.STARTING_GOLD,
		unlockedDepth = 1,
		nextId = 1,
		goblins = {},
		inventory = {},
		tavern = {},
		activeRun = nil,
		stats = { runs = 0, sent = 0, deaths = 0, goldEarned = 0, deepest = 0 },
	}
	local rng = Rng.new(seed)
	for _ = 1, Config.STARTING_GOBLINS do
		table.insert(profile.goblins, newGoblin(profile, rng))
	end
	rollTavern(profile, rng:nextU32())
	return profile
end

function Profile.recruitCost(goblin: Goblin.Goblin): number
	return Config.recruitCost(goblin.baseHp, goblin.basePerception, goblin.baseLuck)
end

function Profile.findGoblin(profile: Profile, id: any): (Goblin.Goblin?, number?)
	for index, goblin in profile.goblins do
		if goblin.id == id then
			return goblin, index
		end
	end
	return nil, nil
end

function Profile.isOnRun(profile: Profile, id: string): boolean
	local run = profile.activeRun
	if run then
		for _, goblin in run.party do
			if goblin.id == id then
				return true
			end
		end
	end
	return false
end

-- Free starter gear (price 0) is always available and never stored.
local function isFree(item: Items.Item): boolean
	return item.price == 0
end

local function addItem(profile: Profile, id: string?)
	local item = Items.get(id)
	if item and not isFree(item) then
		profile.inventory[item.id] = (profile.inventory[item.id] or 0) + 1
	end
end

local function takeItem(profile: Profile, id: string): boolean
	local item = Items.get(id)
	if not item then
		return false
	end
	if isFree(item) then
		return true
	end
	local count = profile.inventory[id] or 0
	if count <= 0 then
		return false
	end
	if count == 1 then
		profile.inventory[id] = nil
	else
		profile.inventory[id] = count - 1
	end
	return true
end

function Profile.recruit(profile: Profile, index: any, seed: number): (boolean, string?)
	if type(index) ~= "number" or profile.tavern[index] == nil then
		return false, "No such recruit"
	end
	if #profile.goblins >= Config.MAX_GOBLINS then
		return false, "Barracks are full"
	end
	local goblin = profile.tavern[index]
	local cost = Profile.recruitCost(goblin)
	if profile.gold < cost then
		return false, "Not enough gold"
	end
	profile.gold -= cost
	table.insert(profile.goblins, goblin)
	profile.tavern[index] = newGoblin(profile, Rng.new(seed))
	return true, nil
end

function Profile.sellGoblin(profile: Profile, id: any): (boolean, string?)
	local goblin, index = Profile.findGoblin(profile, id)
	if not goblin or not index then
		return false, "No such goblin"
	end
	if Profile.isOnRun(profile, goblin.id) then
		return false, "That goblin is in the dungeon"
	end
	-- Gear goes back to the inventory, the goblin goes to a "better place".
	addItem(profile, goblin.equipment.weapon)
	addItem(profile, goblin.equipment.armor)
	addItem(profile, goblin.equipment.utility)
	profile.gold += Goblin.sellValue(goblin)
	table.remove(profile.goblins, index)
	return true, nil
end

function Profile.buyItem(profile: Profile, id: any): (boolean, string?)
	local item = Items.get(if type(id) == "string" then id else nil)
	if not item or isFree(item) then
		return false, "No such item"
	end
	if profile.gold < item.price then
		return false, "Not enough gold"
	end
	profile.gold -= item.price
	addItem(profile, item.id)
	return true, nil
end

function Profile.sellItem(profile: Profile, id: any): (boolean, string?)
	local item = Items.get(if type(id) == "string" then id else nil)
	if not item or isFree(item) then
		return false, "No such item"
	end
	if not takeItem(profile, item.id) then
		return false, "You don't have that"
	end
	profile.gold += math.floor(item.price * Config.ITEM_SELL_FRACTION)
	return true, nil
end

-- itemId nil = unequip (weapon/armor fall back to the free starter gear).
function Profile.equip(profile: Profile, goblinId: any, slot: any, itemId: any): (boolean, string?)
	local goblin = Profile.findGoblin(profile, goblinId)
	if not goblin then
		return false, "No such goblin"
	end
	if Profile.isOnRun(profile, goblin.id) then
		return false, "That goblin is in the dungeon"
	end
	if slot ~= "weapon" and slot ~= "armor" and slot ~= "utility" then
		return false, "Bad slot"
	end

	local newItem: Items.Item? = nil
	if itemId ~= nil then
		newItem = Items.get(if type(itemId) == "string" then itemId else nil)
		if not newItem or newItem.slot ~= slot then
			return false, "That doesn't go there"
		end
	elseif slot == "weapon" then
		newItem = Items.get("stick")
	elseif slot == "armor" then
		newItem = Items.get("rags")
	end

	local current = (goblin.equipment :: any)[slot]
	if newItem and current == newItem.id then
		return true, nil
	end
	if newItem and not takeItem(profile, newItem.id) then
		return false, "You don't have that"
	end
	addItem(profile, current)
	;(goblin.equipment :: any)[slot] = if newItem then newItem.id else nil
	return true, nil
end

function Profile.startRun(profile: Profile, ids: any, depth: any, now: number, seed: number): (Expedition.Result?, string?)
	if profile.activeRun then
		return nil, "A run is already in progress"
	end
	if type(depth) ~= "number" or depth ~= math.floor(depth) or depth < 1 or depth > profile.unlockedDepth then
		return nil, "That floor is locked"
	end
	if type(ids) ~= "table" or #ids < 1 or #ids > Config.MAX_PARTY then
		return nil, `Send between 1 and {Config.MAX_PARTY} goblins`
	end

	local party, seen = {}, {}
	for _, id in ids do
		local goblin = Profile.findGoblin(profile, id)
		if not goblin or seen[goblin.id] then
			return nil, "Bad party"
		end
		seen[goblin.id] = true
		local snapshot = table.clone(goblin)
		snapshot.equipment = table.clone(goblin.equipment)
		table.insert(party, snapshot)
	end

	local result = Expedition.run({ seed = seed, depth = depth, goblins = party })
	profile.activeRun = {
		seed = seed,
		depth = depth,
		startedAt = now,
		duration = result.duration,
		party = party,
	}
	profile.stats.runs += 1
	profile.stats.sent += #party
	return result, nil
end

-- Recomputes the active run's result (e.g. after the player rejoins).
function Profile.activeResult(profile: Profile): Expedition.Result?
	local run = profile.activeRun
	if not run then
		return nil
	end
	return Expedition.run({ seed = run.seed, depth = run.depth, goblins = run.party })
end

function Profile.collectRun(profile: Profile, now: number, tavernSeed: number): (RunSummary?, string?)
	local run = profile.activeRun
	if not run then
		return nil, "No run to collect"
	end
	if now + Config.COLLECT_TOLERANCE < run.startedAt + run.duration then
		return nil, "The goblins are still down there"
	end

	local result = Expedition.run({ seed = run.seed, depth = run.depth, goblins = run.party })
	local summary: RunSummary = { result = result, unlockedDepth = nil, levelUps = {} }

	profile.gold += result.totalGold
	profile.stats.goldEarned += result.totalGold

	for _, goblinResult in result.goblins do
		for _, itemId in goblinResult.items do
			addItem(profile, itemId)
		end

		local goblin, index = Profile.findGoblin(profile, goblinResult.id)
		if goblin and index then
			if goblinResult.survived then
				local updated = Goblin.withXp(goblin, goblinResult.xp)
				if goblinResult.hardHatBroken and updated.equipment.utility == "hardhat" then
					updated.equipment.utility = nil
				end
				if updated.level > goblin.level then
					summary.levelUps[goblin.id] = updated.level
				end
				profile.goblins[index] = updated
			else
				-- Dead goblins don't come back, and neither does their gear.
				table.remove(profile.goblins, index)
				profile.stats.deaths += 1
			end
		end
	end

	if result.survivors > 0 then
		profile.stats.deepest = math.max(profile.stats.deepest, run.depth)
		if run.depth == profile.unlockedDepth then
			profile.unlockedDepth += 1
			summary.unlockedDepth = profile.unlockedDepth
		end
	end

	profile.activeRun = nil
	rollTavern(profile, tavernSeed)

	-- Never leave a player with no goblins and no way to buy one.
	if #profile.goblins == 0 then
		local cheapest = math.huge
		for _, offer in profile.tavern do
			cheapest = math.min(cheapest, Profile.recruitCost(offer))
		end
		if profile.gold < cheapest then
			local goblin = newGoblin(profile, Rng.new(tavernSeed + 1))
			table.insert(profile.goblins, goblin)
			summary.pityGoblin = goblin.name
		end
	end
	return summary, nil
end

-- Fills in fields added after a profile was first saved.
function Profile.migrate(data: any, seed: number): Profile
	if type(data) ~= "table" or data.version == nil then
		return Profile.new(seed)
	end
	return data :: Profile
end

return Profile
