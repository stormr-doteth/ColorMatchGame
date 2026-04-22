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

export type RobuxPackage = {
	quantity: number, -- how many blocks this product grants
	productId: number, -- dev product ID (0 = not set yet)
}

export type LuckyBlockEntry = {
	id: string,
	displayName: string,
	modelName: string, -- name of the Model in Workspace (the display block)
	lootTable: { LootEntry },
	buyOptions: { BuyOption },
	robuxProductId: number?, -- dev product ID for single-block Robux purchase
	robuxPrice: number?, -- Robux price for display (set on the Creator Dashboard for the actual product)
	robuxPackages: { RobuxPackage }?, -- multi-quantity Robux packages (e.g. 1x/3x/5x)
	shopType: string?, -- "shop" (default) or "cosmetics" — which UI this block opens
	imageId: number?, -- asset ID for the block's image/icon in shop cards
}

local LuckyBlockCatalog: { LuckyBlockEntry } = {
	-- Cosmetics Shop blocks (purchasable with cash + Robux)
	{
		id = "common_block",
		displayName = "Common Block",
		modelName = "CommonBlock",
		shopType = "cosmetics",
		robuxProductId = 3575825989,
		robuxPrice = 9,
		imageId = 105629651259186,
		lootTable = {
			{ chairId = "red_chair",    weight = 1 },
			{ chairId = "yellow_chair", weight = 1 },
			{ chairId = "green_chair",  weight = 1 },
			{ chairId = "blue_chair",   weight = 1 },
			{ chairId = "violet_chair", weight = 1 },
		},
		buyOptions = {
			{ quantity = 1, price = 250 },
		},
	},
	{
		id = "uncommon_block",
		displayName = "Uncommon Block",
		modelName = "UncommonBlock",
		shopType = "cosmetics",
		robuxProductId = 3575826043,
		robuxPrice = 15,
		imageId = 90687483761350,
		lootTable = {
			{ chairId = "toilet_chair",  weight = 1 },
			{ chairId = "rocking_chair", weight = 1 },
			{ chairId = "camping_chair", weight = 1 },
			{ chairId = "cushion_chair", weight = 1 },
			{ chairId = "tree_stump",    weight = 1 },
		},
		buyOptions = {
			{ quantity = 1, price = 500 },
		},
	},
	{
		id = "rare_block",
		displayName = "Rare Block",
		modelName = "RareBlock",
		shopType = "cosmetics",
		robuxProductId = 3575826076,
		robuxPrice = 25,
		imageId = 129221708610973,
		lootTable = {
			{ chairId = "rare_gaming_chair", weight = 30 },
			{ chairId = "regal_throne",      weight = 25 },
			{ chairId = "toilet_throne",     weight = 20 },
			{ chairId = "samurai_throne",    weight = 15 },
			{ chairId = "phoenix_throne",    weight = 10 },
		},
		buyOptions = {
			{ quantity = 1, price = 800 },
		},
	},
	{
		id = "epic_block",
		displayName = "Epic Block",
		modelName = "EpicBlock",
		shopType = "cosmetics",
		robuxProductId = 3575826120,
		robuxPrice = 49,
		imageId = 112821596275173,
		lootTable = {
			{ chairId = "cloud_chair",      weight = 50 },
			{ chairId = "flame_throne",     weight = 30 },
			{ chairId = "celestial_throne", weight = 13 },
			{ chairId = "shadow_seat",      weight = 5 },
			{ chairId = "opal_throne",      weight = 2 },
		},
		buyOptions = {
			{ quantity = 1, price = 1500 },
		},
	},
	{
		id = "glacial_block",
		displayName = "Glacial Block",
		modelName = "GlacialBlock",
		robuxProductId = 3578611641,
		robuxPackages = {
			{ quantity = 1, productId = 3578611641 },
			{ quantity = 3, productId = 3578989408 },
			{ quantity = 5, productId = 3578989491 },
		},
		imageId = 137563051885989,
		lootTable = {
			{ chairId = "glacier_throne",    weight = 50 },
			{ chairId = "yeti_throne",       weight = 30 },
			{ chairId = "krampus_throne",    weight = 15 },
			{ chairId = "cryomancer_throne", weight = 5 },
		},
		buyOptions = {}, -- Robux only, no cash purchase
	},
	{
		id = "stormbringer_block",
		displayName = "Storm Block",
		modelName = "StormBlock",
		robuxProductId = 3578611508,
		robuxPackages = {
			{ quantity = 1, productId = 3578611508 },
			{ quantity = 3, productId = 3578989669 },
			{ quantity = 5, productId = 3578989769 },
		},
		imageId = 116470141222904,
		lootTable = {
			{ chairId = "thunder_throne",   weight = 50 },
			{ chairId = "tempest_throne",   weight = 30 },
			{ chairId = "monsoon_throne",   weight = 13 },
			{ chairId = "zeus_throne",      weight = 5 },
			{ chairId = "storm_god_throne", weight = 2 },
		},
		buyOptions = {
			{ quantity = 1, price = 5000 },
		},
	},
	{
		id = "legendary_block",
		displayName = "Legendary Block",
		modelName = "LegendaryBlock",
		shopType = "cosmetics",
		robuxProductId = 3575826157,
		robuxPrice = 69,
		imageId = 134983609308824,
		lootTable = {
			{ chairId = "elderwood_throne",      weight = 45 },
			{ chairId = "chronos_throne",        weight = 30 },
			{ chairId = "dragon_emperor_throne", weight = 20 },
			{ chairId = "oblivion_throne",       weight = 5 },
		},
		buyOptions = {
			{ quantity = 1, price = 2500 },
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
