--!strict
-- Text "security feed" of one expedition.
-- Usage: lune run scripts/watch -- [depth=3] [goblins=6] [seed=random]

local process = require("@lune/process")

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end

local Expedition = require("../src/shared/Sim/Expedition")
local Goblin = require("../src/shared/Sim/Goblin")
local Narration = require("../src/shared/Sim/Narration")
local Rng = require("../src/shared/Sim/Rng")

local depth = tonumber(args[1]) or 3
local count = tonumber(args[2]) or 6
local seed = tonumber(args[3]) or os.time()

local rng = Rng.new(seed)
local goblins = {}
local names = {}
for i = 1, count do
	local g = Goblin.new(rng, `g{i}`)
	table.insert(goblins, g)
	names[g.id] = g.name
end

print(`=== SEND GOBLINS — floor {depth}, {count} goblins, seed {seed} ===\n`)
for _, g in goblins do
	local s = Goblin.stats(g)
	print(
		string.format(
			"  %-14s %-8s HP %2d  Food %2d  Perc %2d  Luck %2d",
			g.name,
			g.trait,
			s.maxHp,
			s.food,
			s.perception,
			s.luck
		)
	)
end
print("")

local result = Expedition.run({ seed = seed, depth = depth, goblins = goblins })
for _, e in Expedition.merged(result) do
	if e.kind ~= "hit" and e.kind ~= "hurt" then
		print(string.format("[%5.1fs] %s", e.t, Narration.describe(e, names[e.goblinId])))
	end
end

print(`\n=== {result.survivors}/{count} came back. Loot: {result.totalGold} gold. ({result.duration}s of footage) ===`)
for _, g in result.goblins do
	local status = if g.survived
		then `back, +{g.xp} xp`
		else `died ({g.cause}{if g.causeName then ": " .. g.causeName else ""})`
	print(string.format("  %-14s room %2d  %4d gold  %s", names[g.id], g.rooms, g.gold, status))
end
