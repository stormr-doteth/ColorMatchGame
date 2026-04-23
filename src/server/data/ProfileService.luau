local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Packages = ServerScriptService:WaitForChild("Packages")
local ProfileStore = require(Packages.ProfileStore)

local PROFILE_TEMPLATE = {
	Cash = 0,
	Wins = 0,
	WinStreak = 0,
	Chairs = {} :: { string },
	EquippedChair = "",
	LuckyBlocks = {} :: { [string]: number },
	Hints = 0, -- persistent hint inventory
	Matches = 0, -- persistent match-color inventory
	LastLoginReward = 0, -- os.time() of last claimed daily reward
	LoginStreak = 0, -- consecutive days logged in
	TotalLogins = 0,
	GroupRewardClaimed = false,
	VIPRewardClaimed = false,
	ProcessedReceipts = {} :: { [string]: boolean },
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
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		return nil
	end
	local remote = remotes:WaitForChild("PlayerDataUpdate", 10)
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

	-- Retry with exponential backoff if DataStore is temporarily unavailable.
	-- Without this, a brief DataStore hiccup kicks every connecting player.
	local profile = nil
	local backoffs = { 1, 3, 9 }
	for attempt = 0, #backoffs do
		if player.Parent == nil then return end
		profile = PlayerStore:StartSessionAsync(profileKey, {
			Cancel = function()
				return player.Parent == nil
			end,
		})
		if profile ~= nil then break end
		local delay = backoffs[attempt + 1]
		if delay then
			warn(("[ProfileService] Session load failed for %s, retrying in %ds"):format(player.Name, delay))
			task.wait(delay)
		end
	end

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

-- Push the player's current profile to their client on demand. Used by the
-- client-initiated RequestPlayerData sync so late-starting HUDs (inventory,
-- cash, wins) can pull the initial snapshot instead of racing the server's
-- post-load push.
function ProfileService.PushData(player: Player)
	notify(player)
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

function ProfileService.AddWins(player, amount: number)
	local profile = activeProfiles[player]
	if profile then
		profile.Data.Wins += amount
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

function ProfileService.AddHints(player, amount: number)
	local profile = activeProfiles[player]
	if profile and amount > 0 then
		profile.Data.Hints = (profile.Data.Hints or 0) + amount
		notify(player)
	end
end

function ProfileService.UseHint(player): boolean
	local profile = activeProfiles[player]
	if not profile then return false end
	local count = profile.Data.Hints or 0
	if count <= 0 then return false end
	profile.Data.Hints = count - 1
	notify(player)
	return true
end

function ProfileService.AddMatches(player, amount: number)
	local profile = activeProfiles[player]
	if profile and amount > 0 then
		profile.Data.Matches = (profile.Data.Matches or 0) + amount
		notify(player)
	end
end

function ProfileService.UseMatch(player): boolean
	local profile = activeProfiles[player]
	if not profile then return false end
	local count = profile.Data.Matches or 0
	if count <= 0 then return false end
	profile.Data.Matches = count - 1
	notify(player)
	return true
end

function ProfileService.AddLuckyBlock(player, blockId: string)
	local profile = activeProfiles[player]
	if profile then
		local blocks = profile.Data.LuckyBlocks
		blocks[blockId] = (blocks[blockId] or 0) + 1
		notify(player)
	end
end

-- Decrements the count of a lucky block type. Returns true if successful.
function ProfileService.UseLuckyBlock(player, blockId: string): boolean
	local profile = activeProfiles[player]
	if not profile then
		return false
	end
	local blocks = profile.Data.LuckyBlocks
	local count = blocks[blockId] or 0
	if count <= 0 then
		return false
	end
	blocks[blockId] = count - 1
	if blocks[blockId] == 0 then
		blocks[blockId] = nil
	end
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

-- Daily reward functions
function ProfileService.GetDailyRewardData(player): (number, number, number) -- lastReward, streak, totalLogins
	local profile = activeProfiles[player]
	if not profile then return 0, 0, 0 end
	return profile.Data.LastLoginReward or 0, profile.Data.LoginStreak or 0, profile.Data.TotalLogins or 0
end

function ProfileService.SetDailyRewardData(player, lastReward: number, streak: number, totalLogins: number)
	local profile = activeProfiles[player]
	if not profile then return end
	profile.Data.LastLoginReward = lastReward
	profile.Data.LoginStreak = streak
	profile.Data.TotalLogins = totalLogins
	notify(player)
end

-- Receipt idempotency: returns true if this receipt is newly recorded, false
-- if it was already processed (or the profile isn't loaded). ProcessReceipt
-- must check this BEFORE granting rewards so Roblox retries don't double-grant.
function ProfileService.TryRecordReceipt(player, receiptId: string): boolean
	local profile = activeProfiles[player]
	if not profile then
		return false
	end
	local processed = profile.Data.ProcessedReceipts
	if processed[receiptId] then
		return false
	end
	processed[receiptId] = true
	return true
end

-- Force-flush the profile to DataStore. Use after a monetised grant so we
-- don't ack PurchaseGranted before the data actually persists. Returns
-- true if the save landed (or appeared to).
function ProfileService.SaveProfile(player): boolean
	local profile = activeProfiles[player]
	if not profile then
		return false
	end
	local ok, err = pcall(function()
		profile:Save()
	end)
	if not ok then
		warn(("[ProfileService] SaveProfile failed for %s: %s"):format(player.Name, tostring(err)))
		return false
	end
	return true
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

	-- Belt-and-suspenders BindToClose: ProfileStore already handles session
	-- release on shutdown, but explicitly ending every active session here
	-- guarantees Roblox waits for saves to flush before terminating the
	-- server process. Roblox gives us up to 30s here before a hard kill.
	game:BindToClose(function()
		for player, _ in activeProfiles do
			task.spawn(releaseProfile, player)
		end
		-- Wait until every active profile has been drained (or we run out
		-- of time). ProfileStore's EndSession triggers an async save, so
		-- poll the map rather than assuming a fixed delay.
		local deadline = os.clock() + 25
		while next(activeProfiles) and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return ProfileService
