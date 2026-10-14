--!strict
-- Turns events into the one-line captions shown under the security-camera feed.

local Items = require("./Items")
local Rooms = require("./Rooms")

local Narration = {}

local TRAP_DEATHS: { [string]: string } = {
	spikes = "was skewered by floor spikes",
	boulder = "was flattened by a rolling boulder",
	pit = "fell into a bottomless pit. Still falling, probably",
	darts = "became a goblin pincushion",
	crusher = "was turned into a goblin pancake",
}

local TRAP_HITS: { [string]: string } = {
	spikes = "stepped on spikes",
	boulder = "got clipped by a boulder",
	pit = "tumbled into a pit and climbed out",
	darts = "took a dart to the rear",
	crusher = "got squished, but only a little",
}

local HINT_TEXT: { [string]: string } = {
	quiet = "a quiet door",
	glint = "a door with something glinting behind it",
	growl = "a door with growling behind it",
	glow = "a softly glowing door",
}

local ROOM_TEXT: { [string]: string } = {
	empty = "an empty room",
	treasure = "a treasure room",
	trap = "a suspiciously clean room",
	mimic = "a room with a lovely chest",
	monster = "a room that smells awful",
	shrine = "an old shrine",
}

local function itemName(id: string?): string
	local item = Items.get(id)
	return if item then item.name else tostring(id)
end

function Narration.describe(event: Rooms.Event, goblinName: string): string
	local n = goblinName
	local kind = event.kind
	local amount = event.amount or 0
	local name = event.name or "?"

	if kind == "enter" then
		return `{n} enters floor {amount}.`
	elseif kind == "doors" then
		local hints = event.hints or {}
		if #hints == 1 then
			return `{n} sees only {HINT_TEXT[hints[1]]}.`
		end
		return `{n} picks door {event.choice} of {#hints}: {HINT_TEXT[hints[event.choice or 1]]}.`
	elseif kind == "room" then
		return `It's {ROOM_TEXT[name] or name}.`
	elseif kind == "empty" then
		return `Nothing here. {n} keeps walking.`
	elseif kind == "lost" then
		return `{n} gets lost and wanders around, eating {amount} extra food.`
	elseif kind == "loot" then
		return `{n} grabs {amount} gold!`
	elseif kind == "item" then
		return `{n} found a {itemName(event.name)}!`
	elseif kind == "trap_avoided" then
		return `{n} spots the {name} trap and tiptoes around it.`
	elseif kind == "trap" then
		return `{n} {TRAP_HITS[name] or "hits a trap"} (-{amount} HP).`
	elseif kind == "hardhat" then
		return `The Hard Hat saves {n} from the {name}! It's dented beyond use.`
	elseif kind == "mimic_spotted" then
		return `{n} notices the chest has teeth. Nope.`
	elseif kind == "mimic" then
		return `The chest was a MIMIC! It bites {n} (-{amount} HP).`
	elseif kind == "combat" then
		return `A {name} attacks!`
	elseif kind == "hit" then
		return `{n} hits the {name} for {amount}.`
	elseif kind == "hurt" then
		return `The {name} hits {n} for {amount}.`
	elseif kind == "flee" then
		return `{n} runs away from the {name}!`
	elseif kind == "sneak" then
		return `{n} sneaks past a sleeping {name}.`
	elseif kind == "shrine" then
		if name == "heal" then
			return `The shrine heals {n} (+{amount} HP).`
		elseif name == "feast" then
			return `The shrine offers snacks. {n} eats (+{amount} food).`
		end
		return `The shrine blesses {n}. Everything looks sharper.`
	elseif kind == "starving" then
		return `{n} is starving (-{amount} HP).`
	elseif kind == "death" then
		local cause = event.cause
		if cause == "trap" then
			return `💀 {n} {TRAP_DEATHS[name] or "died in a trap"}.`
		elseif cause == "mimic" then
			return `💀 {n} was eaten by a mimic.`
		elseif cause == "monster" then
			return `💀 {n} was killed by a {name}.`
		elseif cause == "starvation" then
			return `💀 {n} wandered until it starved.`
		end
		return `💀 {n} died.`
	elseif kind == "return" then
		return `🏁 {n} made it out with {amount} gold!`
	elseif kind == "levelup" then
		return `⭐ {n} reached level {amount}!`
	end
	return `{n}: {kind}`
end

return Narration
