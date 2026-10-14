--!strict
-- Equipment definitions. Ids are what gets saved; never rename an id once it ships.

export type Slot = "weapon" | "armor" | "utility"

export type Item = {
	id: string,
	name: string,
	slot: Slot,
	price: number,
	tier: number, -- drop tier: deeper floors can drop higher tiers
	attack: number?,
	defense: number?,
	perception: number?,
	luck: number?,
	food: number?,
	hp: number?,
	hardHat: boolean?, -- survives one instant-death trap at 1 HP
}

local Items = {}

local list: { Item } = {
	-- Weapons
	{ id = "stick", name = "Pointy Stick", slot = "weapon", price = 0, tier = 0, attack = 1 },
	{ id = "dagger", name = "Rusty Dagger", slot = "weapon", price = 40, tier = 1, attack = 3 },
	{ id = "shortsword", name = "Short Sword", slot = "weapon", price = 150, tier = 2, attack = 5 },
	{ id = "axe", name = "War Axe", slot = "weapon", price = 500, tier = 3, attack = 8 },
	{ id = "cleaver", name = "Ogre Cleaver", slot = "weapon", price = 1500, tier = 4, attack = 12 },

	-- Armor
	{ id = "rags", name = "Rags", slot = "armor", price = 0, tier = 0, defense = 0 },
	{ id = "leather", name = "Leather Vest", slot = "armor", price = 60, tier = 1, defense = 1 },
	{ id = "chainmail", name = "Chainmail", slot = "armor", price = 250, tier = 2, defense = 3 },
	{ id = "plate", name = "Dented Plate", slot = "armor", price = 900, tier = 3, defense = 5, hp = 4 },

	-- Utility
	{ id = "torch", name = "Torch", slot = "utility", price = 30, tier = 1, perception = 15 },
	{ id = "ration", name = "Rations", slot = "utility", price = 20, tier = 1, food = 6 },
	{ id = "charm", name = "Lucky Charm", slot = "utility", price = 120, tier = 2, luck = 25 },
	{ id = "hardhat", name = "Hard Hat", slot = "utility", price = 200, tier = 2, hardHat = true },
	{ id = "monocle", name = "Suspicious Monocle", slot = "utility", price = 400, tier = 3, perception = 35 },
}

local byId: { [string]: Item } = {}
for _, item in list do
	byId[item.id] = item
end

Items.list = list

function Items.get(id: string?): Item?
	if id == nil then
		return nil
	end
	return byId[id]
end

-- Items that can drop on a floor of this depth (price > 0 excludes starter junk).
function Items.dropPool(depth: number): { Item }
	local maxTier = math.min(1 + math.floor(depth / 3), 4)
	local pool = {}
	for _, item in list do
		if item.tier > 0 and item.tier <= maxTier then
			table.insert(pool, item)
		end
	end
	return pool
end

return Items
