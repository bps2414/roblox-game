--!strict
-- Simulation tests. Run: lune run tests/sim.spec

local Config = require("../src/shared/Sim/Config")
local Expedition = require("../src/shared/Sim/Expedition")
local Goblin = require("../src/shared/Sim/Goblin")
local Narration = require("../src/shared/Sim/Narration")
local Rng = require("../src/shared/Sim/Rng")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(`  ✓ {name}`)
	else
		failed += 1
		print(`  ✗ {name}\n      {err}`)
	end
end

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function serialize(value: any): string
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for key in value do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		local v = value[key]
		if v == nil then
			v = value[tonumber(key)]
		end
		table.insert(parts, `{key}={serialize(v)}`)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function party(seed: number, size: number): { Goblin.Goblin }
	local rng = Rng.new(seed)
	local goblins = {}
	for i = 1, size do
		table.insert(goblins, Goblin.new(rng, `g{i}`))
	end
	return goblins
end

print("Rng")
test("int stays in bounds", function()
	local rng = Rng.new(1)
	for _ = 1, 10000 do
		local n = rng:int(1, 3)
		check(n >= 1 and n <= 3 and n == math.floor(n), `out of bounds: {n}`)
	end
end)

test("weighted roughly follows weights", function()
	local rng = Rng.new(7)
	local counts = { a = 0, b = 0 }
	for _ = 1, 20000 do
		local key = rng:weighted({ a = 1, b = 3 })
		counts[key] += 1
	end
	local ratio = counts.b / counts.a
	check(ratio > 2.7 and ratio < 3.3, `ratio {ratio}`)
end)

test("same seed => same sequence", function()
	local a, b = Rng.new(42), Rng.new(42)
	for _ = 1, 100 do
		check(a:nextU32() == b:nextU32(), "diverged")
	end
end)

print("Goblin")
test("level thresholds", function()
	check(Goblin.levelForXp(0) == 1, "0 xp")
	check(Goblin.levelForXp(Config.xpForLevel(2) - 1) == 1, "just under 2")
	check(Goblin.levelForXp(Config.xpForLevel(2)) == 2, "exactly 2")
	check(Goblin.levelForXp(10 ^ 9) == Config.MAX_LEVEL, "capped")
end)

test("equipment changes stats", function()
	local g = party(3, 1)[1]
	g.trait = "Tough"
	local before = Goblin.stats(g)
	g.equipment.weapon = "dagger"
	g.equipment.armor = "chainmail"
	g.equipment.utility = "hardhat"
	local after = Goblin.stats(g)
	check(after.attack == before.attack + 2, "attack")
	check(after.defense == before.defense + 3, "defense")
	check(after.hardHat and not before.hardHat, "hard hat")
end)

test("withXp does not mutate the original", function()
	local g = party(4, 1)[1]
	local leveled = Goblin.withXp(g, 1000)
	check(g.xp == 0 and g.level == 1, "mutated")
	check(leveled.level > 1, "did not level")
end)

print("Expedition")
test("deterministic for the same seed", function()
	local goblins = party(5, 8)
	local a = Expedition.run({ seed = 99, depth = 4, goblins = goblins })
	local b = Expedition.run({ seed = 99, depth = 4, goblins = goblins })
	check(serialize(a) == serialize(b), "results differ")
end)

test("different seeds give different runs", function()
	local goblins = party(5, 8)
	local a = Expedition.run({ seed = 1, depth = 4, goblins = goblins })
	local b = Expedition.run({ seed = 2, depth = 4, goblins = goblins })
	check(serialize(a) ~= serialize(b), "identical results")
end)

test("invariants hold across 3000 runs", function()
	local rng = Rng.new(2024)
	for run = 1, 3000 do
		local depth = rng:int(1, 12)
		local goblins = party(run, rng:int(1, 10))
		local result = Expedition.run({ seed = run, depth = depth, goblins = goblins })
		local survivors, total = 0, 0

		for i, g in result.goblins do
			local events = result.timelines[g.id]
			local where = `run {run} depth {depth} goblin {g.id}`
			check(g.id == goblins[i].id, `order {where}`)
			check(g.survived == (g.cause == nil), `survived/cause mismatch {where}`)
			check(g.gold >= 0, `negative gold {where}`)
			check(g.rooms <= Config.floorLength(depth), `too many rooms {where}`)
			if not g.survived then
				check(g.xp == 0, `dead goblin got xp {where}`)
				check(events[#events].kind == "death", `dead without death event {where}`)
			end

			local lootSum, lastT, sawReturn = 0, 0, false
			for _, e in events do
				check(e.t >= lastT, `time went backwards {where}`)
				lastT = e.t
				check((e.hp or 0) >= 0, `negative hp in event {where}`)
				if e.kind == "loot" then
					lootSum += e.amount or 0
				elseif e.kind == "return" then
					sawReturn = true
				end
				local text = Narration.describe(e, "Test")
				check(not string.find(text, ": " .. e.kind, 1, true), `no narration for {e.kind}`)
			end
			check(lootSum == g.gold, `loot events {lootSum} ~= gold {g.gold} {where}`)
			check(sawReturn == g.survived, `return event mismatch {where}`)

			total += g.gold
			if g.survived then
				survivors += 1
			end
		end
		check(survivors == result.survivors, "survivor count")
		check(total == result.totalGold, "total gold")
	end
end)

test("merged events are in time order", function()
	local result = Expedition.run({ seed = 11, depth = 3, goblins = party(11, 5) })
	local lastT = 0
	for _, e in Expedition.merged(result) do
		check(e.t >= lastT, "out of order")
		lastT = e.t
	end
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
