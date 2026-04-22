-- Per-player, per-bucket cooldown. Returns true if allowed, false if rate-limited.
-- Buckets isolate different remotes so unrelated spammy clients don't starve
-- each other (e.g. UseHint and PurchaseChair have independent cooldowns).

local Players = game:GetService("Players")

local RateLimit = {}

local lastCall: { [string]: { [Player]: number } } = {}

function RateLimit.check(bucket: string, player: Player, cooldown: number): boolean
	local bucketMap = lastCall[bucket]
	if not bucketMap then
		bucketMap = {}
		lastCall[bucket] = bucketMap
	end
	local now = os.clock()
	local prev = bucketMap[player]
	if prev and (now - prev) < cooldown then
		return false
	end
	bucketMap[player] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	for _, bucketMap in lastCall do
		bucketMap[player] = nil
	end
end)

return RateLimit
