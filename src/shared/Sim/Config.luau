--!strict
-- Every balancing number lives here. Tune with `lune run tests/balance`.

local Config = {}

-- Seconds of playback per room (combat adds per round).
Config.ROOM_SECONDS = 3
Config.COMBAT_ROUND_SECONDS = 0.8
Config.MAX_COMBAT_ROUNDS = 20

-- Floor length grows with depth, so food matters deeper down.
function Config.floorLength(depth: number): number
	return 5 + depth
end

-- Base goblin rolls.
Config.GOBLIN = {
	hp = { 8, 12 },
	food = { 10, 14 },
	perception = { 10, 30 },
	luck = { 0, 20 },
	attack = 1,
	defense = 0,
}

-- Per level above 1.
Config.LEVEL_BONUS = {
	hp = 2,
	perception = 4,
	attack = 1,
}

Config.MAX_LEVEL = 20

-- Total XP needed to *reach* `level`.
function Config.xpForLevel(level: number): number
	return 30 * (level - 1) ^ 2
end

Config.XP = {
	perRoom = 2, -- × depth, only counts if the goblin returns
	perKill = 5, -- × depth
	perAvoid = 3, -- × depth (spotted trap/mimic)
	returnBonus = 10, -- × depth
}

Config.FOOD_PER_ROOM = 1
Config.STARVE_DAMAGE = 2

Config.TRAITS = {
	"Greedy", -- always heads for glints, never suspects mimics
	"Coward", -- avoids growls, often flees fights
	"Dumb", -- ignores door hints, half perception
	"Tough", -- +4 HP
	"Glutton", -- eats 2 food per room, +6 food
	"Lucky", -- +30 luck
	"Sneaky", -- may sneak past monsters
}

-- Room type weights for each door. Depth makes the nasty ones more common.
function Config.roomWeights(depth: number): { [string]: number }
	return {
		empty = 28,
		treasure = 22,
		trap = 12 + 3 * depth,
		mimic = if depth >= 2 then 2 + 1.5 * depth else 0,
		monster = 14 + 2 * depth,
		shrine = 7,
	}
end

Config.DOORS = { 1, 3 }

-- What each room *looks like* from the door. Mimics glint like treasure on purpose.
Config.ROOM_HINT = {
	empty = "quiet",
	treasure = "glint",
	trap = "quiet",
	mimic = "glint",
	monster = "growl",
	shrine = "glow",
}
Config.HINTS = { "quiet", "glint", "growl", "glow" }
Config.MISLEADING_HINT_CHANCE = 0.25

-- How much a normal goblin wants each hint (weighted pick).
Config.HINT_PREFERENCE = {
	quiet = 1.5,
	glint = 3,
	growl = 0.6,
	glow = 2,
}

Config.EMPTY_LOST_CHANCE = 0.2
Config.EMPTY_LOST_FOOD = { 1, 3 }

Config.PERCEPTION_CAP = 0.9
Config.MIMIC_PERCEPTION_FACTOR = 0.6

function Config.trapDamage(depth: number): number
	return 2 + depth * 1.2
end

-- Chance an undetected trap kills outright.
function Config.trapInstantDeathChance(depth: number): number
	if depth < 3 then
		return 0
	end
	return math.min(0.05 * (depth - 2), 0.3)
end

Config.TRAPS = { "spikes", "boulder", "pit", "darts", "crusher" }

Config.MIMIC = {
	bite = function(depth: number): number
		return 3 + 1.5 * depth
	end,
	hp = function(depth: number): number
		return 6 + 3 * depth
	end,
	attack = function(depth: number): number
		return 2 + depth
	end,
	goldMultiplier = 2.5,
}

-- minDepth: first floor it shows up on. Stats scale 10% per floor past minDepth.
Config.MONSTERS = {
	{ name = "Rat", minDepth = 1, hp = 4, attack = 2, gold = 4 },
	{ name = "Bat", minDepth = 1, hp = 3, attack = 3, gold = 3 },
	{ name = "Giant Spider", minDepth = 3, hp = 8, attack = 4, gold = 10 },
	{ name = "Skeleton", minDepth = 4, hp = 10, attack = 5, gold = 14 },
	{ name = "Orc", minDepth = 6, hp = 16, attack = 7, gold = 25 },
	{ name = "Troll", minDepth = 9, hp = 28, attack = 10, gold = 45 },
}
Config.MONSTER_SCALE_PER_DEPTH = 0.1
Config.COWARD_FLEE_CHANCE = 0.5
Config.SNEAKY_SNEAK_CHANCE = 0.35

function Config.treasureGold(depth: number): number
	return 10 * 1.35 ^ (depth - 1)
end
Config.TREASURE_VARIANCE = { 0.6, 1.4 }

function Config.itemDropChance(depth: number): number
	return 0.04 + 0.01 * depth
end

Config.SHRINE = {
	healFraction = 0.5,
	feastFood = 5,
	blessingPerception = 15,
}

-- Economy (used by the server in M2, and by the balance report).
Config.RECRUIT_BASE_COST = 25
Config.RECRUIT_COST_GROWTH = 1.12

function Config.sellValue(level: number): number
	return math.floor(15 + 20 * (level - 1) ^ 1.3)
end

return Config
