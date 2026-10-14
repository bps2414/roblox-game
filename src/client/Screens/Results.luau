--!strict
-- After collecting: who came back, who didn't, what they brought.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Sim.Items)

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
	local names: { [string]: string } = {}
	for _, goblin in party do
		names[goblin.id] = goblin.name
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
	Ui.title(`{result.survivors}/{#result.goblins} CAME BACK`, {
		Size = UDim2.new(1, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 24,
		TextColor3 = if everyoneDied then Ui.color.red else Ui.color.green,
		Parent = panel,
	})
	Ui.label(`FLOOR {result.depth}  ·  LOOT {Ui.paint(`{result.totalGold} GOLD`, Ui.color.gold)}`, {
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

	local list = Ui.scroll({
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 1, -170),
		Parent = panel,
	}, { Ui.list(nil, 6) })

	for index, goblin in result.goblins do
		local name = names[goblin.id] or goblin.id
		local outcome
		if goblin.survived then
			local level = summary.levelUps[goblin.id]
			outcome = Ui.paint(`RETURNED  +{goblin.xp} XP`, Ui.color.green)
				.. (if level then Ui.paint(`  ⭐ LEVEL {level}!`, Ui.color.gold) else "")
		else
			local cause = CAUSE_TEXT[goblin.cause] or goblin.cause or "died"
			local detail = if goblin.causeName and goblin.cause ~= "mimic" then ` {goblin.causeName}` else ""
			outcome = Ui.paint(`💀 {cause}{detail}  (room {goblin.rooms})`, Ui.color.red)
		end

		local found = {}
		for _, itemId in goblin.items do
			local item = Items.get(itemId)
			table.insert(found, if item then item.name else itemId)
		end

		local row = Ui.new("Frame", {
			Size = UDim2.new(1, -10, 0, if #found > 0 then 52 else 32),
			BackgroundColor3 = if goblin.survived then Ui.color.panelLight else Ui.color.darkRed,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = list,
		}, {
			Ui.padding(4, 10),
			Ui.label(Ui.paint(name, Ui.color.green), { Size = UDim2.fromOffset(200, 24) }),
			Ui.label(outcome, { Position = UDim2.fromOffset(200, 0), Size = UDim2.fromOffset(480, 24) }),
			Ui.label(Ui.paint(`🪙 {goblin.gold}`, Ui.color.gold), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(120, 24),
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		})
		if #found > 0 then
			Ui.label(`Found: {table.concat(found, ", ")}`, {
				Position = UDim2.fromOffset(200, 22),
				Size = UDim2.fromOffset(560, 22),
				TextSize = 17,
				TextColor3 = Ui.color.caption,
				Parent = row,
			})
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

	return {
		destroy = function()
			frame:Destroy()
		end,
	}
end

return Results
