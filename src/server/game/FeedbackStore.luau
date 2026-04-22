-- FeedbackStore
-- Collects player-submitted feedback via the SubmitFeedback remote and
-- persists each entry in the "PlayerFeedback_v1" DataStore. Keyed by
-- "feedback_<epochSeconds>_<userId>" so the dev can scan it by time.
-- Also maintains a small "recent" list at key "recent" (last 100 entries)
-- for quick inspection.

local DataStoreService = game:GetService("DataStoreService")

local RemoteSetup = require(script.Parent:WaitForChild("RemoteSetup"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))
local Analytics = require(script.Parent:WaitForChild("Analytics"))

local STORE_NAME = "PlayerFeedback_v1"
local RECENT_KEY = "recent"
local RECENT_MAX = 100
local MAX_LEN = 500
local MIN_LEN = 3

local FeedbackStore = {}

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function FeedbackStore.Init()
	local store = DataStoreService:GetDataStore(STORE_NAME)

	RemoteSetup.Get("SubmitFeedback").OnServerEvent:Connect(function(player, text)
		if typeof(text) ~= "string" then return end
		if not RateLimit.check("SubmitFeedback", player, 5) then return end

		text = trim(text)
		if #text < MIN_LEN then return end
		if #text > MAX_LEN then
			text = string.sub(text, 1, MAX_LEN)
		end

		local entry = {
			userId = player.UserId,
			username = player.Name,
			displayName = player.DisplayName,
			text = text,
			timestamp = os.time(),
			placeId = game.PlaceId,
		}

		Analytics.LogCustom(player, "FeedbackSubmitted", #text, nil, "lobby")

		task.spawn(function()
			local key = ("feedback_%d_%d"):format(entry.timestamp, entry.userId)
			local ok, err = pcall(function()
				store:SetAsync(key, entry)
			end)
			if not ok then
				warn("[FeedbackStore] SetAsync failed: " .. tostring(err))
				return
			end

			-- Append to the "recent" rolling list for easy dev scanning.
			local ok2, err2 = pcall(function()
				store:UpdateAsync(RECENT_KEY, function(old)
					local list = old or {}
					table.insert(list, 1, entry)
					while #list > RECENT_MAX do
						table.remove(list)
					end
					return list
				end)
			end)
			if not ok2 then
				warn("[FeedbackStore] recent UpdateAsync failed: " .. tostring(err2))
			end
		end)
	end)
end

return FeedbackStore
