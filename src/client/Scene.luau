--!strict
-- The main security-camera picture: one goblin's current room in pixel art. Everything on it is
-- a function of (timeline, display times, now), so switching cameras or rejoining mid-run
-- always shows the right moment. No tweens: positions are interpolated every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Sim.Items)

local Art = require(script.Parent.Art)
local PixelSprite = require(script.Parent.PixelSprite)
local Ui = require(script.Parent.Ui)

local Scene = {}

export type Scene = {
	update: (goblin: any, events: { any }, times: { number }, t: number) -> (),
	destroy: () -> (),
}

local P = 4 -- screen pixels per art pixel
local W, H = 820, 430
local FLOOR = 356 -- feet line
local ENTRANCE, STAND, NEAR, OBJECT = 90, 280, 440, 590
local OFFSCREEN_LEFT, OFFSCREEN_RIGHT = -80, W + 80
local DOOR_X = { { 410 }, { 290, 530 }, { 200, 410, 620 } }

local HINT: { [string]: { text: string, color: Color3 } } = {
	quiet = { text = "...", color = Ui.color.muted },
	glint = { text = "$ $ $", color = Ui.color.gold },
	growl = { text = "GRRR!", color = Ui.color.red },
	glow = { text = "* * *", color = Color3.fromHex("8ad0ff") },
}

local SHAKERS = { hurt = true, trap = true, mimic = true, death = true, hardhat = true, starving = true }

local function color(key: string): Color3
	return Color3.fromHex(Art.palette[key])
end

-- UDim offsets are integers.
local function at(x: number, y: number): UDim2
	return UDim2.fromOffset(math.round(x), math.round(y))
end

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * math.clamp(alpha, 0, 1)
end

local function block(parent: Instance, x: number, y: number, w: number, h: number, key: string): Frame
	return Ui.new("Frame", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color(key),
		BorderSizePixel = 0,
		Parent = parent,
	})
end

local function circle(parent: Instance, x: number, y: number, size: number, c: Color3, transparency: number): Frame
	return Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = c,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
end

-- Wall, floor and torches: built once, cheap (bricks are drawn as lines, not tiles).
local function buildRoom(world: Frame): { { sprite: Frame, glow: Frame } }
	block(world, 0, 0, W, FLOOR, "3")
	local brickH, brickW = 40, 112
	for row = 0, math.ceil(FLOOR / brickH) - 1 do
		local y = row * brickH
		block(world, 0, y, W, 4, "4")
		block(world, 0, y + brickH - 4, W, 4, "2")
		local offset = if row % 2 == 0 then 0 else brickW // 2
		for x = offset - brickW, W, brickW do
			block(world, x, y, 4, brickH - 4, "2")
			-- A few darker, cracked bricks so the wall isn't a perfect grid.
			if (row * 7 + x // brickW * 3) % 5 == 0 then
				block(world, x + 4, y + 4, brickW - 4, brickH - 8, "2").BackgroundTransparency = 0.5
			end
		end
	end
	local shade = block(world, 0, FLOOR - 24, W, 24, "1")
	shade.BackgroundTransparency = 0.5

	block(world, 0, FLOOR, W, H - FLOOR, "4")
	block(world, 0, FLOOR, W, 6, "6")
	block(world, 0, FLOOR + 6, W, 4, "2")
	block(world, 0, FLOOR + 40, W, 4, "3")
	for _, x in { 70, 260, 470, 690 } do
		block(world, x, FLOOR + 10, 4, 30, "3")
		block(world, x + 100, FLOOR + 44, 4, H - FLOOR - 44, "3")
	end

	local torches = {}
	for _, x in { 220, 620 } do
		local glow = circle(world, x, 112, 260, color("F"), 0.955)
		circle(glow, 130, 130, 140, color("F"), 0.91)
		local sprite = PixelSprite.new(Art.sprites.torch, Art.palette, P)
		sprite.AnchorPoint = Vector2.new(0.5, 0)
		sprite.Position = UDim2.fromOffset(x, 80)
		sprite.Parent = world
		table.insert(torches, { sprite = sprite, glow = glow })
	end
	return torches
end

function Scene.new(parent: Instance): Scene
	local root = Ui.new("Frame", {
		Name = "Scene",
		Size = UDim2.fromOffset(W, H),
		BackgroundColor3 = color("1"),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,
	})
	local world =
		Ui.new("Frame", { Name = "World", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	local torches = buildRoom(world)
	local actors =
		Ui.new("Frame", { Name = "Actors", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = world })

	-- Overlays (not shaken): darkness at the edges, death static, big captions, scanlines.
	local dim = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.color.black,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})
	local vignette = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.color.black,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		Ui.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.18, 1),
				NumberSequenceKeypoint.new(0.82, 1),
				NumberSequenceKeypoint.new(1, 0.35),
			}),
		}),
	})
	vignette.BackgroundTransparency = 0
	local noise =
		Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = root })
	local noiseBlocks = {}
	for i = 1, 36 do
		noiseBlocks[i] = Ui.new("Frame", { BorderSizePixel = 0, Parent = noise })
	end
	local big = Ui.title("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W // 2, 150),
		Size = UDim2.fromOffset(W, 50),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 34,
		TextStrokeTransparency = 0,
		Parent = root,
	})
	for y = 0, H, 6 do
		local line = block(root, 0, y, W, 2, "1")
		line.BackgroundTransparency = 0.82
	end

	-- Speech bubble and floating numbers.
	local bubble = Ui.title("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(120, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 26,
		TextStrokeTransparency = 0,
		Parent = actors,
	})
	bubble.ZIndex = 20
	local floats = {}
	for i = 1, 4 do
		local label = Ui.title("", {
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(240, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 24,
			TextStrokeTransparency = 0,
			Parent = actors,
		})
		label.ZIndex = 20
		floats[i] = label
	end
	local hints = {}
	for i = 1, 3 do
		local label = Ui.title("", {
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(160, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 16,
			TextStrokeTransparency = 0,
			Parent = actors,
		})
		hints[i] = label
	end

	-- Sprites are built on first use and kept; every update hides the ones it didn't place.
	local cache: { [string]: Frame } = {}
	local used: { [Frame]: boolean } = {}
	local tints: { [Frame]: Color3 | false } = {}

	local function get(key: string, build: () -> Frame): Frame
		local cached = cache[key]
		if cached then
			return cached
		end
		local sprite = build()
		sprite.AnchorPoint = Vector2.new(0.5, 1)
		sprite.Visible = false
		sprite.Parent = actors
		cache[key] = sprite
		return sprite
	end

	local function art(name: string, overrides: { [string]: string }?, cacheKey: string?): Frame
		return get(cacheKey or name, function()
			return PixelSprite.new(Art.sprites[name], Art.palette, P, overrides)
		end)
	end

	local function place(sprite: Frame, x: number, y: number, frame: number?, z: number?)
		used[sprite] = true
		sprite.Position = at(x, y)
		sprite.ZIndex = z or 2
		PixelSprite.setFrame(sprite, frame or 1)
	end

	local function tint(sprite: Frame, c: Color3?)
		local current = tints[sprite] or nil
		if current ~= c then
			tints[sprite] = c or false
			PixelSprite.tint(sprite, c)
		end
	end

	local doors: { Frame } = {}
	for i = 1, 3 do
		doors[i] = get(`door{i}`, function()
			local frames = Art.sprites.door
			return PixelSprite.new({ frames[1], frames[#frames] }, Art.palette, P)
		end)
	end

	local function update(goblin: any, events: { any }, times: { number }, t: number)
		table.clear(used)
		local clock = os.clock()

		local shown = 0
		for i, shownAt in times do
			if shownAt > t then
				break
			end
			shown = i
		end

		-- Ambient: torches flicker.
		for i, torch in torches do
			PixelSprite.setFrame(torch.sprite, 1 + math.floor(clock * 8 + i) % #Art.sprites.torch)
			torch.glow.BackgroundTransparency = 0.955 + 0.015 * math.sin(clock * 9 + i * 2)
		end

		local skin = Art.goblinSkin[goblin.trait]
		local trait = goblin.trait
		local idle = art("goblin", skin, `goblin:{trait}`)
		local walk = art("goblinWalk", skin, `walk:{trait}`)
		local hurtPose = art("goblinHurt", skin, `hurt:{trait}`)
		local dead = art("goblinDead", skin, `dead:{trait}`)

		local gx, gy = ENTRANCE, FLOOR + 4
		local moving = false
		local pose: Frame? = idle
		local goblinTint: Color3? = nil
		local squash = 1
		local bubbleText, bubbleColor, bubbleX, bubbleY = "", Ui.color.text, 0, 0
		local shake = 0
		local floatList: { { text: string, color: Color3, x: number, dt: number } } = {}
		local bigText, bigColor = "", Ui.color.text
		local dimAmount = 1
		noise.Visible = false

		-- Moves the goblin from `from` to `to` over `duration`; returns the resting x.
		local function walkTo(from: number, to: number, dt: number, duration: number): number
			gx = lerp(from, to, dt / duration)
			moving = dt < duration and from ~= to
			return to
		end

		local function float(text: string, c: Color3, x: number, dt: number)
			if dt < 1.1 then
				table.insert(floatList, { text = text, color = c, x = x, dt = dt })
			end
		end

		-- Which part of the timeline are we in?
		local doorsAt = 0
		for i = shown, 1, -1 do
			if events[i].kind == "doors" then
				doorsAt = i
				break
			end
		end
		local last = events[shown]

		if last and last.kind == "doors" then
			-- Corridor: pick a door. Hints over every door; the chosen one blinks.
			local dt = t - times[shown]
			local count = #(last.hints or { "quiet" })
			local xs = DOOR_X[math.clamp(count, 1, 3)]
			local choice = last.choice or 1
			for i, x in xs do
				place(doors[i], x, FLOOR + 4, if i == choice and dt > 0.75 then 2 else 1)
				local hint = HINT[(last.hints or {})[i] or "quiet"]
				local label = hints[i]
				label.Visible = not (i == choice and dt > 0.3 and math.floor(dt * 8) % 2 == 0)
				label.Text = hint.text
				label.TextColor3 = hint.color
				label.Position = at(x, FLOOR - 150 + math.sin(clock * 4 + i) * 4)
			end
			for i = #xs + 1, 3 do
				hints[i].Visible = false
			end
			gx = 110
			if dt < 0.3 then
				bubbleText, bubbleColor = "?", Ui.color.caption
			else
				walkTo(110, xs[choice], dt - 0.3, 0.5)
			end
			if dt > 0.85 then
				pose = nil -- went through the door
			end
		else
			for i = 1, 3 do
				hints[i].Visible = false
			end
			place(doors[1], ENTRANCE - 20, FLOOR + 4, 2, 1)

			local roomIndex = if doorsAt > 0 then doorsAt + 1 else 0
			local roomEvent = events[roomIndex]
			local roomType = if roomEvent and roomEvent.kind == "room" then roomEvent.name else nil
			local entered = if roomIndex > 0 and roomIndex <= shown then times[roomIndex] else (times[1] or 0)
			local base = walkTo(ENTRANCE, STAND, t - entered, 0.6)

			-- Look ahead in this room for names (the whole timeline is already known).
			local monsterName, trapName = nil, nil
			for i = roomIndex + 1, #events do
				local e = events[i]
				if e.kind == "doors" then
					break
				elseif e.kind == "combat" or e.kind == "flee" or e.kind == "sneak" then
					monsterName = monsterName or e.name
				elseif e.kind == "trap" or e.kind == "trap_avoided" or e.kind == "hardhat" then
					trapName = trapName or e.name
				end
			end

			-- Room furniture before anything happens.
			local monster: Frame? = nil
			local monsterX, monsterFrame = OBJECT + 20, 1 + math.floor(clock * 3) % 2
			local monsterVisible = roomType == "monster" and monsterName ~= nil
			local monsterTint: Color3? = nil
			if monsterVisible then
				local spriteName = Art.monster[monsterName :: string] or "rat"
				monster = art(spriteName)
				monsterFrame = 1 + math.floor(clock * 3) % #Art.sprites[spriteName]
			end
			local chestOpen = false
			local mimicFrame = 1
			local spikesFrame = 1
			local shrineFrame = 1 + math.floor(clock * 3) % #Art.sprites.shrine
			local itemIcon: string? = nil
			local itemDt = 0
			local sleeping = false

			local start = if roomIndex > 0 then roomIndex + 1 else 1
			for i = start, shown do
				local e = events[i]
				local dt = t - times[i]
				local kind = e.kind
				local amount = e.amount or 0
				if kind == "lost" then
					bubbleText, bubbleColor = "?", Ui.color.caption
					gx = STAND + math.sin(dt * 2.5) * 140
					moving = true
				elseif kind == "loot" then
					if roomType == "treasure" then
						base = walkTo(base, NEAR, dt, 0.3)
						chestOpen = dt > 0.3
					elseif monsterVisible then
						-- The monster dies: blink, then gone.
						monsterVisible = dt < 0.5 and math.floor(dt * 12) % 2 == 0
					end
					float(`+{amount} GOLD`, Ui.color.gold, OBJECT, dt - 0.3)
				elseif kind == "item" then
					itemIcon, itemDt = e.name, dt
					local item = Items.get(e.name)
					float(if item then item.name:upper() else "ITEM!", Ui.color.caption, OBJECT, dt)
				elseif kind == "trap_avoided" then
					spikesFrame = 2
					bubbleText, bubbleColor = "!", Ui.color.caption
					if dt > 0.3 then
						base = walkTo(base, OBJECT + 120, dt - 0.3, 0.7)
						gy -= math.sin(math.clamp((dt - 0.3) / 0.7, 0, 1) * math.pi) * 60
					end
				elseif kind == "trap" or kind == "hardhat" then
					base = walkTo(base, OBJECT, dt, 0.3)
					if dt > 0.3 then
						spikesFrame = #Art.sprites.spikes
						if dt < 0.8 then
							pose = hurtPose
						end
						goblinTint = if dt < 0.45 then Ui.color.red else nil
					end
					if kind == "hardhat" then
						float("CLONK!", Ui.color.gold, OBJECT, dt - 0.3)
					else
						float(`-{amount}`, Ui.color.red, OBJECT, dt - 0.3)
					end
				elseif kind == "mimic_spotted" then
					bubbleText, bubbleColor = "!", Ui.color.caption
					base = walkTo(base, STAND - 60, dt, 0.4)
				elseif kind == "mimic" then
					base = walkTo(base, NEAR + 20, dt, 0.3)
					mimicFrame = if dt > 0.4 then 3 elseif dt > 0.3 then 2 else 1
					if dt > 0.4 and dt < 0.9 then
						pose = hurtPose
						goblinTint = if dt < 0.55 then Ui.color.red else nil
					end
					float(`-{amount}`, Ui.color.red, NEAR, dt - 0.4)
				elseif kind == "mimic_escape" then
					mimicFrame = 3
					base = walkTo(base, OFFSCREEN_LEFT, dt, 0.7)
				elseif kind == "combat" then
					base = walkTo(base, NEAR, dt, 0.3)
					bubbleText, bubbleColor = "!", Ui.color.red
				elseif kind == "hit" then
					gx = NEAR + (if dt < 0.2 then 30 * (1 - dt / 0.2) else 0)
					base = NEAR
					monsterTint = if dt < 0.12 then Ui.color.text else nil
					float(`-{amount}`, Ui.color.caption, monsterX, dt)
				elseif kind == "hurt" then
					monsterX = OBJECT + 20 - (if dt < 0.2 then 40 * (1 - dt / 0.2) else 0)
					if dt < 0.4 then
						pose = hurtPose
					end
					goblinTint = if dt < 0.15 then Ui.color.red else nil
					float(`-{amount}`, Ui.color.red, gx, dt)
				elseif kind == "flee" then
					bubbleText, bubbleColor = "!!", Ui.color.caption
					base = walkTo(base, OFFSCREEN_LEFT, dt, 0.6)
					if amount > 0 then
						float(`-{amount}`, Ui.color.red, STAND, dt)
					end
				elseif kind == "sneak" then
					sleeping = true
					goblinTint = Color3.fromHex(Art.palette["2"])
					base = walkTo(base, OFFSCREEN_RIGHT, dt, 2)
				elseif kind == "shrine" then
					base = walkTo(base, NEAR, dt, 0.3)
					shrineFrame = 1 + math.floor(clock * 10) % #Art.sprites.shrine
					goblinTint = if dt > 0.3 and dt < 0.6 then Color3.fromHex("b4f0ff") else nil
					local text = if e.name == "heal"
						then `+{amount} HP`
						elseif e.name == "feast" then `+{amount} FOOD`
						else "BLESSED"
					float(text, Color3.fromHex("8ad0ff"), NEAR, dt - 0.3)
				elseif kind == "starving" then
					float(`HUNGRY -{amount}`, Ui.color.red, gx, dt)
					goblinTint = if dt < 0.15 then Ui.color.red else nil
				elseif kind == "death" then
					pose = dead
					goblinTint = nil
					local trap = e.cause == "trap" and e.name or nil
					if trap == "crusher" or trap == "boulder" then
						squash = 0.45
					elseif trap == "pit" then
						gy += math.min(dt, 1) * 400
					end
					if dt > 1.4 then
						place(art("tombstone"), gx, FLOOR + 4, 1, 3)
						pose = nil
						dimAmount = 0.45
						bigText = if math.floor(clock * 2) % 2 == 0 then "SIGNAL LOST" else ""
						bigColor = Ui.color.red
					end
					noise.Visible = dt > 0.9 and dt < 1.6
				elseif kind == "return" then
					base = walkTo(base, OFFSCREEN_RIGHT, dt, 1.2)
					if dt > 1.2 then
						bigText, bigColor = "MADE IT OUT", Ui.color.green
					end
				elseif kind == "levelup" then
					float("LEVEL UP!", Ui.color.gold, W // 2, dt)
				end
				if SHAKERS[kind] and dt < 0.3 then
					shake = 5
				end
			end

			-- Furniture after the events had their say.
			if roomType == "treasure" then
				place(art(if chestOpen then "chestOpen" else "chest"), OBJECT, FLOOR + 4)
				if itemIcon and Art.sprites[itemIcon] and itemDt < 1.5 then
					place(art(itemIcon), OBJECT, FLOOR - 90 - itemDt * 30, 1, 6)
				end
			elseif roomType == "mimic" then
				place(art("mimic"), OBJECT, FLOOR + 4, mimicFrame)
			elseif roomType == "trap" then
				place(art("spikes"), OBJECT, FLOOR + 8, spikesFrame, 1)
			elseif roomType == "shrine" then
				place(art("shrine"), OBJECT, FLOOR + 4, shrineFrame)
			end
			if monster and monsterVisible then
				place(monster, monsterX, FLOOR + 4, if sleeping then 1 else monsterFrame, 3)
				tint(monster, monsterTint)
				if sleeping then
					bubbleText, bubbleColor = "Z z", Ui.color.muted
					bubbleX, bubbleY = monsterX + 30, FLOOR - 120 - math.sin(clock * 2) * 6
				end
			end
		end

		-- The goblin.
		if pose then
			if pose == idle and moving then
				pose = walk
			end
			local frames = #Art.sprites[if pose == walk
				then "goblinWalk"
				elseif pose == dead then "goblinDead"
				elseif pose == hurtPose then "goblinHurt"
				else "goblin"]
			local frame = if pose == walk
				then 1 + math.floor(clock * 10) % frames
				elseif pose == idle then 1 + math.floor(clock * 2) % frames
				elseif pose == dead then frames
				else 1
			place(pose, gx, gy, frame, 4)
			pose.Size = at(24 * P, 24 * P * squash)
			tint(pose, goblinTint)
		end

		-- Labels.
		bubble.Visible = bubbleText ~= ""
		bubble.Text = bubbleText
		bubble.TextColor3 = bubbleColor
		if bubbleX == 0 then
			bubbleX, bubbleY = gx, gy - 100
		end
		bubble.Position = at(bubbleX, bubbleY + math.sin(clock * 6) * 3)
		for i, label in floats do
			local entry = floatList[#floatList - i + 1]
			label.Visible = entry ~= nil and entry.dt >= 0
			if entry then
				label.Text = entry.text
				label.TextColor3 = entry.color
				label.TextTransparency = math.max(0, entry.dt - 0.5) * 2
				label.TextStrokeTransparency = label.TextTransparency
				label.Position = at(entry.x, FLOOR - 104 - entry.dt * 50 - (i - 1) * 26)
			end
		end
		big.Text = bigText
		big.TextColor3 = bigColor
		dim.BackgroundTransparency = dimAmount
		world.Position = if shake > 0
			then UDim2.fromOffset(math.random(-shake, shake), math.random(-shake, shake))
			else UDim2.new()
		if noise.Visible then
			for _, b in noiseBlocks do
				local gray = math.random(30, 200) / 255
				b.BackgroundColor3 = Color3.new(gray, gray, gray)
				b.Position = UDim2.fromOffset(math.random(0, W), math.random(0, H))
				b.Size = UDim2.fromOffset(math.random(20, 160), math.random(2, 10))
			end
		end

		for _, sprite in cache do
			sprite.Visible = used[sprite] == true
		end
	end

	return {
		update = update,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Scene
