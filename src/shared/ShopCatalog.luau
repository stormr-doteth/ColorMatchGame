-- ShopCatalog
-- Defines coin packs (dev products) and game passes for the unified shop.
-- Product/pass IDs are placeholders (0) until created on the Roblox dashboard.
-- Update the IDs here once created — no other code changes needed.

export type CoinPack = {
	id: string,
	displayName: string,
	coins: number,
	robuxPrice: number, -- shown in UI (actual price set on dashboard)
	productId: number, -- Roblox developer product ID (0 = placeholder)
}

export type GamePass = {
	id: string,
	displayName: string,
	description: string,
	robuxPrice: number, -- shown in UI
	gamePassId: number, -- Roblox game pass ID (0 = placeholder)
	frameName: string?, -- name of the Frame in Shop.Body.GamePasses (for manual UI)
}

local CoinPacks: { CoinPack } = {
	{ id = "coins_250",   displayName = "Starter Pack",  coins = 250,    robuxPrice = 49,  productId = 3575477629 },
	{ id = "coins_1000",  displayName = "Small Pack",    coins = 1000,   robuxPrice = 149, productId = 3575477715 },
	{ id = "coins_5000",  displayName = "Medium Pack",   coins = 5000,   robuxPrice = 499, productId = 3575477758 },
	{ id = "coins_25000", displayName = "Large Pack",    coins = 25000,  robuxPrice = 1999, productId = 3575478040 },
}

-- frameName = the name of the Frame inside Shop.Body.GamePasses
local GamePasses: { GamePass } = {
	{ id = "2x_coins", displayName = "DOUBLE CASH", description = "Double all coin earnings permanently!", robuxPrice = 299, gamePassId = 1797672278, frameName = "DoubleCash" },
	{ id = "2x_wins",  displayName = "DOUBLE WINS", description = "Double all win earnings permanently!", robuxPrice = 299, gamePassId = 1796710377, frameName = "DoubleWins" },
}

local M = {}

function M.GetCoinPacks(): { CoinPack }
	return CoinPacks
end

function M.GetGamePasses(): { GamePass }
	return GamePasses
end

function M.GetCoinPack(id: string): CoinPack?
	for _, pack in CoinPacks do
		if pack.id == id then return pack end
	end
	return nil
end

function M.GetGamePass(id: string): GamePass?
	for _, pass in GamePasses do
		if pass.id == id then return pass end
	end
	return nil
end

return M
