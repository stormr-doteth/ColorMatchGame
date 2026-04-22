-- ShopCatalog
-- Defines dev products (cash, wins) and game passes for the unified shop.
-- All IDs match the Roblox dashboard. Frames are matched by ItemLabel text
-- in the manually-designed Shop UI.

export type DevProduct = {
	id: string,
	displayName: string, -- matches ItemLabel.Text in the UI
	amount: number, -- how much to grant
	robuxPrice: number, -- shown in UI
	productId: number, -- Roblox developer product ID
	category: string, -- "cash" or "wins"
}

export type GamePass = {
	id: string,
	displayName: string, -- matches ItemLabel.Text in the UI
	robuxPrice: number,
	gamePassId: number,
}

local DevProducts: { DevProduct } = {
	-- Cash packs (in DevProducts frame)
	{ id = "cash_300",   displayName = "300 CASH",    amount = 300,   robuxPrice = 29,  productId = 3575477629, category = "cash" },
	{ id = "cash_1000",  displayName = "1,000 CASH",  amount = 1000,  robuxPrice = 89,  productId = 3575477715, category = "cash" },
	{ id = "cash_2500",  displayName = "2,500 CASH",  amount = 2500,  robuxPrice = 199, productId = 3575477758, category = "cash" },
	{ id = "cash_5000",  displayName = "5,000 CASH!", amount = 5000,  robuxPrice = 349, productId = 3575478040, category = "cash" },

	-- Wins packs (in DevProducts_Wins frame)
	{ id = "wins_10",    displayName = "10 WINS",     amount = 10,    robuxPrice = 39,  productId = 3575511557, category = "wins" },
	{ id = "wins_25",    displayName = "25 WINS",     amount = 25,    robuxPrice = 79,  productId = 3575511597, category = "wins" },
	{ id = "wins_50",    displayName = "50 WINS",     amount = 50,    robuxPrice = 179, productId = 3575511650, category = "wins" },
	{ id = "wins_100",   displayName = "100 WINS",    amount = 100,   robuxPrice = 249, productId = 3575511685, category = "wins" },
}

local GamePasses: { GamePass } = {
	{ id = "2x_cash",   displayName = "DOUBLE CASH",   robuxPrice = 99, gamePassId = 1797672278 },
	{ id = "2x_wins",   displayName = "DOUBLE WINS",   robuxPrice = 99, gamePassId = 1796963414 },
	{ id = "2x_streak", displayName = "DOUBLE STREAK", robuxPrice = 99, gamePassId = 1797239408 },
	{ id = "vip",          displayName = "VIP",            robuxPrice = 149, gamePassId = 1796710377 },
	{ id = "starter_pack", displayName = "STARTER PACK",   robuxPrice = 99,  gamePassId = 1796993729 },
}

local M = {}

function M.GetDevProducts(): { DevProduct }
	return DevProducts
end

function M.GetGamePasses(): { GamePass }
	return GamePasses
end

function M.GetDevProduct(id: string): DevProduct?
	for _, p in DevProducts do
		if p.id == id then return p end
	end
	return nil
end

function M.GetDevProductByProductId(productId: number): DevProduct?
	for _, p in DevProducts do
		if p.productId == productId then return p end
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
