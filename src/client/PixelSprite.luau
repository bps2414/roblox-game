--!strict
-- Pixel-art sprites built from Frames (no uploaded images). A sprite is a list of frames,
-- each a list of equal-length rows; every character is a palette key and "." is transparent.
-- Each horizontal run of one color becomes one Frame, positioned in Scale so the whole sprite
-- can be resized or tweened (squash, flatten) by changing the outer Size.

local PixelSprite = {}

export type Sprite = { { string } }
export type Palette = { [string]: string } -- key -> hex color
export type Run = { x: number, y: number, length: number, key: string }

-- Splits rows into same-color runs, skipping transparent pixels. Pure (used by tests).
function PixelSprite.runs(rows: { string }): { Run }
	local runs = {}
	for y, row in rows do
		local x = 1
		while x <= #row do
			local key = string.sub(row, x, x)
			local length = 1
			while string.sub(row, x + length, x + length) == key do
				length += 1
			end
			if key ~= "." then
				table.insert(runs, { x = x, y = y, length = length, key = key })
			end
			x += length
		end
	end
	return runs
end

-- Builds the sprite at `pixel` screen pixels per art pixel. Frames are children "1", "2", ...;
-- only the first is visible. `overrides` replaces palette colors (e.g. goblin skin per trait).
function PixelSprite.new(sprite: Sprite, palette: Palette, pixel: number, overrides: Palette?): Frame
	local width, height = #sprite[1][1], #sprite[1]
	local root = Instance.new("Frame")
	root.Name = "Sprite"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(width * pixel, height * pixel)
	for index, rows in sprite do
		local frame = Instance.new("Frame")
		frame.Name = tostring(index)
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.Visible = index == 1
		for _, run in PixelSprite.runs(rows) do
			local hex = (overrides and overrides[run.key]) or palette[run.key]
			local color = Color3.fromHex(hex)
			local block = Instance.new("Frame")
			block.BorderSizePixel = 0
			block.BackgroundColor3 = color
			block.Position = UDim2.fromScale((run.x - 1) / width, (run.y - 1) / height)
			block.Size = UDim2.fromScale(run.length / width, 1 / height)
			block:SetAttribute("Color", color)
			block.Parent = frame
		end
		frame.Parent = root
	end
	return root
end

function PixelSprite.setFrame(root: Instance, index: number)
	for _, child in root:GetChildren() do
		if child:IsA("Frame") then
			child.Visible = child.Name == tostring(index)
		end
	end
end

-- Paints every pixel one color (hit flash, silhouette); nil restores the original colors.
function PixelSprite.tint(root: Instance, color: Color3?)
	for _, block in root:GetDescendants() do
		local original = block:GetAttribute("Color")
		if original then
			(block :: Frame).BackgroundColor3 = color or original :: Color3
		end
	end
end

return PixelSprite
