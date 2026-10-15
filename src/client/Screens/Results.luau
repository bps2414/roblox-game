--!strict
-- After collecting: who came back, who didn't, what they brought. Survivors stand on the
-- ground, the rest get a tombstone with the cause of death.

local RunService = game:GetService("RunService")

local Art = require(script.Parent.Parent.Art)
local PixelSprite = require(script.Parent.Parent.PixelSprite)
local Sfx = require(script.Parent.Parent.Sfx)
local Types = require(script.Parent.Parent.Types)
local Ui = require(script.Parent.Parent.Ui)

local Results = {}

local CAUSE_TEXT: { [string]: string } = {
	trap = "trap:",
	mimic = "eaten by a mimic",
	monster = "killed by",
	starvation = "starved",
}

function Results.mount(ctx: Types.Ctx, summary: any, party: { any }): Types.Screen
	local result = summary.result
	local byId: { [string]: any } = {}
	for _, goblin in party do
		byId[goblin.id] = goblin
	end

	local frame = Ui.new("Frame", {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = ctx.root,
	})

	local panel = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 620),
		BorderColor3 = Ui.color.borderLight,
		Parent = frame,
	}, { Ui.padding(18, 24) })

	local everyoneDied = result.survivors == 0
	Sfx.play(if everyoneDied then "fail" else "fanfare")
	Ui.title(`{result.survivors}/{#result.goblins} CAME BACK`, {
		Size = UDim2.new(1, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 24,
		TextColor3 = if everyoneDied then Ui.color.red else Ui.color.green,
		Parent = panel,
	})
	local lootLabel = Ui.label("", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 24,
		Parent = panel,
	})

	local banners = {}
	if summary.unlockedDepth then
		table.insert(banners, Ui.paint(`⭐ FLOOR {summary.unlockedDepth} UNLOCKED!`, Ui.color.gold))
	end
	if summary.pityGoblin then
		table.insert(
			banners,
			Ui.paint(`A stray goblin named {summary.pityGoblin} wanders into your empty barracks.`, Ui.color.caption)
		)
	end
	if #banners > 0 then
		Ui.label(table.concat(banners, "   "), {
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 20,
			Parent = panel,
		})
	end

	local grid = Ui.scroll({
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 1, -170),
		Parent = panel,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(160, 200),
			CellPadding = UDim2.fromOffset(12, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		Ui.padding(3),
	})

	for index, goblin in result.goblins do
		local info = byId[goblin.id]
		local name = if info then info.name else goblin.id
		local cell = Ui.new("Frame", {
			BackgroundColor3 = Color3.fromHex(Art.palette["2"]),
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = grid,
		}, {
			-- Ground under the sprite.
			Ui.new("Frame", {
				Position = UDim2.fromOffset(0, 82),
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundColor3 = Color3.fromHex(Art.palette["4"]),
				BorderSizePixel = 0,
			}),
			Ui.label(Ui.paint(name, if goblin.survived then Ui.color.green else Ui.color.muted), {
				Font = Ui.font.pixel,
				TextSize = 10,
				Position = UDim2.fromOffset(0, 96),
				Size = UDim2.new(1, 0, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
		})
		Ui.stroke(if goblin.survived then Ui.color.green else Ui.color.border, 2).Parent = cell

		local sprite = if goblin.survived
			then PixelSprite.new({ Art.sprites.goblin[1] }, Art.palette, 3, info and Art.goblinSkin[info.trait])
			else PixelSprite.new(Art.sprites.tombstone, Art.palette, 3)
		sprite.AnchorPoint = Vector2.new(0.5, 1)
		sprite.Position = UDim2.new(0.5, 0, 0, 86)
		sprite.Parent = cell

		local outcome
		if goblin.survived then
			local level = summary.levelUps[goblin.id]
			outcome = Ui.paint(`MADE IT OUT\n+{goblin.xp} XP`, Ui.color.green)
				.. (if level then Ui.paint(`\nLEVEL {level}!`, Ui.color.gold) else "")
		else
			local cause = CAUSE_TEXT[goblin.cause] or goblin.cause or "died"
			local detail = if goblin.causeName and goblin.cause ~= "mimic" then ` {goblin.causeName}` else ""
			outcome = Ui.paint(`{cause}{detail}\nroom {goblin.rooms}`, Ui.color.red)
		end
		Ui.label(outcome, {
			Position = UDim2.fromOffset(6, 116),
			Size = UDim2.new(1, -12, 0, 50),
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = cell,
		})
		Ui.label(Ui.paint(`{goblin.gold} GOLD`, Ui.color.gold), {
			Position = UDim2.new(0, 0, 1, -28),
			Size = UDim2.new(1, -8, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = 16,
			Parent = cell,
		})
		-- Items found (they come home even when the goblin doesn't).
		for i, itemId in goblin.items do
			if Art.sprites[itemId] and i <= 3 then
				local icon = PixelSprite.new({ Art.sprites[itemId][1] }, Art.palette, 1.5)
				icon.Position = UDim2.new(0, 6 + (i - 1) * 28, 1, -30)
				icon.Parent = cell
			end
		end
	end

	Ui.button("CONTINUE", function()
		ctx.showBase()
	end, {
		BackgroundColor3 = Ui.color.darkGold,
		TextColor3 = Ui.color.gold,
		TextSize = 16,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(320, 48),
		Parent = panel,
	})

	local shownAt = os.clock()
	local function showLoot()
		local gold = math.floor(result.totalGold * math.clamp((os.clock() - shownAt) / 1.2, 0, 1))
		lootLabel.Text = `FLOOR {result.depth}  ·  LOOT {Ui.paint(`{gold} GOLD`, Ui.color.gold)}`
	end
	showLoot()
	local counter = RunService.Heartbeat:Connect(showLoot)

	return {
		destroy = function()
			counter:Disconnect()
			frame:Destroy()
		end,
	}
end

return Results
