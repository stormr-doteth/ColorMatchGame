-- LuckyBlockCatalog
-- Data-driven catalog of lucky block types. Adding a new block is one table
-- entry here + a matching Workspace model. Used by:
--   * Server (LuckyBlockShop) to set up prompts, validate purchases, roll loot
--   * Client (LuckyBlockClient) to know which chairs to cycle during reveal
--   * Client (LuckyBlockShopUI) to render the shop with prices and chances

export type LootEntry = {
	chairId: string, -- references a ChairCatalog id
	weight: number, -- relative probability (higher = more common)
}

export type BuyOption = {
	quantity: number, -- how many blocks you get
	price: number, -- total cost
}

export type LuckyBlockEntry = {
	id: string,
	displayName: string,
	modelName: string, -- name of the Model in Workspace (the display block)
	lootTable: { LootEntry },
	buyOptions: { BuyOption },
}

local LuckyBlockCatalog: { LuckyBlockEntry } = {
	{
		id = "secret_block",
		displayName = "Secret Lucky Block",
		modelName = "Secret Lucky Block",
		lootTable = {
			{ chairId = "red_chair", weight = 30 },
			{ chairId = "blue_chair", weight = 25 },
			{ chairId = "yellow_chair", weight = 25 },
			{ chairId = "teal_chair", weight = 20 },
		},
		buyOptions = {
			{ quantity = 1, price = 1 }, -- TODO: raise prices after testing
			{ quantity = 3, price = 2 },
			{ quantity = 5, price = 3 },
		},
	},
	{
		id = "mythic_block",
		displayName = "Mythic Lucky Block",
		modelName = "Mythic Lucky Block",
		lootTable = {
			{ chairId = "crystal_chair", weight = 40 },
			{ chairId = "flame_chair", weight = 30 },
			{ chairId = "shadow_chair", weight = 20 },
			{ chairId = "galaxy_chair", weight = 10 },
		},
		buyOptions = {
			{ quantity = 1, price = 2 }, -- TODO: raise prices after testing
			{ quantity = 3, price = 5 },
			{ quantity = 5, price = 7 },
		},
	},
	{
		id = "brainrot_block",
		displayName = "Brainrot God Lucky Block",
		modelName = "Brainrot God Lucky Block",
		lootTable = {
			{ chairId = "diamond_chair", weight = 40 },
			{ chairId = "lava_chair", weight = 30 },
			{ chairId = "rainbow_chair", weight = 20 },
			{ chairId = "brainrot_throne", weight = 10 },
		},
		buyOptions = {
			{ quantity = 1, price = 5 }, -- TODO: raise prices after testing
			{ quantity = 3, price = 12 },
			{ quantity = 5, price = 18 },
		},
	},
}

-- Helper: compute % chance for each loot entry
local function computeChances(lootTable: { LootEntry }): { [string]: number }
	local totalWeight = 0
	for _, loot in lootTable do
		totalWeight += loot.weight
	end
	local chances: { [string]: number } = {}
	for _, loot in lootTable do
		chances[loot.chairId] = math.floor((loot.weight / totalWeight) * 100 + 0.5)
	end
	return chances
end

local byId: { [string]: LuckyBlockEntry } = {}
for _, entry in LuckyBlockCatalog do
	byId[entry.id] = entry
end

local M = {}

function M.GetAll(): { LuckyBlockEntry }
	return LuckyBlockCatalog
end

function M.Get(id: string): LuckyBlockEntry?
	return byId[id]
end

function M.GetChances(id: string): { [string]: number }
	local entry = byId[id]
	if not entry then
		return {}
	end
	return computeChances(entry.lootTable)
end

return M
