-- M1 demo: each player that joins triggers one expedition, narrated in the Output window.
-- Replaced by the real game flow in M2.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sim = ReplicatedStorage.Shared.Sim
local Expedition = require(Sim.Expedition)
local Goblin = require(Sim.Goblin)
local Narration = require(Sim.Narration)
local Rng = require(Sim.Rng)

local DEPTH = 3
local PARTY_SIZE = 6

Players.PlayerAdded:Connect(function(player)
	local seed = os.time() + player.UserId
	local rng = Rng.new(seed)
	local goblins, names = {}, {}
	for i = 1, PARTY_SIZE do
		local goblin = Goblin.new(rng, `g{i}`)
		table.insert(goblins, goblin)
		names[goblin.id] = goblin.name
	end

	local result = Expedition.run({ seed = seed, depth = DEPTH, goblins = goblins })
	print(`[Send Goblins] {player.Name} sends {PARTY_SIZE} goblins to floor {DEPTH} (seed {seed})`)

	-- Replay in real time, like the client will in M2/M3.
	local start = os.clock()
	for _, event in Expedition.merged(result) do
		if event.kind ~= "hit" and event.kind ~= "hurt" then
			local wait = event.t - (os.clock() - start)
			if wait > 0 then
				task.wait(wait)
			end
			print(string.format("[%5.1fs] %s", event.t, Narration.describe(event, names[event.goblinId])))
		end
	end
	print(`[Send Goblins] {result.survivors}/{PARTY_SIZE} came back with {result.totalGold} gold.`)
end)
