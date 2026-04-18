--!strict
-- DailyRewards
-- Plug-and-play daily login rewards for Roblox. Consumer supplies a profile
-- adapter + a pair of RemoteEvents via `DailyRewards.new(config)`.
--
-- Rewards cycle every N days (default 7). Streak breaks if the player misses
-- more than 48h. Each reward can contain any mix of fields your adapter
-- understands (cash, hint, match, luckyBlock) — extra/unknown fields are
-- ignored, so you can extend reward shapes without forking this module.

local Players = game:GetService("Players")

local ONE_DAY = 86400
local TWO_DAYS = 172800

export type RewardEntry = {
	cash: number?,
	hint: number?,
	match: number?,
	luckyBlock: string?,
}

-- Profile adapter — wire these to whatever data system you use (ProfileStore,
-- DataStore, in-memory, etc.). Only `isLoaded`, `getData`, and `setData` are
-- required; the reward grant callbacks are optional but you'll want at least
-- one of them for rewards to actually do anything.
export type ProfileAdapter = {
	isLoaded: (player: Player) -> boolean,
	getData: (player: Player) -> (number, number, number), -- lastReward, streak, totalLogins
	setData: (player: Player, lastReward: number, streak: number, totalLogins: number) -> (),
	addCash: ((player: Player, amount: number) -> ())?,
	addHints: ((player: Player, amount: number) -> ())?,
	addMatches: ((player: Player, amount: number) -> ())?,
	addLuckyBlock: ((player: Player, blockId: string) -> ())?,
	-- Optional multiplier applied to cash rewards (e.g., VIP pass = 2).
	cashMultiplier: ((player: Player) -> number)?,
}

export type Config = {
	profile: ProfileAdapter,
	dataRemote: RemoteEvent, -- server fires this to push state to clients
	claimRemote: RemoteEvent, -- clients fire this to request a claim
	dayRewards: { RewardEntry }?,
	notify: ((player: Player, message: string) -> ())?,
}

local DEFAULT_REWARDS: { RewardEntry } = {
	{ cash = 75 },
	{ cash = 150 },
	{ cash = 250 },
	{ cash = 400 },
	{ cash = 600 },
	{ cash = 900 },
	{ cash = 1500 },
}

local DailyRewards = {}
DailyRewards.__index = DailyRewards

export type DailyRewards = typeof(setmetatable(
	{} :: {
		profile: ProfileAdapter,
		dataRemote: RemoteEvent,
		claimRemote: RemoteEvent,
		rewards: { RewardEntry },
		notify: ((player: Player, message: string) -> ())?,
	},
	DailyRewards
))

function DailyRewards.new(config: Config): DailyRewards
	assert(config and config.profile, "DailyRewards.new: config.profile is required")
	assert(config.dataRemote, "DailyRewards.new: config.dataRemote is required")
	assert(config.claimRemote, "DailyRewards.new: config.claimRemote is required")

	local self = setmetatable({
		profile = config.profile,
		dataRemote = config.dataRemote,
		claimRemote = config.claimRemote,
		rewards = config.dayRewards or DEFAULT_REWARDS,
		notify = config.notify,
	}, DailyRewards)

	local function onPlayerAdded(player: Player)
		task.defer(function()
			local attempts = 0
			while not self.profile.isLoaded(player) and attempts < 30 do
				task.wait(0.5)
				attempts += 1
			end
			if not self.profile.isLoaded(player) then return end
			self:CheckAndNotify(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	self.claimRemote.OnServerEvent:Connect(function(player)
		self:Claim(player)
	end)

	return self
end

function DailyRewards.CheckAndNotify(self: DailyRewards, player: Player)
	if not self.profile.isLoaded(player) then return end
	local lastReward, streak = self.profile.getData(player)
	local now = os.time()
	local elapsed = now - lastReward

	local currentDay = streak
	if elapsed >= TWO_DAYS then
		currentDay = 0
	end

	local nextDay = (currentDay % #self.rewards) + 1
	local canClaim = elapsed >= ONE_DAY or lastReward == 0

	self.dataRemote:FireClient(player, {
		canClaim = canClaim,
		currentStreak = currentDay,
		nextDay = nextDay,
		reward = self.rewards[nextDay],
		dayRewards = self.rewards,
	})
end

function DailyRewards.Claim(self: DailyRewards, player: Player)
	if not self.profile.isLoaded(player) then return end
	local lastReward, streak, totalLogins = self.profile.getData(player)
	local now = os.time()
	local elapsed = now - lastReward

	if elapsed < ONE_DAY and lastReward ~= 0 then return end
	if elapsed >= TWO_DAYS and lastReward ~= 0 then
		streak = 0
	end

	streak += 1
	totalLogins += 1

	local dayIndex = ((streak - 1) % #self.rewards) + 1
	local reward = self.rewards[dayIndex]

	local multiplier = 1
	if self.profile.cashMultiplier then
		multiplier = self.profile.cashMultiplier(player) or 1
	end

	local grantedCash = 0
	if reward.cash and self.profile.addCash then
		grantedCash = reward.cash * multiplier
		self.profile.addCash(player, grantedCash)
	end
	if reward.hint and self.profile.addHints then
		self.profile.addHints(player, reward.hint)
	end
	if reward.match and self.profile.addMatches then
		self.profile.addMatches(player, reward.match)
	end
	if reward.luckyBlock and self.profile.addLuckyBlock then
		self.profile.addLuckyBlock(player, reward.luckyBlock)
	end

	self.profile.setData(player, now, streak, totalLogins)
	self:CheckAndNotify(player)

	if self.notify then
		local parts = {}
		if grantedCash > 0 then table.insert(parts, `+${grantedCash} Cash`) end
		if reward.hint then table.insert(parts, `+{reward.hint} Hint`) end
		if reward.match then table.insert(parts, `+{reward.match} Match`) end
		if reward.luckyBlock then table.insert(parts, "+1 Lucky Block") end
		self.notify(player, `Day {dayIndex} reward: ` .. table.concat(parts, ", ") .. "!")
	end
end

return DailyRewards
