-- WinsLeaderboard / StreakLeaderboard
-- Generic all-time OrderedDataStore-backed leaderboard used for both the
-- wins and the streak billboards in Workspace.Leaderboard.
--
-- Create an instance with Leaderboards.new({ storeName, remoteName }) and
-- call :Record(player, value) whenever the tracked stat changes. The module
-- coalesces rapid updates, periodically refreshes the top N from the store,
-- and broadcasts to clients over the configured RemoteEvent.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOP_N = 100
local REFRESH_INTERVAL = 60
local BROADCAST_DEBOUNCE = 3

local Leaderboard = {}
Leaderboard.__index = Leaderboard

export type Config = {
	storeName: string,
	remoteName: string,
}

function Leaderboard.new(cfg: Config)
	local self = setmetatable({}, Leaderboard)
	self.cfg = cfg
	self.pendingBroadcast = false
	self.cachedTop = {}
	return self
end

local function nameFromUserId(userId: number): string
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return ok and name or ("Player" .. userId)
end

function Leaderboard:_fetchTop()
	local store = DataStoreService:GetOrderedDataStore(self.cfg.storeName)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok or not pages then
		warn("[" .. self.cfg.storeName .. "] GetSortedAsync failed")
		return self.cachedTop
	end

	local entries = {}
	local ok2, err = pcall(function()
		for _, row in pages:GetCurrentPage() do
			local uid = tonumber(row.key)
			local value = tonumber(row.value) or 0
			if uid then
				table.insert(entries, {
					userId = uid,
					username = nameFromUserId(uid),
					value = value,
				})
			end
		end
	end)
	if not ok2 then
		warn("[" .. self.cfg.storeName .. "] page walk failed: " .. tostring(err))
		return self.cachedTop
	end
	return entries
end

function Leaderboard:_broadcast(targetPlayer: Player?)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild(self.cfg.remoteName)
	if not remote then return end
	if targetPlayer then
		(remote :: RemoteEvent):FireClient(targetPlayer, self.cachedTop)
	else
		(remote :: RemoteEvent):FireAllClients(self.cachedTop)
	end
end

function Leaderboard:RefreshAndBroadcast()
	task.spawn(function()
		self.cachedTop = self:_fetchTop()
		self:_broadcast(nil)
	end)
end

function Leaderboard:Record(player: Player, value: number)
	task.spawn(function()
		local store = DataStoreService:GetOrderedDataStore(self.cfg.storeName)
		local ok, err = pcall(function()
			store:SetAsync(tostring(player.UserId), value)
		end)
		if not ok then
			warn("[" .. self.cfg.storeName .. "] SetAsync failed: " .. tostring(err))
			return
		end
		if self.pendingBroadcast then return end
		self.pendingBroadcast = true
		task.delay(BROADCAST_DEBOUNCE, function()
			self.pendingBroadcast = false
			self:RefreshAndBroadcast()
		end)
	end)
end

function Leaderboard:Init()
	self:RefreshAndBroadcast()
	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			self:RefreshAndBroadcast()
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		if #self.cachedTop > 0 then
			self:_broadcast(player)
		end
	end)
end

-- Module singletons for the two boards we actually care about.
local M = {}

M.Wins = Leaderboard.new({
	storeName = "WinsLeaderboard_v1",
	remoteName = "WinsLeaderboardUpdate",
})

M.Streak = Leaderboard.new({
	storeName = "StreakLeaderboard_v1",
	remoteName = "StreakLeaderboardUpdate",
})

-- Back-compat shim: old code calls WinsLeaderboard.Init() / Record(player,n).
function M.Init()
	M.Wins:Init()
	M.Streak:Init()
end

function M.Record(player: Player, wins: number)
	M.Wins:Record(player, wins)
end

function M.RecordStreak(player: Player, streak: number)
	M.Streak:Record(player, streak)
end

return M
