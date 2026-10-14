--!strict
-- Deterministic xorshift32 PRNG. Same seed => same sequence on server, client and Lune,
-- which is what lets us simulate once and replay anywhere.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number): Rng
	local state = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if state == 0 then
		state = 0x9E3779B9
	end
	local self = setmetatable({ state = state }, Rng)
	-- Warm up so nearby seeds diverge quickly.
	for _ = 1, 8 do
		self:nextU32()
	end
	return self
end

function Rng.nextU32(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Float in [0, 1).
function Rng.float(self: Rng): number
	return self:nextU32() / 4294967296
end

-- Integer in [min, max].
function Rng.int(self: Rng, min: number, max: number): number
	return min + math.floor(self:float() * (max - min + 1))
end

-- Float in [min, max).
function Rng.range(self: Rng, min: number, max: number): number
	return min + self:float() * (max - min)
end

-- True with probability p (0..1).
function Rng.chance(self: Rng, p: number): boolean
	return self:float() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

-- Picks a key from { [key] = weight }. Keys are sorted so the result is deterministic.
function Rng.weighted(self: Rng, weights: { [string]: number }): string
	local keys = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	table.sort(keys)
	local roll = self:float() * total
	for _, key in keys do
		roll -= weights[key]
		if roll < 0 then
			return key
		end
	end
	return keys[#keys]
end

-- Derives an independent child generator (e.g. one per goblin).
function Rng.fork(self: Rng): Rng
	return Rng.new(self:nextU32())
end

return Rng
