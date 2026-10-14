--!strict
-- What happens inside each room type. Every outcome is appended as an event so the
-- client can replay it.

local Config = require("./Config")
local Goblin = require("./Goblin")
local Items = require("./Items")
local Rng = require("./Rng")

export type Event = {
	t: number,
	goblinId: string,
	room: number,
	kind: string,
	amount: number?, -- damage, gold, food, xp...
	hp: number?, -- goblin HP after the event
	name: string?, -- monster / trap / item / shrine effect
	hints: { string }?,
	choice: number?,
	cause: string?,
}

export type Delver = {
	goblin: Goblin.Goblin,
	stats: Goblin.Stats,
	rng: Rng.Rng,
	events: { Event },
	depth: number,
	room: number,
	t: number,
	hp: number,
	food: number,
	perception: number,
	gold: number,
	xp: number,
	kills: number,
	items: { string },
	alive: boolean,
	cause: string?,
}

local Rooms = {}

function Rooms.emit(d: Delver, kind: string, extra: { [string]: any }?)
	local event: Event = {
		t = d.t,
		goblinId = d.goblin.id,
		room = d.room,
		kind = kind,
		hp = math.max(0, d.hp),
	}
	if extra then
		for key, value in extra do
			(event :: any)[key] = value
		end
	end
	table.insert(d.events, event)
end

local function die(d: Delver, cause: string, name: string?)
	d.hp = 0
	d.alive = false
	d.cause = cause
	Rooms.emit(d, "death", { cause = cause, name = name })
end

local function hurt(d: Delver, amount: number, cause: string, name: string?)
	d.hp -= amount
	if d.hp <= 0 then
		die(d, cause, name)
	end
end

local function perceives(d: Delver, factor: number): boolean
	local chance = math.min(d.perception / 100 * factor, Config.PERCEPTION_CAP)
	return d.rng:chance(chance)
end

local function avoided(d: Delver, kind: string, name: string?)
	local xp = Config.XP.perAvoid * d.depth
	d.xp += xp
	Rooms.emit(d, kind, { name = name, amount = xp })
end

-- Goblin swings first. Returns true if the goblin won.
local function fight(d: Delver, name: string, hp: number, attack: number, cause: string): boolean
	Rooms.emit(d, "combat", { name = name, amount = hp })
	local enemyHp = hp
	for _ = 1, Config.MAX_COMBAT_ROUNDS do
		d.t += Config.COMBAT_ROUND_SECONDS
		local dealt = d.stats.attack + d.rng:int(0, 1)
		enemyHp -= dealt
		Rooms.emit(d, "hit", { amount = dealt, name = name })
		if enemyHp <= 0 then
			d.kills += 1
			return true
		end

		d.t += Config.COMBAT_ROUND_SECONDS
		local taken = math.max(1, attack + d.rng:int(-1, 1) - d.stats.defense)
		d.hp -= taken
		Rooms.emit(d, "hurt", { amount = taken, name = name })
		if d.hp <= 0 then
			die(d, cause, name)
			return false
		end
	end
	-- Stalemate: both wander off bruised.
	Rooms.emit(d, "flee", { name = name })
	return false
end

local function addGold(d: Delver, amount: number, name: string?)
	local gold = math.max(1, math.floor(amount * (1 + d.stats.luck / 100)))
	d.gold += gold
	Rooms.emit(d, "loot", { amount = gold, name = name })
end

local function rollItemDrop(d: Delver)
	if d.rng:chance(Config.itemDropChance(d.depth)) then
		local item = d.rng:pick(Items.dropPool(d.depth))
		table.insert(d.items, item.id)
		Rooms.emit(d, "item", { name = item.id })
	end
end

local handlers: { [string]: (Delver) -> () } = {}

function handlers.empty(d: Delver)
	if d.rng:chance(Config.EMPTY_LOST_CHANCE) then
		local lost = d.rng:int(Config.EMPTY_LOST_FOOD[1], Config.EMPTY_LOST_FOOD[2])
		d.food = math.max(0, d.food - lost)
		Rooms.emit(d, "lost", { amount = lost })
	else
		Rooms.emit(d, "empty")
	end
end

function handlers.treasure(d: Delver)
	local v = Config.TREASURE_VARIANCE
	addGold(d, Config.treasureGold(d.depth) * d.rng:range(v[1], v[2]), "chest")
	rollItemDrop(d)
end

function handlers.trap(d: Delver)
	local trap = d.rng:pick(Config.TRAPS)
	if perceives(d, 1) then
		avoided(d, "trap_avoided", trap)
		return
	end

	if d.rng:chance(Config.trapInstantDeathChance(d.depth)) then
		if d.stats.hardHat then
			d.hp = 1
			d.stats.hardHat = false
			Rooms.emit(d, "hardhat", { name = trap })
		else
			die(d, "trap", trap)
		end
		return
	end

	local damage = math.max(1, math.floor(Config.trapDamage(d.depth) + d.rng:int(-1, 1)) - d.stats.defense)
	Rooms.emit(d, "trap", { name = trap, amount = damage, hp = math.max(0, d.hp - damage) })
	hurt(d, damage, "trap", trap)
end

function handlers.mimic(d: Delver)
	if d.goblin.trait ~= "Greedy" and perceives(d, Config.MIMIC_PERCEPTION_FACTOR) then
		avoided(d, "mimic_spotted")
		return
	end

	local bite = math.max(1, math.floor(Config.mimicBite(d.depth)) - d.stats.defense)
	Rooms.emit(d, "mimic", { amount = bite, hp = math.max(0, d.hp - bite) })
	hurt(d, bite, "mimic", "Mimic")
	if d.alive then
		Rooms.emit(d, "mimic_escape")
	end
end

local function pickMonster(d: Delver)
	local pool = {}
	for _, monster in Config.MONSTERS do
		if monster.minDepth <= d.depth then
			table.insert(pool, monster)
		end
	end
	-- Favor the toughest monsters available on this floor.
	local index = math.max(d.rng:int(1, #pool), d.rng:int(1, #pool))
	return pool[index]
end

function handlers.monster(d: Delver)
	local monster = pickMonster(d)
	local scale = 1 + Config.MONSTER_SCALE_PER_DEPTH * (d.depth - monster.minDepth)
	local hp = math.floor(monster.hp * scale)
	local attack = math.floor(monster.attack * scale)

	if d.goblin.trait == "Sneaky" and d.rng:chance(Config.SNEAKY_SNEAK_CHANCE) then
		avoided(d, "sneak", monster.name)
		return
	end

	if d.goblin.trait == "Coward" and d.rng:chance(Config.COWARD_FLEE_CHANCE) then
		local taken = math.max(1, attack - d.stats.defense)
		Rooms.emit(d, "flee", { name = monster.name, amount = taken, hp = math.max(0, d.hp - taken) })
		hurt(d, taken, "monster", monster.name)
		return
	end

	if fight(d, monster.name, hp, attack, "monster") then
		d.xp += Config.XP.perKill * d.depth
		addGold(d, monster.gold * scale, monster.name)
	end
end

function handlers.shrine(d: Delver)
	local effect = d.rng:pick({ "heal", "feast", "blessing" })
	local s = Config.SHRINE
	if effect == "heal" then
		local amount = math.max(1, math.floor(d.stats.maxHp * s.healFraction))
		d.hp = math.min(d.stats.maxHp, d.hp + amount)
		Rooms.emit(d, "shrine", { name = effect, amount = amount })
	elseif effect == "feast" then
		d.food += s.feastFood
		Rooms.emit(d, "shrine", { name = effect, amount = s.feastFood })
	else
		d.perception = math.min(100, d.perception + s.blessingPerception)
		Rooms.emit(d, "shrine", { name = effect, amount = s.blessingPerception })
	end
end

function Rooms.resolve(d: Delver, roomType: string)
	handlers[roomType](d)
end

return Rooms
