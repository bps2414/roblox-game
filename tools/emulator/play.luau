--!nocheck
-- Plays through the game in the emulator and dumps the GUI tree at each step.
-- Usage (from the repo root):
--   rojo sourcemap default.project.json --include-non-scripts -o build/sourcemap-full.json
--   lune run tools/emulator/play -- build/emulator [seed]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Emu = require("./Roblox")

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local outDir = args[1] or "build/emulator"
math.randomseed(tonumber(args[2]) or 7)
fs.writeDir(outDir)

local game = Emu.boot("build/sourcemap-full.json")
local Players = game.Players

local player = Emu.new("Player", "Builder")
player.UserId = 1
Emu.new("PlayerGui", "PlayerGui").Parent = player
player.Parent = Players
Players.LocalPlayer = player
Emu.player = player

local function step(name)
	local gui = player.PlayerGui:FindFirstChild("SendGoblins")
	assert(gui, "no ScreenGui")
	fs.writeFile(`{outDir}/{name}.json`, serde.encode("json", Emu.snapshot(gui)))
	print(`snapshot: {name}`)
end

local function heartbeat()
	game.RunService.Heartbeat:Fire(0.2)
end

local ok, err = pcall(function()
	task.spawn(Emu.run, game.ServerScriptService.Server)
	task.wait(0.1)
	task.spawn(Emu.run, game.StarterPlayer.StarterPlayerScripts.Client)
	task.wait(0.2)
	step("1-base")

	Emu.click(Emu.findText(player.PlayerGui, "^HIRE"))
	Emu.click(Emu.findText(player.PlayerGui, "^BUY 40$"))
	Emu.click(Emu.findText(player.PlayerGui, "^Pointy Stick$"))
	step("2-equip")
	Emu.click(Emu.findText(player.PlayerGui, "^Rusty Dagger"))
	step("3-base-after")

	local function expedition(prefix)
		Emu.click(Emu.findText(player.PlayerGui, "^SEND %d"))
		local state = game.ReplicatedStorage.Remotes.Request:InvokeServer("state")
		local result, run = state.result, state.run
		assert(result, "run did not start")

		-- Find a dramatic moment: someone dead, someone in trouble.
		local Playback = Emu.run(game.ReplicatedStorage.Shared.Sim.Playback)
		local moment, focus = result.duration * 0.6, 1
		for t = 3, result.duration, 0.2 do
			local states = Playback.all(result, t)
			local dead, troubled
			for index, goblin in run.party do
				local s = states[goblin.id]
				if s.status == "dead" then
					dead = true
				elseif s.status == "delving" and s.last and (s.last.kind == "mimic" or s.last.kind == "trap") then
					troubled = index
				end
			end
			if dead and troubled then
				moment, focus = t, troubled
				break
			end
		end
		Emu.now = run.startedAt + moment
		for _ = 2, focus do
			game.UserInputService.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.E }, false)
		end
		heartbeat()
		step(`{prefix}-run`)

		Emu.now = run.startedAt + Playback.endTime(result) + 1
		heartbeat()
		Emu.click(Emu.findText(player.PlayerGui, "^COLLECT"))
		step(`{prefix}-results`)
		Emu.click(Emu.findText(player.PlayerGui, "^CONTINUE"))
	end

	expedition("4")
	step("5-base")
	-- Spend the loot on more goblins and go one floor deeper.
	while pcall(function()
		local hire = Emu.findText(player.PlayerGui, "^HIRE")
		assert(hire.Active)
		Emu.click(hire)
	end) do
	end
	Emu.click(Emu.findText(player.PlayerGui, "^>$"))
	step("6-base-floor2")
	expedition("7")
	step("8-base")
end)

if not ok then
	print("EMULATION FAILED:", err)
	process.exit(1)
end
print("emulation ok")
process.exit(0)
