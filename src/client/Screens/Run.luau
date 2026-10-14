--!strict
-- The security-camera view of a run in progress. Replays the server's result in sync
-- with server time. M2 shows the feed as text; M3 adds pixel-art scenes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Sim = ReplicatedStorage.Shared.Sim
local Config = require(Sim.Config)
local Goblin = require(Sim.Goblin)
local Narration = require(Sim.Narration)
local Playback = require(Sim.Playback)

local Types = require(script.Parent.Parent.Types)
local Ui = require(script.Parent.Parent.Ui)

local Run = {}

local FEED_LINES = 12
local TICK = 0.1

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

function Run.mount(ctx: Types.Ctx, run: any, result: any, _serverNow: number): Types.Screen
	local frame = Ui.new("Frame", {
		Name = "Run",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = ctx.root,
	})

	local party: { any } = run.party
	local byId: { [string]: any } = {}
	local lines: { [string]: { string } } = {}
	for _, goblin in party do
		byId[goblin.id] = goblin
		local list = {}
		for _, event in result.timelines[goblin.id] do
			table.insert(list, Narration.describe(event, goblin.name))
		end
		lines[goblin.id] = list
	end

	local focus = 1
	local finished = false
	local collecting = false

	local function elapsed(): number
		return workspace:GetServerTimeNow() - run.startedAt
	end

	-- Top bar
	local topStats = Ui.label("", {
		Position = UDim2.fromOffset(300, 0),
		Size = UDim2.fromOffset(960, 56),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 22,
	})
	Ui.new("Frame", {
		Size = UDim2.fromOffset(Ui.WIDTH, 56),
		BackgroundColor3 = Ui.color.panel,
		BorderSizePixel = 0,
		Parent = frame,
	}, {
		Ui.title("SEND", {
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.fromOffset(90, 56),
			TextSize = 20,
			TextColor3 = Ui.color.green,
		}),
		Ui.title("GOBLINS", {
			Position = UDim2.fromOffset(110, 0),
			Size = UDim2.fromOffset(160, 56),
			TextSize = 20,
			TextColor3 = Ui.color.gold,
		}),
		topStats,
	})

	-- Main feed
	local feed = Ui.panel({
		Position = UDim2.fromOffset(18, 72),
		Size = UDim2.fromOffset(820, 430),
		BackgroundColor3 = Ui.color.feed,
		BorderColor3 = Ui.color.borderLight,
		ClipsDescendants = true,
		Parent = frame,
	})
	local camLabel = Ui.title("", { Position = UDim2.fromOffset(16, 12), TextColor3 = Ui.color.text, Parent = feed })
	local rec = Ui.title("● REC", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(100, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Ui.color.red,
		Parent = feed,
	})
	local roomLabel = Ui.title("", {
		Position = UDim2.new(0, 16, 1, -36),
		Size = UDim2.fromOffset(400, 24),
		TextColor3 = Ui.color.text,
		Parent = feed,
	})
	local timeLabel = Ui.title("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 1, -36),
		Size = UDim2.fromOffset(200, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Ui.color.text,
		Parent = feed,
	})
	local feedText = Ui.label("", {
		Position = UDim2.fromOffset(24, 48),
		Size = UDim2.new(1, -48, 1, -96),
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = true,
		TextSize = 22,
		TextColor3 = Ui.color.muted,
		Parent = feed,
	})
	local status = Ui.title("", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 22,
		Parent = feed,
	})

	local caption = Ui.label("", {
		Position = UDim2.fromOffset(18, 514),
		Size = UDim2.fromOffset(820, 54),
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.color.black,
		TextColor3 = Ui.color.caption,
		TextSize = 24,
		TextWrapped = true,
		Parent = frame,
	})
	Ui.padding(6, 16).Parent = caption
	Ui.stroke(Ui.color.borderLight).Parent = caption

	local card = Ui.panel({
		Position = UDim2.fromOffset(18, 582),
		Size = UDim2.fromOffset(820, 52),
		Parent = frame,
	}, { Ui.padding(8, 14) })
	local cardName = Ui.label("", { Size = UDim2.fromOffset(330, 36), TextSize = 20, Parent = card })
	local hpBar = Ui.bar(1, Ui.color.red, {
		Position = UDim2.fromOffset(340, 8),
		Size = UDim2.fromOffset(200, 20),
		Parent = card,
	})
	local cardInfo = Ui.label("", {
		Position = UDim2.fromOffset(556, 0),
		Size = UDim2.fromOffset(240, 36),
		TextSize = 20,
		Parent = card,
	})

	-- Camera grid
	Ui.title("SECURITY FEEDS  [Q] < > [E]", {
		Position = UDim2.fromOffset(856, 70),
		Size = UDim2.fromOffset(406, 20),
		Parent = frame,
	})
	local grid = Ui.new("Frame", {
		Position = UDim2.fromOffset(856, 96),
		Size = UDim2.fromOffset(406, 410),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(198, 74),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local render: () -> ()
	local cams: { { button: TextButton, stroke: UIStroke, name: TextLabel, info: TextLabel } } = {}
	for index, goblin in party do
		local button = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = Ui.color.feed,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = grid,
			Activated = function()
				focus = index
				render()
			end,
		})
		local stroke = Ui.stroke(Ui.color.borderLight) :: UIStroke
		stroke.Parent = button
		local name = Ui.title(`CAM {string.format("%02d", index)} {goblin.name:upper()}`, {
			Position = UDim2.fromOffset(8, 6),
			Size = UDim2.new(1, -16, 0, 18),
			TextSize = 9,
			TextColor3 = Ui.color.text,
			Parent = button,
		})
		local info = Ui.label("", {
			Position = UDim2.fromOffset(8, 30),
			Size = UDim2.new(1, -16, 0, 36),
			TextSize = 18,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = button,
		})
		cams[index] = { button = button, stroke = stroke, name = name, info = info }
	end

	local log = Ui.label("", {
		Position = UDim2.fromOffset(856, 514),
		Size = UDim2.fromOffset(406, 120),
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.color.black,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = true,
		TextSize = 16,
		TextColor3 = Ui.color.muted,
		ClipsDescendants = true,
		Parent = frame,
	})
	Ui.padding(6, 10).Parent = log
	Ui.stroke().Parent = log

	local collect = Ui.button("WAITING FOR GOBLINS...", function() end, {
		Enabled = false,
		Position = UDim2.fromOffset(18, 648),
		Size = UDim2.fromOffset(1244, 56),
		TextSize = 16,
		Parent = frame,
	})

	local function doCollect()
		if collecting or ctx.busy then
			return
		end
		collecting = true
		local response = ctx.call("collect")
		collecting = false
		if response.ok then
			ctx.showResults(response.summary, party)
		end
	end

	render = function()
		local t = elapsed()
		local states = Playback.all(result, t)
		finished = Playback.isFinished(result, t)

		local alive, loot = 0, 0
		for index, goblin in party do
			local state = states[goblin.id]
			local stats = Goblin.stats(goblin)
			loot += state.gold
			if state.status ~= "dead" then
				alive += 1
			end

			local cam = cams[index]
			cam.stroke.Color = if index == focus then Ui.color.green else Ui.color.borderLight
			cam.button.BackgroundColor3 = if state.status == "dead" then Ui.color.darkRed else Ui.color.feed
			if state.status == "dead" then
				local last = state.last
				local killer = if last then last.name or last.cause else nil
				cam.info.Text = Ui.paint(`💀 {killer or "dead"}`, Ui.color.red) .. `  🪙{state.gold}`
			elseif state.status == "returned" then
				cam.info.Text = Ui.paint("🏁 MADE IT OUT", Ui.color.green) .. `  🪙{state.gold}`
			else
				cam.info.Text = `♥{state.hp or stats.maxHp}/{stats.maxHp}  🪙{state.gold}  R{state.room}`
			end
		end

		topStats.Text = `FLOOR {Ui.paint(tostring(run.depth), Ui.color.gold)}    ALIVE {Ui.paint(
			`{alive}/{#party}`,
			Ui.color.gold
		)}    LOOT {Ui.paint(tostring(loot), Ui.color.gold)}    RUN {Ui.paint(
			`{clock(math.min(t, result.duration))}/{clock(result.duration)}`,
			Ui.color.gold
		)}`

		-- Focused camera
		local goblin = party[focus]
		local state = states[goblin.id]
		local stats = Goblin.stats(goblin)
		local hp = state.hp or stats.maxHp
		camLabel.Text = `CAM {string.format("%02d", focus)} · {goblin.name:upper()}`
		roomLabel.Text = `FLOOR {run.depth} · ROOM {state.room}/{Config.floorLength(run.depth)}`
		timeLabel.Text = `00:{clock(t)}`
		rec.Visible = state.status == "delving" and math.floor(t * 2) % 2 == 0

		local goblinLines = lines[goblin.id]
		local from = math.max(1, state.shown - FEED_LINES + 1)
		local shown = {}
		for i = from, state.shown do
			table.insert(shown, goblinLines[i])
		end
		feedText.Text = table.concat(shown, "\n")
		caption.Text = if state.shown > 0 then goblinLines[state.shown] else `{goblin.name} waits at the entrance...`

		if state.status == "dead" then
			status.Text = "SIGNAL LOST"
			status.TextColor3 = Ui.color.red
		elseif state.status == "returned" then
			status.Text = "MADE IT OUT"
			status.TextColor3 = Ui.color.green
		else
			status.Text = ""
		end

		cardName.Text = `{Ui.paint(goblin.name, Ui.color.green)}  {Ui.paint(goblin.trait, Ui.color.muted)}  HP {hp}/{stats.maxHp}`
		Ui.setBar(hpBar, hp / stats.maxHp)
		cardInfo.Text = `🪙 {state.gold}`

		-- Recent events from every camera
		local recent = {}
		for id, list in lines do
			local feedState = states[id]
			if feedState.shown > 0 then
				table.insert(recent, { t = feedState.last and feedState.last.t or 0, text = list[feedState.shown] })
			end
		end
		table.sort(recent, function(a, b)
			return a.t < b.t
		end)
		local logLines = {}
		for i = math.max(1, #recent - 3), #recent do
			table.insert(logLines, recent[i].text)
		end
		log.Text = table.concat(logLines, "\n")

		if finished then
			collect.Text = `COLLECT {loot} GOLD`
			collect.Active = true
			collect.AutoButtonColor = true
			collect.BackgroundColor3 = Ui.color.darkGold
			collect.TextColor3 = Ui.color.gold
		end
	end

	collect.Activated:Connect(function()
		if finished then
			doCollect()
		end
	end)

	local inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			focus = if focus == 1 then #party else focus - 1
			render()
		elseif input.KeyCode == Enum.KeyCode.E then
			focus = if focus == #party then 1 else focus + 1
			render()
		end
	end)

	local accumulator = 0
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= TICK then
			accumulator = 0
			render()
		end
	end)

	render()

	return {
		destroy = function()
			heartbeat:Disconnect()
			inputConnection:Disconnect()
			frame:Destroy()
		end,
		refresh = render,
	}
end

return Run
