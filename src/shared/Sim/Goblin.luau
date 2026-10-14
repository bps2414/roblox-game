--!strict
-- Goblin data (what gets saved) and derived stats.

local Config = require("./Config")
local Items = require("./Items")
local Rng = require("./Rng")

export type Equipment = {
	weapon: string?,
	armor: string?,
	utility: string?,
}

export type Goblin = {
	id: string,
	name: string,
	trait: string,
	level: number,
	xp: number,
	baseHp: number,
	baseFood: number,
	basePerception: number,
	baseLuck: number,
	equipment: Equipment,
}

export type Stats = {
	maxHp: number,
	food: number,
	perception: number, -- 0..100
	luck: number, -- percent bonus to gold
	attack: number,
	defense: number,
	hardHat: boolean,
}

local Goblin = {}

Goblin.TRAIT_INFO = {
	Greedy = "Loves shiny doors. Never suspects mimics.",
	Coward = "Avoids growls, often runs from fights.",
	Dumb = "Ignores door hints. Half perception.",
	Tough = "+4 HP.",
	Glutton = "+6 food, but eats twice as much.",
	Lucky = "+30 luck.",
	Sneaky = "May sneak past monsters.",
}

local NAME_START = { "Gr", "Sn", "Z", "N", "M", "Kr", "Sk", "Bl", "W", "Dr", "Gl", "Pl" }
local NAME_MID = { "ub", "ik", "og", "ib", "urk", "eez", "ag", "ot", "ix", "um", "ap", "ilk" }
local NAME_END = { "", "", "", "le", "ny", "o", "gle", "wick", "bit", "snout", "toe", "rot" }

function Goblin.randomName(rng: Rng.Rng): string
	return rng:pick(NAME_START) .. rng:pick(NAME_MID) .. rng:pick(NAME_END)
end

function Goblin.new(rng: Rng.Rng, id: string): Goblin
	local g = Config.GOBLIN
	return {
		id = id,
		name = Goblin.randomName(rng),
		trait = rng:pick(Config.TRAITS),
		level = 1,
		xp = 0,
		baseHp = rng:int(g.hp[1], g.hp[2]),
		baseFood = rng:int(g.food[1], g.food[2]),
		basePerception = rng:int(g.perception[1], g.perception[2]),
		baseLuck = rng:int(g.luck[1], g.luck[2]),
		equipment = { weapon = "stick", armor = "rags" },
	}
end

function Goblin.stats(goblin: Goblin): Stats
	local bonusLevels = goblin.level - 1
	local stats: Stats = {
		maxHp = goblin.baseHp + bonusLevels * Config.LEVEL_BONUS.hp,
		food = goblin.baseFood,
		perception = goblin.basePerception + bonusLevels * Config.LEVEL_BONUS.perception,
		luck = goblin.baseLuck,
		attack = Config.GOBLIN.attack + bonusLevels * Config.LEVEL_BONUS.attack,
		defense = Config.GOBLIN.defense,
		hardHat = false,
	}

	for _, itemId in { goblin.equipment.weapon, goblin.equipment.armor, goblin.equipment.utility } do
		local item = Items.get(itemId)
		if item then
			stats.attack += item.attack or 0
			stats.defense += item.defense or 0
			stats.perception += item.perception or 0
			stats.luck += item.luck or 0
			stats.food += item.food or 0
			stats.maxHp += item.hp or 0
			stats.hardHat = stats.hardHat or item.hardHat == true
		end
	end

	if goblin.trait == "Tough" then
		stats.maxHp += 4
	elseif goblin.trait == "Glutton" then
		stats.food += 6
	elseif goblin.trait == "Lucky" then
		stats.luck += 30
	elseif goblin.trait == "Dumb" then
		stats.perception = math.floor(stats.perception / 2)
	end

	stats.perception = math.clamp(stats.perception, 0, 100)
	return stats
end

function Goblin.levelForXp(xp: number): number
	local level = 1
	while level < Config.MAX_LEVEL and xp >= Config.xpForLevel(level + 1) do
		level += 1
	end
	return level
end

-- Returns a copy with XP added and level recalculated.
function Goblin.withXp(goblin: Goblin, xp: number): Goblin
	local copy = table.clone(goblin)
	copy.equipment = table.clone(goblin.equipment)
	copy.xp += xp
	copy.level = Goblin.levelForXp(copy.xp)
	return copy
end

function Goblin.sellValue(goblin: Goblin): number
	return Config.sellValue(goblin.level)
end

return Goblin
