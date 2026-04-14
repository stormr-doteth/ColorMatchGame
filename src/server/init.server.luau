local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))

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
		-- Check if it's a coin pack purchase
		for _, pack in ShopCatalog.GetCoinPacks() do
			if receiptInfo.ProductId == pack.productId then
				ProfileService.AddCash(player, pack.coins)
				RemoteSetup.Get("ShowNotification"):FireClient(player, `+${pack.coins} Coins!`)
				break
			end
		end
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
