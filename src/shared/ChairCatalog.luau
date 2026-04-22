-- ChairCatalog
-- Single source of truth for purchasable chair skins. Used by:
--   * Server (ChairShop) to set up shop prompts and validate purchases
--   * Server (TableManager) to look up the equipped chair model on seat
--   * Client (InventoryHud) to render owned chairs in the inventory UI
--
-- A chair entry is identified by `id` (a stable string saved in the player
-- profile). `modelName` is the name of the chair Model in workspace, which
-- the server clones into ReplicatedStorage.ChairTemplates at startup.

export type ChairEntry = {
	id: string,
	displayName: string,
	price: number,
	modelName: string,
	rarity: string, -- "common"|"uncommon"|"rare"|"epic"|"legendary"|"stormbringer"|"glacial"
	flipSeat: boolean?, -- true = rotate entire chair 180° yaw (body + seat together)
	flipSeatDirection: boolean?, -- true = rotate ONLY the Seat 180° (fixes player-faces-wrong-way when body is correct but Seat was authored reversed)
	viewportFlip: boolean?, -- override for viewport-only flip. nil = inherit flipSeat; explicit bool decouples viewport from world-flip
	viewportZoom: number?, -- multiplier on viewport camera distance (>1 = farther/smaller, <1 = closer/bigger)
	yOffset: number?, -- studs to nudge the chair on Y after ground-snap. Negative lowers the chair. Use when ground-snap's "lowest visible part" lands on an invisible hitbox/anchor that's lower than the visible mesh.
	displayYOffset: number?, -- Y nudge applied specifically on ChairDisplay shop stands (separate from seated `yOffset`).
}

local ChairCatalog: { ChairEntry } = {
	-- Common tier (lucky block exclusive) — solid color wooden chairs
	{ id = "red_chair",    displayName = "Red Chair",    price = 0, modelName = "BaseChair_Red",    rarity = "common" },
	{ id = "orange_chair", displayName = "Orange Chair", price = 0, modelName = "BaseChair_Orange", rarity = "common" },
	{ id = "yellow_chair", displayName = "Yellow Chair", price = 0, modelName = "BaseChair_Yellow", rarity = "common" },
	{ id = "green_chair",  displayName = "Green Chair",  price = 0, modelName = "BaseChair_Green",  rarity = "common" },
	{ id = "blue_chair",   displayName = "Blue Chair",   price = 0, modelName = "BaseChair_Blue",   rarity = "common" },
	{ id = "violet_chair", displayName = "Violet Chair", price = 0, modelName = "BaseChair_Violet", rarity = "common" },

	-- Uncommon tier (lucky block exclusive)
	{ id = "toilet_chair",   displayName = "Toilet",         price = 0, modelName = "Toilet",         rarity = "uncommon", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "rocking_chair",  displayName = "Rocking Chair",  price = 0, modelName = "RockingChair",   rarity = "uncommon", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "camping_chair",  displayName = "Camping Chair",  price = 0, modelName = "CampingChair",   rarity = "uncommon", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "cushion_chair",  displayName = "Cushion Chair",  price = 0, modelName = "CushionChair",   rarity = "uncommon", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "tree_stump",     displayName = "Tree Stump",     price = 0, modelName = "TreeStump",      rarity = "uncommon", yOffset = -2 },

	-- Rare tier (Rare block exclusive)
	{ id = "samurai_throne",     displayName = "Samurai Throne",   price = 0, modelName = "Samurai Throne", rarity = "rare", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "regal_throne",       displayName = "Regal Throne",     price = 0, modelName = "Throne",         rarity = "rare", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "toilet_throne",      displayName = "Golden Toilet",    price = 0, modelName = "Golden Toilet",  rarity = "rare", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "phoenix_throne",     displayName = "Phoenix Throne",   price = 0, modelName = "PhoenixThrone",  rarity = "rare", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "rare_gaming_chair",  displayName = "Gaming Chair",     price = 0, modelName = "Gaming Chair",   rarity = "rare", flipSeat = true, flipSeatDirection = true, viewportFlip = false },

	{ id = "opal_throne",         displayName = "Opal Throne",         price = 0, modelName = "OpalThrone",         rarity = "epic", flipSeat = true, flipSeatDirection = true, viewportFlip = false },

	-- Legendary tier (Legendary block exclusive)
	{ id = "elderwood_throne",       displayName = "Elderwood Throne",       price = 0, modelName = "ElderwoodThrone",       rarity = "legendary", flipSeat = true, flipSeatDirection = true, viewportFlip = false, yOffset = -2.5, displayYOffset = -2 },
	{ id = "chronos_throne",         displayName = "Chronos Throne",         price = 0, modelName = "ChronosThrone",         rarity = "legendary", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "dragon_emperor_throne",  displayName = "Dragon Emperor Throne",  price = 0, modelName = "DragonEmperorThrone",   rarity = "legendary", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "oblivion_throne",        displayName = "Oblivion Throne",        price = 0, modelName = "OblivionThrone",        rarity = "legendary", flipSeat = true, flipSeatDirection = true, viewportFlip = false },

	-- Glacial tier (Glacial block exclusive — Robux only)
	{ id = "glacier_throne",    displayName = "Glacier Throne",    price = 0, modelName = "GlacierThrone",    rarity = "glacial", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "yeti_throne",       displayName = "Yeti Throne",       price = 0, modelName = "YetiThrone",       rarity = "glacial", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "krampus_throne",    displayName = "Krampus Throne",    price = 0, modelName = "KrampusThrone",    rarity = "glacial", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "cryomancer_throne", displayName = "Cryomancer Throne", price = 0, modelName = "CryomancerThrone", rarity = "glacial", flipSeat = true, flipSeatDirection = true, viewportFlip = false },

	-- Stormbringer tier (Stormbringer block exclusive)
	{ id = "thunder_throne",   displayName = "Thunder Throne",   price = 0, modelName = "ThunderThrone",   rarity = "stormbringer", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "tempest_throne",   displayName = "Tempest Throne",   price = 0, modelName = "TempestThrone",   rarity = "stormbringer", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "monsoon_throne",   displayName = "Monsoon Throne",   price = 0, modelName = "MonsoonThrone",   rarity = "stormbringer", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "zeus_throne",      displayName = "Zeus Throne",      price = 0, modelName = "ZeusThrone",      rarity = "stormbringer", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "storm_god_throne", displayName = "Storm God Throne", price = 0, modelName = "StormGodThrone",  rarity = "stormbringer", flipSeat = true, flipSeatDirection = true, viewportFlip = false },

	-- Epic tier (Epic block exclusive)
	{ id = "shadow_seat",       displayName = "Shadow Seat",      price = 0, modelName = "ShadowSeat",       rarity = "epic", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "celestial_throne",  displayName = "Celestial Throne", price = 0, modelName = "CelestialThrone",  rarity = "epic", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "flame_throne",      displayName = "Flame Throne",     price = 0, modelName = "FlameThrone",      rarity = "epic", flipSeat = true, flipSeatDirection = true, viewportFlip = false },
	{ id = "cloud_chair",       displayName = "Cloud Chair",      price = 0, modelName = "CloudChair",       rarity = "epic", flipSeat = true, flipSeatDirection = true, viewportFlip = false },

	-- Gamepass exclusives (granted when the matching gamepass is purchased)
	{ id = "office_chair", displayName = "Office Chair", price = 0, modelName = "OfficeChair", rarity = "gamepass", viewportZoom = 1.8, flipSeat = true, flipSeatDirection = true, viewportFlip = false, yOffset = 1.75 },
	{ id = "vip_throne",   displayName = "VIP Throne",   price = 0, modelName = "VipThrone",   rarity = "gamepass", flipSeat = true, flipSeatDirection = true, viewportFlip = true },
}

local byId: { [string]: ChairEntry } = {}
for _, entry in ChairCatalog do
	byId[entry.id] = entry
end

local M = {}

function M.GetAll(): { ChairEntry }
	return ChairCatalog
end

function M.Get(id: string): ChairEntry?
	return byId[id]
end

return M
