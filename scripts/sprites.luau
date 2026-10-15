--!strict
-- Renders every sprite in Art.luau (all frames side by side) to one PNG sheet.
-- Usage: lune run scripts/sprites -- [out=build/sprites.png] [scale=4]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Art = require("../src/client/Art")
local PixelSprite = require("../src/client/PixelSprite")

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local out = args[1] or "build/sprites.png"
local scale = tonumber(args[2]) or 4
local GAP, MAX_WIDTH = 3, 220 -- in art pixels
local BACKGROUND = "302744"

-- Shelf-pack the sprites (name order) into rows.
local names = {}
for name in Art.sprites do
	table.insert(names, name)
end
table.sort(names)

local placed = {}
local x, y, shelf, width = GAP, GAP, 0, 0
for _, name in names do
	local frames = Art.sprites[name]
	local w = #frames * (#frames[1][1] + GAP) - GAP
	local h = #frames[1]
	if x + w + GAP > MAX_WIDTH then
		x, y, shelf = GAP, y + shelf + GAP, 0
	end
	table.insert(placed, { name = name, x = x, y = y })
	local most = 0 -- Frames per frame in Roblox (one per same-color run)
	for _, rows in frames do
		most = math.max(most, #PixelSprite.runs(rows))
	end
	print(`{name}: ({x}, {y}) {#frames[1][1]}x{h}, {#frames} frames, {most} runs`)
	x += w + GAP
	shelf = math.max(shelf, h)
	width = math.max(width, x)
end
local height = y + shelf + GAP

local W, H = width * scale, height * scale
local stride = 1 + W * 3
local pixels = buffer.create(stride * H)

local function rgb(hex: string): (number, number, number)
	return tonumber(string.sub(hex, 1, 2), 16) :: number,
		tonumber(string.sub(hex, 3, 4), 16) :: number,
		tonumber(string.sub(hex, 5, 6), 16) :: number
end

local function fill(px: number, py: number, hex: string)
	local r, g, b = rgb(hex)
	for sy = py * scale, py * scale + scale - 1 do
		for sx = px * scale, px * scale + scale - 1 do
			local at = sy * stride + 1 + sx * 3
			buffer.writeu8(pixels, at, r)
			buffer.writeu8(pixels, at + 1, g)
			buffer.writeu8(pixels, at + 2, b)
		end
	end
end

for py = 0, height - 1 do
	for px = 0, width - 1 do
		fill(px, py, BACKGROUND)
	end
end
for _, place in placed do
	local frames = Art.sprites[place.name]
	local frameWidth = #frames[1][1]
	for f, rows in frames do
		local ox = place.x + (f - 1) * (frameWidth + GAP)
		for ry, row in rows do
			for rx = 1, #row do
				local key = string.sub(row, rx, rx)
				if key ~= "." then
					fill(ox + rx - 1, place.y + ry - 1, Art.palette[key])
				end
			end
		end
	end
end

-- Minimal PNG writer: RGB, filter 0 on every row (the leading zero byte), zlib via Lune.
local crcTable = {}
for n = 0, 255 do
	local c = n
	for _ = 1, 8 do
		c = if bit32.band(c, 1) == 1 then bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) else bit32.rshift(c, 1)
	end
	crcTable[n] = c
end

local function crc32(data: string): number
	local c = 0xFFFFFFFF
	for i = 1, #data do
		c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, string.byte(data, i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function chunk(kind: string, data: string): string
	return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end

local png = "\137PNG\r\n\26\n"
	.. chunk("IHDR", string.pack(">I4I4BBBBB", W, H, 8, 2, 0, 0, 0))
	.. chunk("IDAT", serde.compress("zlib", buffer.tostring(pixels)))
	.. chunk("IEND", "")
fs.writeFile(out, png)
print(`wrote {out} ({W}x{H})`)
