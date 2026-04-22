-- GamePassUtil
-- Cached game pass ownership checks. Call HasPass(player, "DOUBLE_CASH") etc.
-- Cache is invalidated on purchase so effects take effect immediately.

local MarketplaceService = game:GetService("MarketplaceService")

local PASS_IDS = {
	DOUBLE_CASH = 1797672278,
	DOUBLE_WINS = 1796963414,
	DOUBLE_STREAK = 1797239408,
	VIP = 1796710377,
	STARTER_PACK = 1796993729,
}

local cache: { [string]: boolean } = {}

local GamePassUtil = {}

function GamePassUtil.HasPass(player: Player, passName: string): boolean
	local passId = PASS_IDS[passName]
	if not passId then return false end
	local key = tostring(player.UserId) .. "_" .. tostring(passId)
	if cache[key] ~= nil then return cache[key] end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	local result = ok and owns or false
	cache[key] = result
	return result
end

function GamePassUtil.InvalidateCache(player: Player)
	local prefix = tostring(player.UserId) .. "_"
	for key, _ in cache do
		if string.sub(key, 1, #prefix) == prefix then
			cache[key] = nil
		end
	end
end

function GamePassUtil.InvalidatePass(player: Player, passName: string)
	local passId = PASS_IDS[passName]
	if not passId then return end
	local key = tostring(player.UserId) .. "_" .. tostring(passId)
	cache[key] = nil
end

function GamePassUtil.GetPassId(passName: string): number?
	return PASS_IDS[passName]
end

-- Sync boost attributes on the player so clients can react to ownership
-- (BoostIconsHud reads these). Safe to call repeatedly.
local BOOST_ATTRS = {
	Boost_DoubleCash = "DOUBLE_CASH",
	Boost_DoubleWins = "DOUBLE_WINS",
	Boost_DoubleStreak = "DOUBLE_STREAK",
	Boost_VIP = "VIP",
}

function GamePassUtil.SyncBoostAttributes(player: Player)
	task.spawn(function()
		for attr, passName in BOOST_ATTRS do
			player:SetAttribute(attr, GamePassUtil.HasPass(player, passName))
		end
	end)
end

-- Mark a pass as owned immediately (bypasses the UserOwnsGamePassAsync
-- web query, which can return stale `false` for a few seconds right after a
-- successful purchase). Seeds the cache and flips the matching boost
-- attribute so downstream HUDs update instantly.
function GamePassUtil.MarkOwned(player: Player, passName: string)
	local passId = PASS_IDS[passName]
	if not passId then return end
	local key = tostring(player.UserId) .. "_" .. tostring(passId)
	cache[key] = true
	for attr, name in BOOST_ATTRS do
		if name == passName then
			player:SetAttribute(attr, true)
		end
	end
end

return GamePassUtil
