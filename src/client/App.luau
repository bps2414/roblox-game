--!strict
-- Owns the screen, the latest profile and UI-only state (party selection, floor), and
-- switches between the Base, Run and Results screens.

local Players = game:GetService("Players")

local Net = require(script.Parent.Net)
local Types = require(script.Parent.Types)
local Ui = require(script.Parent.Ui)

local Screens = script.Parent.Screens
local BaseScreen = require(Screens.Base)
local ResultsScreen = require(Screens.Results)
local RunScreen = require(Screens.Run)

type Ctx = Types.Ctx

local App = {}

function App.start()
	local gui = Ui.new("ScreenGui", {
		Name = "SendGoblins",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Ui.new("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Ui.color.bg,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})

	-- Fixed 1280x720 canvas, scaled to fit the screen.
	local root = Ui.new("Frame", {
		Name = "Canvas",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Ui.WIDTH, Ui.HEIGHT),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local scale = Ui.new("UIScale", { Parent = root })
	local function rescale()
		local viewport = gui.AbsoluteSize
		scale.Scale = math.min(viewport.X / Ui.WIDTH, viewport.Y / Ui.HEIGHT)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()

	local content = Ui.new("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})

	local toastLabel = Ui.label("", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(600, 36),
		BackgroundColor3 = Ui.color.black,
		BackgroundTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 22,
		Visible = false,
		ZIndex = 50,
		Parent = root,
	})
	local toastId = 0

	local current: { destroy: () -> (), refresh: (() -> ())? }? = nil

	local ctx: Ctx
	ctx = {
		root = content,
		profile = nil,
		party = {},
		depth = 1,
		busy = false,

		toast = function(text, color)
			toastId += 1
			local id = toastId
			toastLabel.Text = text
			toastLabel.TextColor3 = color or Ui.color.caption
			toastLabel.Visible = true
			task.delay(3, function()
				if toastId == id then
					toastLabel.Visible = false
				end
			end)
		end,

		call = function(action, payload)
			ctx.busy = true
			local response = Net.call(action, payload)
			ctx.busy = false
			if response.profile then
				ctx.profile = response.profile
			end
			if not response.ok then
				ctx.toast(response.err or "Something went wrong", Ui.color.red)
			end
			return response
		end,

		refresh = function()
			if current and current.refresh then
				current.refresh()
			end
		end,

		showBase = function()
			if current then
				current.destroy()
			end
			current = BaseScreen.mount(ctx)
		end,

		showRun = function(run, result, serverNow)
			if current then
				current.destroy()
			end
			current = RunScreen.mount(ctx, run, result, serverNow)
		end,

		showResults = function(summary, party)
			if current then
				current.destroy()
			end
			current = ResultsScreen.mount(ctx, summary, party)
		end,
	}

	local loading = Ui.title("LOADING THE DUNGEON...", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 20,
		Parent = content,
	})

	local response
	repeat
		response = ctx.call("state")
		if not response.ok then
			task.wait(2)
		end
	until response.ok
	loading:Destroy()

	if response.run and response.result then
		ctx.showRun(response.run, response.result, response.serverNow)
	else
		ctx.showBase()
	end
end

return App
