--!strict
-- Home base: barracks (roster + equipment), tavern, shop, floor picker and SEND.
-- Rebuilt from the profile after every action (it's small enough).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sim = ReplicatedStorage.Shared.Sim
local Config = require(Sim.Config)
local Goblin = require(Sim.Goblin)
local Items = require(Sim.Items)
local Profile = require(Sim.Profile)

local Types = require(script.Parent.Parent.Types)
local Ui = require(script.Parent.Parent.Ui)

local Base = {}

local SLOTS = { "weapon", "armor", "utility" }

local function itemName(id: string?): string
	local item = Items.get(id)
	return if item then item.name else "—"
end

function Base.mount(ctx: Types.Ctx): Types.Screen
	local frame = Ui.new("Frame", {
		Name = "Base",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = ctx.root,
	})

	local equipping: { goblinId: string, slot: string }? = nil
	local rosterScroll = Vector2.zero
	local shopScroll = Vector2.zero
	local render: () -> ()

	local function act(action: string, payload: { [string]: any }?)
		if ctx.busy then
			return
		end
		ctx.call(action, payload)
		render()
	end

	local function partyIds(): { string }
		local ids = {}
		for _, goblin in ctx.profile.goblins do
			if ctx.party[goblin.id] then
				table.insert(ids, goblin.id)
			end
		end
		return ids
	end

	-- Drops goblins that are gone and adds newly hired ones while there is room.
	local function syncParty()
		local exists = {}
		for _, goblin in ctx.profile.goblins do
			exists[goblin.id] = true
		end
		for id in ctx.party do
			if not exists[id] then
				ctx.party[id] = nil
			end
		end
		for _, goblin in ctx.profile.goblins do
			if not ctx.known[goblin.id] then
				ctx.known[goblin.id] = true
				if #partyIds() < Config.MAX_PARTY then
					ctx.party[goblin.id] = true
				end
			end
		end
		ctx.depth = math.clamp(ctx.depth, 1, ctx.profile.unlockedDepth)
	end

	local function topBar(profile: any)
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
			Ui.label(
				`GOLD {Ui.paint(tostring(profile.gold), Ui.color.gold)}    DEEPEST FLOOR {Ui.paint(
					tostring(profile.unlockedDepth),
					Ui.color.gold
				)}    BARRACKS {Ui.paint(`{#profile.goblins}/{Config.MAX_GOBLINS}`, Ui.color.gold)}`,
				{
					Position = UDim2.fromOffset(420, 0),
					Size = UDim2.fromOffset(840, 56),
					TextXAlignment = Enum.TextXAlignment.Right,
					TextSize = 22,
				}
			),
		})
	end

	local function goblinCard(goblin: any, parent: Instance)
		local stats = Goblin.stats(goblin)
		local inParty = ctx.party[goblin.id] == true
		local nextXp = Config.xpForLevel(goblin.level + 1)
		local prevXp = Config.xpForLevel(goblin.level)

		local card = Ui.panel({
			BackgroundColor3 = if inParty then Ui.color.panelLight else Ui.color.panel,
			BorderColor3 = if inParty then Ui.color.green else Ui.color.border,
			Parent = parent,
		}, {
			Ui.padding(8, 10),
			Ui.label(goblin.name, {
				Font = Ui.font.pixel,
				TextSize = 13,
				TextColor3 = Ui.color.green,
				Size = UDim2.fromOffset(180, 20),
			}),
			Ui.label(goblin.trait:upper(), {
				Font = Ui.font.pixel,
				TextSize = 9,
				Position = UDim2.fromOffset(186, 0),
				Size = UDim2.fromOffset(80, 20),
				BackgroundTransparency = 0,
				BackgroundColor3 = Ui.color.purple,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
			Ui.label(`LV {goblin.level}`, {
				Position = UDim2.fromOffset(276, 0),
				Size = UDim2.fromOffset(70, 20),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = Ui.color.gold,
			}),
			Ui.bar((goblin.xp - prevXp) / math.max(1, nextXp - prevXp), Ui.color.gold, {
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.new(1, 0, 0, 6),
			}),
			Ui.label(
				`HP {stats.maxHp} FOOD {stats.food} PER {stats.perception} LCK {stats.luck} ATK {stats.attack} DEF {stats.defense}`,
				{ Position = UDim2.fromOffset(0, 34), TextSize = 16 }
			),
			Ui.label(Goblin.TRAIT_INFO[goblin.trait] or "", {
				Position = UDim2.fromOffset(0, 54),
				TextSize = 15,
				TextColor3 = Ui.color.muted,
			}),
		})

		for index, slot in SLOTS do
			Ui.button(itemName((goblin.equipment :: any)[slot]), function()
				equipping = { goblinId = goblin.id, slot = slot }
				render()
			end, {
				Font = Ui.font.body,
				TextSize = 15,
				Position = UDim2.fromOffset((index - 1) * 116, 80),
				Size = UDim2.fromOffset(110, 24),
				Parent = card,
			})
		end

		Ui.button(if inParty then "IN PARTY ✓" else "+ PARTY", function()
			if inParty then
				ctx.party[goblin.id] = nil
			elseif #partyIds() < Config.MAX_PARTY then
				ctx.party[goblin.id] = true
			else
				ctx.toast(`Max {Config.MAX_PARTY} goblins per run`)
			end
			render()
		end, {
			BackgroundColor3 = if inParty then Ui.color.darkGreen else Ui.color.borderLight,
			Position = UDim2.fromOffset(0, 112),
			Size = UDim2.fromOffset(170, 26),
			Parent = card,
		})

		Ui.button(`SELL {Goblin.sellValue(goblin)}G`, function()
			act("sellGoblin", { id = goblin.id })
		end, {
			BackgroundColor3 = Ui.color.darkRed,
			Position = UDim2.fromOffset(178, 112),
			Size = UDim2.fromOffset(170, 26),
			Parent = card,
		})
	end

	local function barracks(profile: any)
		local panel = Ui.panel({
			Position = UDim2.fromOffset(18, 72),
			Size = UDim2.fromOffset(780, 548),
			Parent = frame,
		}, {
			Ui.padding(10),
			Ui.title("BARRACKS  ·  CLICK GEAR TO EQUIP", { Size = UDim2.new(1, 0, 0, 20) }),
		})
		local scroll = Ui.scroll({
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 1, -28),
			Parent = panel,
		}, {
			Ui.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(372, 150),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Ui.padding(3),
		})
		for _, goblin in profile.goblins do
			goblinCard(goblin, scroll)
		end
		if #profile.goblins == 0 then
			Ui.label("No goblins. Hire some at the tavern!", { TextColor3 = Ui.color.muted, Parent = scroll })
		end
		scroll.CanvasPosition = rosterScroll
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			rosterScroll = scroll.CanvasPosition
		end)
	end

	local function tavern(profile: any)
		local panel = Ui.panel({
			Position = UDim2.fromOffset(816, 72),
			Size = UDim2.fromOffset(446, 250),
			Parent = frame,
		}, {
			Ui.padding(10),
			Ui.title("TAVERN  ·  RECRUITS", { Size = UDim2.new(1, 0, 0, 20) }),
		})
		local list = Ui.new("Frame", {
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 1, -28),
			BackgroundTransparency = 1,
			Parent = panel,
		}, { Ui.list(nil, 8) })
		for index, offer in profile.tavern do
			local stats = Goblin.stats(offer)
			local cost = Profile.recruitCost(offer)
			Ui.new("Frame", {
				Size = UDim2.new(1, 0, 0, 58),
				BackgroundColor3 = Ui.color.panelLight,
				BorderSizePixel = 0,
				LayoutOrder = index,
				Parent = list,
			}, {
				Ui.padding(6, 8),
				Ui.label(`{Ui.paint(offer.name, Ui.color.green)}  {Ui.paint(offer.trait, Ui.color.muted)}`, {
					Size = UDim2.new(1, -110, 0, 22),
				}),
				Ui.label(`HP {stats.maxHp}  FOOD {stats.food}  PER {stats.perception}  LCK {stats.luck}`, {
					Position = UDim2.fromOffset(0, 24),
					Size = UDim2.new(1, -110, 0, 22),
					TextSize = 17,
				}),
				Ui.button(`HIRE {cost}G`, function()
					act("recruit", { index = index })
				end, {
					Enabled = profile.gold >= cost and #profile.goblins < Config.MAX_GOBLINS,
					BackgroundColor3 = Ui.color.darkGreen,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.fromOffset(100, 34),
				}),
			})
		end
	end

	local function shop(profile: any)
		local panel = Ui.panel({
			Position = UDim2.fromOffset(816, 338),
			Size = UDim2.fromOffset(446, 282),
			Parent = frame,
		}, {
			Ui.padding(10),
			Ui.title("SHOP", { Size = UDim2.new(1, 0, 0, 20) }),
		})
		local scroll = Ui.scroll({
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 1, -28),
			Parent = panel,
		}, { Ui.list(nil, 6) })
		for index, item in Items.list do
			if item.price > 0 then
				local owned = profile.inventory[item.id] or 0
				Ui.new("Frame", {
					Size = UDim2.new(1, -10, 0, 46),
					BackgroundColor3 = Ui.color.panelLight,
					BorderSizePixel = 0,
					LayoutOrder = index,
					Parent = scroll,
				}, {
					Ui.padding(4, 8),
					Ui.label(
						`{item.name}{if owned > 0 then Ui.paint(` x{owned}`, Ui.color.gold) else ""}`,
						{ Size = UDim2.new(1, -184, 0, 20) }
					),
					Ui.label(Items.describe(item), {
						Position = UDim2.fromOffset(0, 20),
						Size = UDim2.new(1, -184, 0, 18),
						TextSize = 15,
						TextColor3 = Ui.color.muted,
					}),
					Ui.button(`BUY {item.price}`, function()
						act("buyItem", { id = item.id })
					end, {
						Enabled = profile.gold >= item.price,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -90, 0.5, 0),
						Size = UDim2.fromOffset(86, 30),
						TextSize = 9,
					}),
					Ui.button(`SELL {math.floor(item.price * Config.ITEM_SELL_FRACTION)}`, function()
						act("sellItem", { id = item.id })
					end, {
						Enabled = owned > 0,
						BackgroundColor3 = Ui.color.darkRed,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, 0, 0.5, 0),
						Size = UDim2.fromOffset(86, 30),
						TextSize = 9,
					}),
				})
			end
		end
		scroll.CanvasPosition = shopScroll
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			shopScroll = scroll.CanvasPosition
		end)
	end

	local function sendBar(profile: any)
		local ids = partyIds()
		local bar = Ui.panel({
			Position = UDim2.fromOffset(18, 636),
			Size = UDim2.fromOffset(1244, 68),
			Parent = frame,
		}, { Ui.padding(10, 14) })

		Ui.button("<", function()
			ctx.depth = math.max(1, ctx.depth - 1)
			render()
		end, { Enabled = ctx.depth > 1, Size = UDim2.fromOffset(44, 44), Parent = bar })
		Ui.title(`FLOOR {ctx.depth}`, {
			Position = UDim2.fromOffset(52, 0),
			Size = UDim2.fromOffset(150, 44),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 18,
			TextColor3 = Ui.color.gold,
			Parent = bar,
		})
		Ui.button(">", function()
			ctx.depth = math.min(profile.unlockedDepth, ctx.depth + 1)
			render()
		end, {
			Enabled = ctx.depth < profile.unlockedDepth,
			Position = UDim2.fromOffset(208, 0),
			Size = UDim2.fromOffset(44, 44),
			Parent = bar,
		})
		Ui.label(
			`{Config.floorLength(ctx.depth)} rooms deep.  Deeper = richer and deadlier.  Bring a goblin back to unlock the next floor.`,
			{
				Position = UDim2.fromOffset(268, 0),
				Size = UDim2.fromOffset(620, 44),
				TextWrapped = true,
				TextSize = 17,
				TextColor3 = Ui.color.muted,
				Parent = bar,
			}
		)
		Ui.button(`SEND {#ids} GOBLIN{if #ids == 1 then "" else "S"}`, function()
			if ctx.busy then
				return
			end
			local response = ctx.call("send", { ids = ids, depth = ctx.depth })
			if response.ok then
				ctx.showRun(response.run, response.result, response.serverNow)
			else
				render()
			end
		end, {
			Enabled = #ids > 0,
			BackgroundColor3 = Ui.color.darkGold,
			TextColor3 = Ui.color.gold,
			TextSize = 16,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(320, 44),
			Parent = bar,
		})
	end

	local function equipPopup(profile: any)
		local target = equipping
		if not target then
			return
		end
		local goblin = Profile.findGoblin(profile, target.goblinId)
		if not goblin then
			equipping = nil
			return
		end

		local shade = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Ui.color.black,
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = frame,
			Activated = function()
				equipping = nil
				render()
			end,
		})
		local popup = Ui.panel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(460, 380),
			BorderColor3 = Ui.color.borderLight,
			Active = true, -- swallow clicks so they don't close the popup
			ZIndex = 11,
			Parent = shade,
		}, {
			Ui.padding(14),
			Ui.title(`{goblin.name:upper()} · {target.slot:upper()}`, {
				Size = UDim2.new(1, 0, 0, 24),
				TextColor3 = Ui.color.green,
				ZIndex = 12,
			}),
		})
		local list = Ui.scroll({
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 1, -34),
			ZIndex = 12,
			Parent = popup,
		}, { Ui.list(nil, 6) })

		local function option(label: string, detail: string, itemId: string?, order: number)
			local equipped = (goblin.equipment :: any)[target.slot] == itemId
			local button = Ui.button(`{label}   {detail}{if equipped then "  (equipped)" else ""}`, function()
				equipping = nil
				act("equip", { goblinId = goblin.id, slot = target.slot, itemId = itemId })
			end, {
				Font = Ui.font.body,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = if equipped then Ui.color.darkGreen else Ui.color.borderLight,
				Size = UDim2.new(1, -10, 0, 38),
				LayoutOrder = order,
				ZIndex = 13,
				Parent = list,
			})
			Ui.padding(0, 12).Parent = button
		end

		option(if target.slot == "utility" then "Nothing" else "Basic", "free", nil, 0)
		for index, item in Items.list do
			local owned = profile.inventory[item.id] or 0
			if item.slot == target.slot and item.price > 0 and owned > 0 then
				option(`{item.name} x{owned}`, Items.describe(item), item.id, index)
			end
		end
		Ui.label("Buy more gear in the shop.", {
			TextColor3 = Ui.color.muted,
			TextSize = 16,
			LayoutOrder = 1000,
			ZIndex = 13,
			Parent = list,
		})
	end

	render = function()
		frame:ClearAllChildren()
		local profile = ctx.profile
		syncParty()
		topBar(profile)
		barracks(profile)
		tavern(profile)
		shop(profile)
		sendBar(profile)
		equipPopup(profile)
	end

	render()

	return {
		destroy = function()
			frame:Destroy()
		end,
		refresh = render,
	}
end

return Base
