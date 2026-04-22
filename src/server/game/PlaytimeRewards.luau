-- PlaytimeRewards
-- Tracks session playtime and grants milestone rewards.
-- Milestones reset each session (not persisted).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("data"):WaitForChild("ProfileService"))

-- Milestones must match UI labels in
-- StarterGui.ScreenGui.Rewards.Body.PlaytimeRewards.<id>
local MILESTONES = {
	{ id = "5_min",  seconds = 300,  cash = 75,   hint = 1 },
	{ id = "10_min", seconds = 600,  cash = 150,  match = 1 },
	{ id = "15_min", seconds = 900,  cash = 250,  luckyBlock = "common_block" },
	{ id = "20_min", seconds = 1200, cash = 400,  hint = 1, match = 1 },
	{ id = "30_min", seconds = 1800, cash = 600,  luckyBlock = "uncommon_block" },
	{ id = "45_min", seconds = 2700, cash = 900,  hint = 2 },
	{ id = "60_min", seconds = 3600, cash = 1500, luckyBlock = "rare_block", hint = 1, match = 1 },
}

-- Session state (not persisted)
local joinTimes: { [Player]: number } = {} -- os.clock() when joined
local claimed: { [Player]: { [string]: boolean } } = {}

local PlaytimeRewards = {}

function PlaytimeRewards.GetMilestones()
	return MILESTONES
end

function PlaytimeRewards.GetData(player: Player): { joinTime: number, claimed: { [string]: boolean } }
	return {
		joinTime = joinTimes[player] or os.clock(),
		claimed = claimed[player] or {},
	}
end

function PlaytimeRewards.Init()
	local function onPlayerAdded(player: Player)
		joinTimes[player] = os.clock()
		claimed[player] = {}
	end

	local function onPlayerRemoving(player: Player)
		joinTimes[player] = nil
		claimed[player] = nil
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Listen for claim requests
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RateLimit = require(script.Parent:WaitForChild("RateLimit"))
	Remotes:WaitForChild("ClaimPlaytimeReward").OnServerEvent:Connect(function(player, milestoneId)
		if typeof(milestoneId) ~= "string" then return end
		if not RateLimit.check("ClaimPlaytimeReward", player, 0.5) then return end

		local joinTime = joinTimes[player]
		if not joinTime then return end

		local playerClaimed = claimed[player]
		if not playerClaimed then return end
		if playerClaimed[milestoneId] then return end -- already claimed

		-- Find the milestone
		local milestone = nil
		for _, m in MILESTONES do
			if m.id == milestoneId then
				milestone = m
				break
			end
		end
		if not milestone then return end

		-- Check elapsed time
		local elapsed = os.clock() - joinTime
		if elapsed < milestone.seconds then return end

		-- Grant rewards
		ProfileService.AddCash(player, milestone.cash)

		if milestone.luckyBlock then
			ProfileService.AddLuckyBlock(player, milestone.luckyBlock)
		end

		if milestone.hint then
			ProfileService.AddHints(player, milestone.hint)
		end
		if milestone.match then
			ProfileService.AddMatches(player, milestone.match)
		end

		playerClaimed[milestoneId] = true

		local notifyRemote = Remotes:FindFirstChild("ShowNotification")
		if notifyRemote then
			local parts = { `+${milestone.cash} Cash` }
			if milestone.hint then table.insert(parts, `+{milestone.hint} Hint`) end
			if milestone.match then table.insert(parts, `+{milestone.match} Match`) end
			if milestone.luckyBlock then table.insert(parts, "+1 Lucky Block") end
			notifyRemote:FireClient(player, "Playtime reward: " .. table.concat(parts, ", ") .. "!")
		end

		-- Send updated data to client
		local dataRemote = Remotes:FindFirstChild("PlaytimeRewardData")
		if dataRemote then
			dataRemote:FireClient(player, {
				joinTime = joinTime,
				serverTime = os.clock(),
				claimed = playerClaimed,
			})
		end
	end)
end

return PlaytimeRewards
