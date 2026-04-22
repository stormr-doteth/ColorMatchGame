-- ChairTestHarness (dev tool)
-- Lets you cycle through every chair in ChairCatalog to visually verify each
-- one seats correctly (no wrong-facing / off-center models).
--
-- Usage (in chat, as game owner):
--   /chairtest              -- grants every chair and equips the first one
--   /chairnext              -- equips the next chair in the catalog
--   /chairprev              -- equips the previous chair
--   /chairgoto <id>         -- equip a specific chair by id
--   /chairflip              -- toggle flipSeat on the current chair at runtime
--                              (lets you preview the fix; then edit ChairCatalog)
--   /chairflipseat          -- toggle flipSeatDirection (rotates ONLY the Seat;
--                              fixes player-faces-wrong-way while body is correct)
--   /chairlog               -- print the current chair id + flip state
--
-- After you identify broken chairs, edit src/shared/ChairCatalog.luau to add
-- or remove `flipSeat = true` on the offending entries.
--
-- NOTE: This harness is only active in Studio / for the game creator. It does
-- not expose anything to regular players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))
local ProfileService = require(script.Parent.Parent:WaitForChild("data"):WaitForChild("ProfileService"))

local ChairTestHarness = {}

local playerIndex: { [Player]: number } = {}
local runtimeFlipOverride: { [string]: boolean } = {}

local function isAuthorized(player: Player): boolean
	-- Allow in Studio, or if the player is the game creator.
	if RunService:IsStudio() then return true end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return false
end

local function grantAll(player: Player)
	for _, entry in ChairCatalog.GetAll() do
		ProfileService.AddChair(player, entry.id)
	end
end

local function equipAt(player: Player, index: number)
	local entries = ChairCatalog.GetAll()
	if #entries == 0 then return end
	index = ((index - 1) % #entries) + 1
	playerIndex[player] = index
	local entry = entries[index]
	ProfileService.SetEquippedChair(player, entry.id)
	print(string.format(
		"[ChairTest] #%d/%d  id=%s  model=%s  flipSeat=%s  flipSeatDirection=%s",
		index, #entries, entry.id, entry.modelName,
		tostring(entry.flipSeat == true), tostring(entry.flipSeatDirection == true)
	))
end

local function findIndexById(id: string): number?
	for i, entry in ChairCatalog.GetAll() do
		if entry.id == id then return i end
	end
	return nil
end

local function handleCommand(player: Player, text: string)
	if not isAuthorized(player) then return end
	local lower = string.lower(text)

	if lower == "/chairtest" then
		grantAll(player)
		equipAt(player, 1)
	elseif lower == "/chairnext" then
		equipAt(player, (playerIndex[player] or 0) + 1)
	elseif lower == "/chairprev" then
		equipAt(player, (playerIndex[player] or 2) - 1)
	elseif lower == "/chairlog" then
		local idx = playerIndex[player]
		if not idx then print("[ChairTest] no current chair") return end
		local entry = ChairCatalog.GetAll()[idx]
		print(string.format(
			"[ChairTest] current id=%s  flipSeat=%s  (override=%s)",
			entry.id, tostring(entry.flipSeat == true),
			tostring(runtimeFlipOverride[entry.id])
		))
	elseif string.sub(lower, 1, 10) == "/chairgoto" then
		local target = string.match(text, "^/chairgoto%s+(%S+)")
		if target then
			local idx = findIndexById(target)
			if idx then
				equipAt(player, idx)
			else
				print("[ChairTest] unknown id: " .. target)
			end
		end
	elseif lower == "/chairflip" then
		local idx = playerIndex[player]
		if not idx then return end
		local entry = ChairCatalog.GetAll()[idx]
		entry.flipSeat = not (entry.flipSeat == true)
		runtimeFlipOverride[entry.id] = entry.flipSeat
		print(string.format(
			"[ChairTest] toggled flipSeat for %s -> %s  (edit ChairCatalog.luau to persist)",
			entry.id, tostring(entry.flipSeat)
		))
		equipAt(player, idx)
	elseif lower == "/chairflipseat" then
		local idx = playerIndex[player]
		if not idx then return end
		local entry = ChairCatalog.GetAll()[idx]
		entry.flipSeatDirection = not (entry.flipSeatDirection == true)
		print(string.format(
			"[ChairTest] toggled flipSeatDirection for %s -> %s  (edit ChairCatalog.luau to persist)",
			entry.id, tostring(entry.flipSeatDirection)
		))
		equipAt(player, idx)
	end
end

function ChairTestHarness.Init()
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg) handleCommand(player, msg) end)
	end)
	for _, player in Players:GetPlayers() do
		player.Chatted:Connect(function(msg) handleCommand(player, msg) end)
	end
	print("[ChairTestHarness] loaded. Use /chairtest to begin.")
end

return ChairTestHarness
