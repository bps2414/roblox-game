--!strict
-- Pixel art data tests. Run: lune run tests/art.spec

local Art = require("../src/client/Art")
local Items = require("../src/shared/Sim/Items")
local Config = require("../src/shared/Sim/Config")
local PixelSprite = require("../src/client/PixelSprite")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(`  ✓ {name}`)
	else
		failed += 1
		print(`  ✗ {name}\n      {err}`)
	end
end

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

print("Art")
test("every frame is a rectangle of palette keys", function()
	for name, frames in Art.sprites do
		local width, height = #frames[1][1], #frames[1]
		for f, rows in frames do
			check(#rows == height, `{name} frame {f}: {#rows} rows, expected {height}`)
			for y, row in rows do
				check(#row == width, `{name} frame {f} row {y}: width {#row}, expected {width}`)
				for x = 1, #row do
					local key = string.sub(row, x, x)
					check(key == "." or Art.palette[key], `{name} frame {f} row {y}: unknown color "{key}"`)
				end
			end
		end
	end
end)

test("palettes are 6-digit hex", function()
	local function hex(value: string, where: string)
		check(string.match(value, "^%x%x%x%x%x%x$"), `{where}: bad hex {value}`)
	end
	for key, value in Art.palette do
		hex(value, key)
	end
	for trait, skin in Art.goblinSkin do
		for key, value in skin do
			hex(value, `{trait}.{key}`)
		end
	end
end)

test("every item, monster and trait has art", function()
	for _, item in Items.list do
		check(Art.sprites[item.id], `no icon for {item.id}`)
	end
	for _, monster in Config.MONSTERS do
		check(Art.sprites[Art.monster[monster.name]], `no sprite for {monster.name}`)
	end
	for _, trait in Config.TRAITS do
		check(Art.goblinSkin[trait], `no skin for {trait}`)
	end
end)

test("runs merge same colors and skip transparency", function()
	local runs = PixelSprite.runs({ "..kkGk", "GG...." })
	check(#runs == 4, `expected 4 runs, got {#runs}`)
	check(runs[1].x == 3 and runs[1].length == 2 and runs[1].key == "k", "first run")
	check(runs[2].x == 5 and runs[2].length == 1 and runs[2].key == "G", "second run")
	check(runs[4].y == 2 and runs[4].x == 1 and runs[4].length == 2, "second row")
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
