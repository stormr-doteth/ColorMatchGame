-- Analytics
-- Thin wrapper around AnalyticsService. Centralizes every analytics call so
-- event names, flow types, and custom-field keys stay consistent and we can
-- add/remove metadata in one place.
--
-- Event catalog:
--   LogEconomy(player, flowType, currency, amount, endingBalance, txType, sku)
--   LogCustom(player, eventName, value, fields)
--   LogOnboarding(player, step, stepName, fields)  -- one-shot new-player funnel
--
-- CustomFields we attach on most events (built-in keys are CustomField01/02/03):
--   01 = game mode (solo / 1v1)
--   02 = player segment (new / returning / whale)
--   03 = active boosts bitmask string (e.g. "VIP+2xCash")

local AnalyticsService = game:GetService("AnalyticsService")
local ProfileService = require(script.Parent.Parent.data.ProfileService)
local GamePassUtil = require(script.Parent.GamePassUtil)

local Analytics = {}

local function getBalance(player: Player): number
	local data = ProfileService.GetData(player)
	return data and data.Cash or 0
end

local function activeBoosts(player: Player): string
	local parts = {}
	if GamePassUtil.HasPass(player, "VIP") then table.insert(parts, "VIP") end
	if GamePassUtil.HasPass(player, "DOUBLE_CASH") then table.insert(parts, "2xCash") end
	if GamePassUtil.HasPass(player, "DOUBLE_WINS") then table.insert(parts, "2xWins") end
	if GamePassUtil.HasPass(player, "DOUBLE_STREAK") then table.insert(parts, "2xStreak") end
	if #parts == 0 then return "none" end
	return table.concat(parts, "+")
end

local function playerSegment(player: Player): string
	local data = ProfileService.GetData(player)
	if not data then return "unknown" end
	local wins = data.Wins or 0
	if wins == 0 then return "new" end
	if wins < 10 then return "early" end
	if wins < 100 then return "returning" end
	return "veteran"
end

local function buildFields(player: Player, mode: string?): { [string]: string }
	return {
		CustomField01 = mode or "lobby",
		CustomField02 = playerSegment(player),
		CustomField03 = activeBoosts(player),
	}
end

-- Economy ---------------------------------------------------------------

-- flowType: "Source" or "Sink" — pass the AnalyticsEconomyFlowType enum value.
-- currency: "Cash" (soft) or "Robux" (hard)
-- txType: one of the AnalyticsEconomyTransactionType enum values (as string)
-- sku:    identifier for the item/reward, e.g. "chair_office_chair"
function Analytics.LogEconomy(player: Player, flow: string, currency: string, amount: number, txType: string, sku: string, mode: string?)
	local ok, err = pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType[flow],
			currency,
			amount,
			getBalance(player),
			Enum.AnalyticsEconomyTransactionType[txType].Name,
			sku,
			buildFields(player, mode)
		)
	end)
	if not ok then
		warn("[Analytics] Economy log failed: " .. tostring(err))
	end
end

-- Custom ---------------------------------------------------------------

function Analytics.LogCustom(player: Player, eventName: string, value: number?, fields: { [string]: string }?, mode: string?)
	local merged = buildFields(player, mode)
	if fields then
		for k, v in fields do
			merged[k] = v
		end
	end
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1, merged)
	end)
	if not ok then
		warn("[Analytics] Custom log failed: " .. tostring(err))
	end
end

-- Onboarding funnel (built-in, one per player lifetime) ---------------
-- Steps are integers 1..N, each fired once as the player progresses.
-- We use: 1=Joined, 2=Seated, 3=MatchStarted, 4=FirstMatchWon

local onboardingFired: { [number]: { [number]: boolean } } = {}

function Analytics.LogOnboarding(player: Player, step: number, stepName: string)
	local fired = onboardingFired[player.UserId]
	if not fired then
		fired = {}
		onboardingFired[player.UserId] = fired
	end
	if fired[step] then return end
	fired[step] = true

	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, buildFields(player, nil))
	end)
	if not ok then
		warn("[Analytics] Onboarding log failed: " .. tostring(err))
	end
end

function Analytics.Init()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		onboardingFired[player.UserId] = nil
	end)
end

return Analytics
