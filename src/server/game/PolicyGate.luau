-- PolicyGate
-- Wraps Roblox PolicyService. Caches per-player policy info and mirrors the
-- `ArePaidRandomItemsRestricted` flag onto a Player attribute so the client
-- UI can hide paid random-item purchase buttons for affected players (e.g.
-- Belgium, Netherlands) without an extra round-trip.
--
-- Fail-safe: if PolicyService throws, we assume the player IS restricted —
-- shipping loot-box purchases to a restricted region carries real
-- regulatory risk; skipping a sale is strictly safer than allowing one.
--
-- Reference:
-- https://create.roblox.com/docs/reference/engine/classes/PolicyService

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local PolicyGate = {}

local ATTR = "ArePaidRandomItemsRestricted"

local cache: { [Player]: boolean } = {}

local function fetch(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)

	local restricted: boolean
	if ok and typeof(info) == "table" then
		restricted = info.ArePaidRandomItemsRestricted == true
	else
		warn(("[PolicyGate] PolicyService failed for %s: %s — defaulting to restricted"):format(player.Name, tostring(info)))
		restricted = true
	end

	cache[player] = restricted
	if player.Parent then
		player:SetAttribute(ATTR, restricted)
	end
end

-- Authoritative server-side check. Lazily fetches if PlayerAdded race beats
-- the caller.
function PolicyGate.IsPaidRandomRestricted(player: Player): boolean
	if cache[player] == nil then
		fetch(player)
	end
	return cache[player] == true
end

function PolicyGate.Init()
	for _, p in Players:GetPlayers() do
		task.spawn(fetch, p)
	end
	Players.PlayerAdded:Connect(function(p)
		task.spawn(fetch, p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		cache[p] = nil
	end)
end

return PolicyGate
