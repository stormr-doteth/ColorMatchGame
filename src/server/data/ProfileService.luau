local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Packages = ServerScriptService:WaitForChild("Packages")
local ProfileStore = require(Packages.ProfileStore)

local PROFILE_TEMPLATE = {
	Cash = 500, -- TODO: revert to 0 after testing
	Level = 1,
	XP = 0,
	Wins = 0,
	WinStreak = 0,
	Chairs = {} :: { string }, -- array of owned chair ids
	EquippedChair = "", -- "" means none equipped
}

local PlayerStore = ProfileStore.New("PlayerData", PROFILE_TEMPLATE)
local activeProfiles = {}
local started = false

-- Lazily resolved on first use so this module isn't sensitive to RemoteSetup
-- being initialised before ProfileService.
local playerDataUpdateRemote: RemoteEvent? = nil
local function getPlayerDataUpdateRemote(): RemoteEvent?
	if playerDataUpdateRemote then
		return playerDataUpdateRemote
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return nil
	end
	local remote = remotes:FindFirstChild("PlayerDataUpdate")
	if remote then
		playerDataUpdateRemote = remote :: RemoteEvent
	end
	return playerDataUpdateRemote
end

-- Push the player's current profile data to their client. Used after profile
-- load and after every cash/win mutation so the HUD reflects reality. Also
-- mirrors the win streak onto a Player attribute so it replicates to all
-- clients (used for the over-head streak BillboardGui).
local function notify(player: Player)
	local profile = activeProfiles[player]
	if not profile then
		return
	end
	player:SetAttribute("WinStreak", profile.Data.WinStreak or 0)
	local remote = getPlayerDataUpdateRemote()
	if not remote then
		return
	end
	remote:FireClient(player, profile.Data)
end

local ProfileService = {}

local function loadProfile(player)
	local profileKey = ("Player_%d"):format(player.UserId)
	local profile = PlayerStore:StartSessionAsync(profileKey, {
		Cancel = function()
			return player.Parent == nil
		end,
	})

	if profile == nil then
		player:Kick("Could not load your data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	-- Deduplicate Chairs array (cleans up any prior test pollution)
	local seen = {}
	local deduped = {}
	for _, id in profile.Data.Chairs do
		if not seen[id] then
			seen[id] = true
			table.insert(deduped, id)
		end
	end
	profile.Data.Chairs = deduped

	profile.OnSessionEnd:Connect(function()
		activeProfiles[player] = nil
		if player.Parent ~= nil then
			player:Kick("Your data session ended. Please rejoin.")
		end
	end)

	if player.Parent == nil then
		profile:EndSession()
		return
	end

	activeProfiles[player] = profile
	notify(player)
end

local function releaseProfile(player)
	local profile = activeProfiles[player]
	if profile ~= nil then
		profile:EndSession()
	end
end

function ProfileService.GetProfile(player)
	return activeProfiles[player]
end

function ProfileService.GetData(player)
	local profile = activeProfiles[player]
	if profile == nil then
		return nil
	end
	return profile.Data
end

function ProfileService.AddCash(player, amount)
	local profile = activeProfiles[player]
	if profile then
		profile.Data.Cash += amount
		notify(player)
	end
end

function ProfileService.AddWin(player)
	local profile = activeProfiles[player]
	if profile then
		profile.Data.Wins += 1
		profile.Data.WinStreak = (profile.Data.WinStreak or 0) + 1
		notify(player)
	end
end

function ProfileService.ResetStreak(player)
	local profile = activeProfiles[player]
	if profile then
		if (profile.Data.WinStreak or 0) == 0 then
			return
		end
		profile.Data.WinStreak = 0
		notify(player)
	end
end

function ProfileService.OwnsChair(player, chairId: string): boolean
	local profile = activeProfiles[player]
	if not profile then
		return false
	end
	for _, owned in profile.Data.Chairs do
		if owned == chairId then
			return true
		end
	end
	return false
end

-- Returns true if the chair was added (false if already owned).
function ProfileService.AddChair(player, chairId: string): boolean
	local profile = activeProfiles[player]
	if not profile then
		return false
	end
	for _, owned in profile.Data.Chairs do
		if owned == chairId then
			return false
		end
	end
	table.insert(profile.Data.Chairs, chairId)
	notify(player)
	return true
end

-- Sets the equipped chair. Pass an empty string to unequip. Returns true on
-- success. Validates that the player owns the requested chair.
function ProfileService.SetEquippedChair(player, chairId: string): boolean
	local profile = activeProfiles[player]
	if not profile then
		return false
	end
	if chairId == "" then
		if profile.Data.EquippedChair == "" then
			return true
		end
		profile.Data.EquippedChair = ""
		notify(player)
		return true
	end
	-- Owned check
	local owns = false
	for _, id in profile.Data.Chairs do
		if id == chairId then
			owns = true
			break
		end
	end
	if not owns then
		return false
	end
	if profile.Data.EquippedChair == chairId then
		return true
	end
	profile.Data.EquippedChair = chairId
	notify(player)
	return true
end

-- Returns the currently equipped chair id (or "" if none).
function ProfileService.GetEquippedChair(player): string
	local profile = activeProfiles[player]
	if not profile then
		return ""
	end
	return profile.Data.EquippedChair or ""
end

function ProfileService.Start()
	if started then
		return
	end
	started = true

	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	Players.PlayerAdded:Connect(loadProfile)
	Players.PlayerRemoving:Connect(releaseProfile)
end

return ProfileService
