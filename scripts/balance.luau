--!strict
-- Monte Carlo balance report.
-- Usage: lune run scripts/balance -- [runs=2000]

local process = require("@lune/process")

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end

local Config = require("../src/shared/Sim/Config")
local Expedition = require("../src/shared/Sim/Expedition")
local Goblin = require("../src/shared/Sim/Goblin")
local Rng = require("../src/shared/Sim/Rng")

local RUNS = tonumber(args[1]) or 2000
local PARTY = 10

local LOADOUTS: { { name: string, level: number, equipment: Goblin.Equipment } } = {
	{ name = "starter", level = 1, equipment = { weapon = "stick", armor = "rags" } },
	{ name = "basic", level = 1, equipment = { weapon = "dagger", armor = "leather", utility = "torch" } },
	{ name = "mid L5", level = 5, equipment = { weapon = "shortsword", armor = "chainmail", utility = "ration" } },
	{ name = "late L10", level = 10, equipment = { weapon = "axe", armor = "plate", utility = "monocle" } },
}

local function party(rng: Rng.Rng, level: number, equipment: Goblin.Equipment): { Goblin.Goblin }
	local goblins = {}
	for i = 1, PARTY do
		local g = Goblin.new(rng, `g{i}`)
		g.level = level
		g.xp = Config.xpForLevel(level)
		g.equipment = table.clone(equipment)
		table.insert(goblins, g)
	end
	return goblins
end

print(`Monte Carlo: {RUNS} runs × {PARTY} goblins per cell. Cells: survival% / gold per goblin sent / main killer\n`)

for _, loadout in LOADOUTS do
	print(
		`--- {loadout.name} ({loadout.equipment.weapon}, {loadout.equipment.armor}, {loadout.equipment.utility or "-"}) ---`
	)
	for depth = 1, 12 do
		local rng = Rng.new(depth * 7919)
		local sent, survived, gold = 0, 0, 0
		local causes: { [string]: number } = {}
		for run = 1, RUNS do
			local result = Expedition.run({
				seed = run * 31 + depth,
				depth = depth,
				goblins = party(rng, loadout.level, loadout.equipment),
			})
			sent += PARTY
			survived += result.survivors
			gold += result.totalGold
			for _, g in result.goblins do
				if g.cause then
					causes[g.cause] = (causes[g.cause] or 0) + 1
				end
			end
		end
		local killer, most = "-", 0
		for cause, n in causes do
			if n > most then
				killer, most = cause, n
			end
		end
		print(
			string.format(
				"  floor %2d: %5.1f%% survive  %7.1f gold/goblin  killer: %s (%d%%)",
				depth,
				survived / sent * 100,
				gold / sent,
				killer,
				if sent - survived > 0 then math.floor(most / (sent - survived) * 100) else 0
			)
		)
	end
	print("")
end

print(
	`Recruit cost {Config.recruitCost(8, 10, 0)}..{Config.recruitCost(12, 30, 20)}; sell value L1/L5/L10 = {Config.sellValue(
		1
	)}/{Config.sellValue(5)}/{Config.sellValue(10)}`
)
