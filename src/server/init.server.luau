local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))

local ProfileService = require(script:WaitForChild("data"):WaitForChild("ProfileService"))
local RemoteSetup = require(script:WaitForChild("game"):WaitForChild("RemoteSetup"))
local ChairShop = require(script:WaitForChild("game"):WaitForChild("ChairShop"))
local TableManager = require(script:WaitForChild("game"):WaitForChild("TableManager"))
local LuckyBlockShop = require(script:WaitForChild("game"):WaitForChild("LuckyBlockShop"))

ProfileService.Start()
print("ProfileService started")

RemoteSetup.Init()
ChairShop.Init()
LuckyBlockShop.Init()
TableManager.Init()

-- Developer product receipt processing
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receiptInfo.ProductId == Constants.HINT_PRODUCT_ID then
		RemoteSetup.Get("HintActivated"):FireClient(player)
	elseif receiptInfo.ProductId == Constants.MATCH_COLOR_PRODUCT_ID then
		RemoteSetup.Get("MatchColorActivated"):FireClient(player)
	else
		local handled = false

		-- Check if it's a dev product (cash or wins)
		local product = ShopCatalog.GetDevProductByProductId(receiptInfo.ProductId)
		if product then
			if product.category == "cash" then
				ProfileService.AddCash(player, product.amount)
				RemoteSetup.Get("ShowNotification"):FireClient(player, `+${product.amount} Cash!`)
			elseif product.category == "wins" then
				ProfileService.AddWins(player, product.amount)
				RemoteSetup.Get("ShowNotification"):FireClient(player, `+{product.amount} Wins!`)
			end
			handled = true
		end

		-- Check if it's a lucky block Robux purchase
		if not handled then
			for _, entry in LuckyBlockCatalog.GetAll() do
				if entry.robuxProductId and entry.robuxProductId == receiptInfo.ProductId then
					ProfileService.AddLuckyBlock(player, entry.id)
					LuckyBlockShop.GrantTool(player, entry.id)
					RemoteSetup.Get("ShowNotification"):FireClient(player, `Purchased {entry.displayName}!`)
					handled = true
					break
				end
			end
		end
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
