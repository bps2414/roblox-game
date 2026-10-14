--!strict
-- Player actions / economy tests. Run: lune run tests/profile.spec

local Config = require("../src/shared/Sim/Config")
local Goblin = require("../src/shared/Sim/Goblin")
local Profile = require("../src/shared/Sim/Profile")

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

local function ids(profile: Profile.Profile): { string }
	local list = {}
	for _, g in profile.goblins do
		table.insert(list, g.id)
	end
	return list
end

print("Profile")
test("new profile has starter goblins and offers", function()
	local p = Profile.new(1)
	check(#p.goblins == Config.STARTING_GOBLINS, "goblins")
	check(#p.tavern == Config.TAVERN_OFFERS, "tavern")
	check(p.gold == Config.STARTING_GOLD, "gold")
	check(p.unlockedDepth == 1, "depth")
	local seen = {}
	for _, g in p.goblins do
		check(not seen[g.id], "duplicate id")
		seen[g.id] = true
	end
	for _, g in p.tavern do
		check(not seen[g.id], "tavern id collides")
	end
end)

test("recruit costs gold and replaces the offer", function()
	local p = Profile.new(2)
	local offer = p.tavern[1]
	local cost = Profile.recruitCost(offer)
	local ok, err = Profile.recruit(p, 1, 99)
	check(ok, err or "")
	check(p.gold == Config.STARTING_GOLD - cost, "gold")
	check(p.goblins[#p.goblins].id == offer.id, "goblin added")
	check(p.tavern[1].id ~= offer.id, "offer replaced")
	check(not Profile.recruit(p, 7, 1), "bad index accepted")
	check(not Profile.recruit(p, "1" :: any, 1), "string index accepted")
	p.gold = 0
	check(not Profile.recruit(p, 1, 1), "recruited while broke")
end)

test("barracks cap", function()
	local p = Profile.new(3)
	p.gold = 10 ^ 6
	for i = 1, 20 do
		Profile.recruit(p, 1, i)
	end
	check(#p.goblins == Config.MAX_GOBLINS, `{#p.goblins} goblins`)
end)

test("buy, equip, unequip, sell items", function()
	local p = Profile.new(4)
	local g = p.goblins[1]
	check(not Profile.equip(p, g.id, "weapon", "dagger"), "equipped unowned item")
	check(Profile.buyItem(p, "dagger"), "buy")
	check(p.inventory.dagger == 1, "inventory")
	check(not Profile.equip(p, g.id, "armor", "dagger"), "wrong slot accepted")
	check(Profile.equip(p, g.id, "weapon", "dagger"), "equip")
	check(g.equipment.weapon == "dagger" and p.inventory.dagger == nil, "moved to goblin")
	check(Profile.equip(p, g.id, "weapon", nil), "unequip")
	check(g.equipment.weapon == "stick" and p.inventory.dagger == 1, "back to inventory")
	local gold = p.gold
	check(Profile.sellItem(p, "dagger"), "sell")
	check(p.gold == gold + 20 and p.inventory.dagger == nil, "sold for half")
	check(not Profile.sellItem(p, "dagger"), "sold twice")
	check(not Profile.buyItem(p, "stick"), "bought free item")
	check(not Profile.buyItem(p, "nope"), "bought unknown item")
end)

test("selling a goblin returns its gear", function()
	local p = Profile.new(5)
	Profile.buyItem(p, "torch")
	local g = p.goblins[1]
	Profile.equip(p, g.id, "utility", "torch")
	local gold = p.gold
	check(Profile.sellGoblin(p, g.id), "sell")
	check(p.gold == gold + Goblin.sellValue(g), "paid")
	check(p.inventory.torch == 1, "gear returned")
	check(Profile.findGoblin(p, g.id) == nil, "still there")
end)

test("run validation", function()
	local p = Profile.new(6)
	check(not Profile.startRun(p, ids(p), 2, 0, 1), "locked floor")
	check(not Profile.startRun(p, {}, 1, 0, 1), "empty party")
	check(not Profile.startRun(p, { "nope" }, 1, 0, 1), "unknown goblin")
	check(not Profile.startRun(p, { p.goblins[1].id, p.goblins[1].id }, 1, 0, 1), "duplicate goblin")
	check(not Profile.startRun(p, ids(p), 1.5, 0, 1), "fractional depth")
	local result = Profile.startRun(p, ids(p), 1, 100, 1)
	check(result ~= nil, "valid run rejected")
	check(not Profile.startRun(p, ids(p), 1, 100, 1), "two runs at once")
	check(not Profile.sellGoblin(p, p.goblins[1].id), "sold goblin on a run")
	check(not Profile.equip(p, p.goblins[1].id, "weapon", nil), "equipped goblin on a run")
end)

test("collect applies the result", function()
	-- Find a run where some die and some live.
	for seed = 1, 500 do
		local p = Profile.new(seed)
		p.unlockedDepth = 3
		local result = assert(Profile.startRun(p, ids(p), 3, 1000, seed))
		if result.survivors > 0 and result.survivors < #p.goblins then
			check(not Profile.collectRun(p, 1000, 1), "collected too early")
			check(Profile.activeResult(p).totalGold == result.totalGold, "replay differs")
			local gold = p.gold
			local summary = assert(Profile.collectRun(p, 1000 + result.duration, 1))
			check(summary.result.totalGold == result.totalGold, "different result on collect")
			check(p.gold == gold + result.totalGold, "gold")
			check(#p.goblins == result.survivors, "dead goblins removed")
			check(p.unlockedDepth == 4 and summary.unlockedDepth == 4, "next floor unlocked")
			check(p.activeRun == nil, "run cleared")
			for _, g in result.goblins do
				local goblin = Profile.findGoblin(p, g.id)
				if g.survived then
					check(goblin and goblin.xp == g.xp, "xp applied")
				end
			end
			check(not Profile.collectRun(p, 10 ^ 9, 1), "collected twice")
			return
		end
	end
	error("no mixed run found")
end)

test("total wipe does not unlock the next floor", function()
	for seed = 1, 2000 do
		local p = Profile.new(seed)
		p.unlockedDepth = 6
		local result = assert(Profile.startRun(p, ids(p), 6, 0, seed))
		if result.survivors == 0 then
			p.gold = 0
			local summary = assert(Profile.collectRun(p, result.duration, 1))
			check(p.unlockedDepth == 6, "unlocked on a wipe")
			if result.totalGold < 20 then
				check(#p.goblins == 1 and summary.pityGoblin ~= nil, "broke player got no pity goblin")
			end
			return
		end
	end
	error("no wipe found")
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
