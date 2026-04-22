-- Thin adapter wiring the DailyRewards package to this game's ProfileService,
-- GamePassUtil, and Remotes. The reusable logic lives in
-- packages/daily-rewards — keep game-specific config (reward table, VIP
-- multiplier source, notification channel) here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("data"):WaitForChild("ProfileService"))
local GamePassUtil = require(ServerScriptService:WaitForChild("Server"):WaitForChild("game"):WaitForChild("GamePassUtil"))
local DailyRewardsPackage = require(ServerScriptService:WaitForChild("DailyRewards"))

local DAY_REWARDS = {
	{ cash = 75,   hint = 1 },
	{ cash = 150,  match = 1 },
	{ cash = 250,  luckyBlock = "common_block" },
	{ cash = 400,  hint = 1, match = 1 },
	{ cash = 600,  luckyBlock = "uncommon_block" },
	{ cash = 900,  hint = 2 },
	{ cash = 1500, luckyBlock = "rare_block", hint = 1, match = 1 },
}

local DailyRewards = {}
local instance

function DailyRewards.Init()
	if instance then return end
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	instance = DailyRewardsPackage.new({
		profile = {
			isLoaded = function(player)
				return ProfileService.GetProfile(player) ~= nil
			end,
			getData = ProfileService.GetDailyRewardData,
			setData = ProfileService.SetDailyRewardData,
			addCash = ProfileService.AddCash,
			addHints = ProfileService.AddHints,
			addMatches = ProfileService.AddMatches,
			addLuckyBlock = ProfileService.AddLuckyBlock,
			cashMultiplier = function(player)
				local mult = 1
				if GamePassUtil.HasPass(player, "VIP") then mult *= 1.5 end
				if GamePassUtil.HasPass(player, "DOUBLE_CASH") then mult *= 2 end
				return mult
			end,
		},
		dataRemote = Remotes:WaitForChild("DailyRewardData"),
		claimRemote = Remotes:WaitForChild("ClaimDailyReward"),
		dayRewards = DAY_REWARDS,
		notify = function(player, message)
			local notifyRemote = Remotes:FindFirstChild("ShowNotification")
			if notifyRemote then
				notifyRemote:FireClient(player, message)
			end
		end,
	})
end

-- Preserved for external callers. Forwards to the package instance.
function DailyRewards.CheckAndNotify(player: Player)
	if instance then
		instance:CheckAndNotify(player)
	end
end

function DailyRewards.Claim(player: Player)
	if instance then
		instance:Claim(player)
	end
end

return DailyRewards
