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
local ChairDisplays = require(script:WaitForChild("game"):WaitForChild("ChairDisplays"))
local VipDisplay = require(script:WaitForChild("game"):WaitForChild("VipDisplay"))
local VipChatTag = require(script:WaitForChild("game"):WaitForChild("VipChatTag"))
local GamePassUtil = require(script:WaitForChild("game"):WaitForChild("GamePassUtil"))
local DailyRewards = require(script:WaitForChild("game"):WaitForChild("DailyRewards"))
local PlaytimeRewards = require(script:WaitForChild("game"):WaitForChild("PlaytimeRewards"))
local RateLimit = require(script:WaitForChild("game"):WaitForChild("RateLimit"))
local ChairTestHarness = require(script:WaitForChild("game"):WaitForChild("ChairTestHarness"))
local WinsLeaderboard = require(script:WaitForChild("game"):WaitForChild("WinsLeaderboard"))
local FeedbackStore = require(script:WaitForChild("game"):WaitForChild("FeedbackStore"))
local Analytics = require(script:WaitForChild("game"):WaitForChild("Analytics"))
local PolicyGate = require(script:WaitForChild("game"):WaitForChild("PolicyGate"))
local ZoneTrigger = require(script:WaitForChild("game"):WaitForChild("ZoneTrigger"))

ProfileService.Start()
print("ProfileService started")

RemoteSetup.Init()
ZoneTrigger.Init()
ChairShop.Init()
LuckyBlockShop.Init()
ChairDisplays.Init()
VipDisplay.Init()
VipChatTag.Init()
DailyRewards.Init()
PlaytimeRewards.Init()
TableManager.Init()
ChairTestHarness.Init()
WinsLeaderboard.Init()
FeedbackStore.Init()
Analytics.Init()
PolicyGate.Init()

-- Default walk speed
local DEFAULT_WALK_SPEED = 30
local function applyWalkSpeed(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	end
end
local function grantPassChairs(player: Player)
	task.spawn(function()
		if GamePassUtil.HasPass(player, "VIP") then
			ProfileService.AddChair(player, "vip_throne")
		end
		if GamePassUtil.HasPass(player, "STARTER_PACK") then
			ProfileService.AddChair(player, "office_chair")
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(applyWalkSpeed)
	if player.Character then
		applyWalkSpeed(player.Character)
	end
	grantPassChairs(player)
	GamePassUtil.SyncBoostAttributes(player)
	task.delay(2, function()
		if player.Parent then
			Analytics.LogOnboarding(player, 1, "Joined")
		end
	end)
end)
for _, p in Players:GetPlayers() do
	p.CharacterAdded:Connect(applyWalkSpeed)
	if p.Character then
		applyWalkSpeed(p.Character)
	end
	grantPassChairs(p)
	GamePassUtil.SyncBoostAttributes(p)
end

-- Developer product receipt processing. Must be idempotent: Roblox retries the
-- same PurchaseId on transient failures, so we persist processed receipt IDs
-- in the profile and skip grants if we've seen this one. Return NotProcessedYet
-- for any error path so Roblox retries; return PurchaseGranted only after the
-- grant is confirmed in the profile.
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Profile must be loaded to record idempotency. If not loaded yet, retry.
	if not ProfileService.GetData(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = tostring(receiptInfo.PurchaseId)

	-- Grant exactly once. TryRecordReceipt returns false if we've already
	-- processed this PurchaseId (retry) — safe to ack as granted.
	local ok, granted = pcall(function()
		if not ProfileService.TryRecordReceipt(player, receiptId) then
			return true -- already granted; ack
		end

		if receiptInfo.ProductId == Constants.HINT_PRODUCT_ID then
			ProfileService.AddHints(player, 1)
			RemoteSetup.Get("HintActivated"):FireClient(player)
			Analytics.LogEconomy(player, "Source", "Robux", receiptInfo.CurrencySpent or 0, "IAP", "devproduct_hint", "lobby")
			return true
		elseif receiptInfo.ProductId == Constants.MATCH_COLOR_PRODUCT_ID then
			ProfileService.AddMatches(player, 1)
			RemoteSetup.Get("MatchColorActivated"):FireClient(player)
			Analytics.LogEconomy(player, "Source", "Robux", receiptInfo.CurrencySpent or 0, "IAP", "devproduct_match_color", "lobby")
			return true
		end

		local product = ShopCatalog.GetDevProductByProductId(receiptInfo.ProductId)
		if product then
			if product.category == "cash" then
				ProfileService.AddCash(player, product.amount)
				RemoteSetup.Get("ShowNotification"):FireClient(player, `+${product.amount} Cash!`)
			elseif product.category == "wins" then
				ProfileService.AddWins(player, product.amount)
				RemoteSetup.Get("ShowNotification"):FireClient(player, `+{product.amount} Wins!`)
			end
			Analytics.LogEconomy(player, "Source", "Robux", receiptInfo.CurrencySpent or 0, "IAP", "devproduct_" .. product.category .. "_" .. tostring(product.amount), "lobby")
			return true
		end

		for _, entry in LuckyBlockCatalog.GetAll() do
			local matchedQty: number? = nil
			if entry.robuxPackages then
				for _, pkg in entry.robuxPackages do
					if pkg.productId and pkg.productId > 0 and pkg.productId == receiptInfo.ProductId then
						matchedQty = pkg.quantity
						break
					end
				end
			end
			if not matchedQty and entry.robuxProductId and entry.robuxProductId == receiptInfo.ProductId then
				matchedQty = 1
			end
			if matchedQty then
				-- Paid random-item regional restriction. The client is supposed
				-- to suppress the prompt entirely; if a restricted player still
				-- reaches here (spoofed client, stale policy cache, etc.), we
				-- refuse the grant so Robux isn't charged for an illegal sale.
				-- NotProcessedYet keeps Roblox retrying until the policy lifts
				-- or the player is refunded manually via the dev dashboard.
				if PolicyGate.IsPaidRandomRestricted(player) then
					warn(("[ProcessReceipt] Paid random item blocked for %s (%s)"):format(player.Name, entry.id))
					return false
				end
				for _ = 1, matchedQty do
					ProfileService.AddLuckyBlock(player, entry.id)
					LuckyBlockShop.GrantTool(player, entry.id)
				end
				Analytics.LogEconomy(player, "Source", "Robux", receiptInfo.CurrencySpent or 0, "IAP", "luckyblock_robux_" .. entry.id, "lobby")
				local suffix = if matchedQty > 1 then ` x{matchedQty}` else ""
				RemoteSetup.Get("ShowNotification"):FireClient(player, `Purchased {entry.displayName}{suffix}!`)
				return true
			end
		end

		-- Unknown product ID: don't ack as granted.
		warn(("[ProcessReceipt] Unknown ProductId %s for %s"):format(tostring(receiptInfo.ProductId), player.Name))
		return false
	end)

	if not ok then
		warn(("[ProcessReceipt] Grant error for %s: %s"):format(player.Name, tostring(granted)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Force a save so we only ack PurchaseGranted after the grant +
	-- ProcessedReceipts mark actually hit DataStore. If the save fails,
	-- return NotProcessedYet and let Roblox retry later — TryRecordReceipt
	-- will short-circuit the grant next time so there's no double-grant.
	if not ProfileService.SaveProfile(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Game pass purchase handling (VIP, Starter Pack, etc.)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end

	Analytics.LogCustom(player, "GamePassPurchased", gamePassId, {
		CustomField04 = tostring(gamePassId),
	}, "lobby")

	local granted = false
	local ok, err = pcall(function()
		-- Without a loaded profile we can't persist the grant — tell the user
		-- rather than silently dropping a paid gamepass.
		if not ProfileService.GetData(player) then
			warn(("[GamePassPurchaseFinished] no profile for %s; grant dropped"):format(player.Name))
			RemoteSetup.Get("ShowNotification"):FireClient(player, "Purchase couldn't be applied — please rejoin. Contact support if the benefit doesn't appear.")
			return
		end
		granted = true

		if gamePassId == GamePassUtil.GetPassId("STARTER_PACK") then
			GamePassUtil.MarkOwned(player, "STARTER_PACK")
			ProfileService.AddCash(player, 500)
			ProfileService.AddChair(player, "office_chair")
			ProfileService.AddHints(player, 3)
			RemoteSetup.Get("ShowNotification"):FireClient(player, "Starter Pack activated! +500 Cash, Office Chair, +3 Hints!")
		elseif gamePassId == GamePassUtil.GetPassId("VIP") then
			GamePassUtil.MarkOwned(player, "VIP")
			ProfileService.AddChair(player, "vip_throne")
			VipChatTag.Refresh(player)
			RemoteSetup.Get("ShowNotification"):FireClient(player, "VIP activated! +VIP Throne!")
			RemoteSetup.Get("BoostActivated"):FireClient(player, "VIP")
		elseif gamePassId == GamePassUtil.GetPassId("DOUBLE_CASH") then
			GamePassUtil.MarkOwned(player, "DOUBLE_CASH")
			RemoteSetup.Get("BoostActivated"):FireClient(player, "DOUBLE_CASH")
		elseif gamePassId == GamePassUtil.GetPassId("DOUBLE_WINS") then
			GamePassUtil.MarkOwned(player, "DOUBLE_WINS")
			RemoteSetup.Get("BoostActivated"):FireClient(player, "DOUBLE_WINS")
		elseif gamePassId == GamePassUtil.GetPassId("DOUBLE_STREAK") then
			GamePassUtil.MarkOwned(player, "DOUBLE_STREAK")
			RemoteSetup.Get("BoostActivated"):FireClient(player, "DOUBLE_STREAK")
		end
	end)
	if not ok then
		warn(("[GamePassPurchaseFinished] error for %s: %s"):format(player.Name, tostring(err)))
		RemoteSetup.Get("ShowNotification"):FireClient(player, "Purchase couldn't be applied — please rejoin. Contact support if the benefit doesn't appear.")
		return
	end
	-- Persist the gamepass-derived grant immediately so a crash between
	-- now and the next autosave can't erase it.
	if granted then
		ProfileService.SaveProfile(player)
	end
end)

-- Use hint / match: decrement persistent inventory. Client fires optimistically
-- on use; server is the source of truth for the count.
RemoteSetup.Get("UseHint").OnServerEvent:Connect(function(player)
	if not RateLimit.check("UseHint", player, 0.3) then return end
	ProfileService.UseHint(player)
end)

RemoteSetup.Get("UseMatch").OnServerEvent:Connect(function(player)
	if not RateLimit.check("UseMatch", player, 0.3) then return end
	ProfileService.UseMatch(player)
end)

-- Group reward (one-time, requires group membership)
local GROUP_ID = 626343155
RemoteSetup.Get("ClaimGroupReward").OnServerEvent:Connect(function(player)
	if not RateLimit.check("ClaimGroupReward", player, 1.0) then return end
	local data = ProfileService.GetData(player)
	if not data then return end
	if data.GroupRewardClaimed then return end

	local ok, inGroup = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if not ok or not inGroup then return end

	data.GroupRewardClaimed = true
	ProfileService.AddCash(player, 250)
	ProfileService.AddLuckyBlock(player, "uncommon_block")
	LuckyBlockShop.GrantTool(player, "uncommon_block")
	ProfileService.AddHints(player, 2)
	Analytics.LogEconomy(player, "Source", "Cash", 250, "Reward", "group_reward", "lobby")
	Analytics.LogCustom(player, "RewardClaimed", 1, { CustomField04 = "group" }, "lobby")
	RemoteSetup.Get("ShowNotification"):FireClient(player, "Group reward claimed! +$250 + Uncommon Block + 2 Hints!")
end)

-- VIP reward (one-time, requires VIP pass)
RemoteSetup.Get("ClaimVIPReward").OnServerEvent:Connect(function(player)
	if not RateLimit.check("ClaimVIPReward", player, 1.0) then return end
	local data = ProfileService.GetData(player)
	if not data then return end
	if data.VIPRewardClaimed then return end

	if not GamePassUtil.HasPass(player, "VIP") then return end

	data.VIPRewardClaimed = true
	ProfileService.AddCash(player, 500)
	ProfileService.AddLuckyBlock(player, "rare_block")
	LuckyBlockShop.GrantTool(player, "rare_block")
	ProfileService.AddHints(player, 1)
	Analytics.LogEconomy(player, "Source", "Cash", 500, "Reward", "vip_reward", "lobby")
	Analytics.LogCustom(player, "RewardClaimed", 1, { CustomField04 = "vip" }, "lobby")
	RemoteSetup.Get("ShowNotification"):FireClient(player, "VIP reward claimed! +$500 + Rare Block + Hint!")
end)
