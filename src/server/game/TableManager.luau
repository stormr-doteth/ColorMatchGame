local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local MatchController = require(script.Parent.MatchController)
local SoloMatchController = require(script.Parent.SoloMatchController)
local ChairShop = require(script.Parent.ChairShop)
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))
local ProfileService = require(script.Parent.Parent:WaitForChild("data"):WaitForChild("ProfileService"))

local TableManager = {}

local tables = {} -- tableId -> TableState
local playerToTable = {} -- Player -> tableId

-- Lazy remote refs
local PlayerSeatedRemote
local LeaveTableRemote

local function getRemote(name: string): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then return nil end
	return remotes:WaitForChild(name, 10)
end

local function createBillboard(tablePart: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TableBillboard"
	billboard.Size = UDim2.new(6, 0, 2.5, 0) -- studs-based, scales with distance
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 50
	billboard.Adornee = tablePart
	billboard.Parent = tablePart

	local playerCount = Instance.new("TextLabel")
	playerCount.Name = "PlayerCount"
	playerCount.Size = UDim2.new(1, 0, 0.55, 0)
	playerCount.Position = UDim2.fromScale(0, 0)
	playerCount.BackgroundTransparency = 1
	playerCount.Text = "0/2 Players"
	playerCount.TextColor3 = Color3.fromRGB(255, 255, 255)
	playerCount.TextScaled = true
	playerCount.Font = Enum.Font.FredokaOne
	playerCount.Parent = billboard

	local playerCountStroke = Instance.new("UIStroke")
	playerCountStroke.Thickness = 2
	playerCountStroke.Color = Color3.fromRGB(0, 0, 0)
	playerCountStroke.Parent = playerCount

	local reward = Instance.new("TextLabel")
	reward.Name = "Reward"
	reward.Size = UDim2.new(1, 0, 0.4, 0)
	reward.Position = UDim2.fromScale(0, 0.55)
	reward.BackgroundTransparency = 1
	reward.Text = `Win ${Constants.WIN_REWARD}`
	reward.TextColor3 = Color3.fromRGB(50, 255, 50)
	reward.TextScaled = true
	reward.Font = Enum.Font.FredokaOne
	reward.Parent = billboard

	local rewardStroke = Instance.new("UIStroke")
	rewardStroke.Thickness = 1.5
	rewardStroke.Color = Color3.fromRGB(0, 0, 0)
	rewardStroke.Parent = reward

	return billboard, playerCount
end

local function getPlayerCount(tableState)
	local count = 0
	for _, chair in tableState.chairs do
		if chair.player then
			count += 1
		end
	end
	return count
end

local function updateBillboard(tableState)
	local count = getPlayerCount(tableState)
	local max = tableState.maxPlayers or 2
	if max == 1 then
		tableState.playerCountLabel.Text = if count > 0 then "In Use" else "Solo Practice"
	else
		tableState.playerCountLabel.Text = `{count}/{max} Players`
	end
end

local function findSeat(chairModel): Seat?
	if chairModel:IsA("Seat") then
		return chairModel
	end
	return chairModel:FindFirstChildWhichIsA("Seat", true)
end

-- Apply the player's equipped chair skin to this chair slot. Hides every
-- BasePart of the original chair, spawns a clone of the equipped chair model
-- positioned so its Seat lines up with the original Seat, and returns the
-- clone (or the original chair Model when no skin is equipped).
local function applyChairSkin(chair, player)
	local equipped = ProfileService.GetEquippedChair(player)
	if equipped == "" then
		return chair.part
	end
	local clone = ChairShop.CloneChair(equipped)
	if not clone then
		return chair.part
	end

	local cloneSeat = findSeat(clone)
	local originalSeat = findSeat(chair.part)
	if not cloneSeat or not originalSeat then
		clone:Destroy()
		return chair.part
	end

	-- Pivot clone so its Seat sits exactly where the original Seat was.
	clone.PrimaryPart = cloneSeat
	local targetCFrame = originalSeat.CFrame
	local entry = ChairCatalog.Get(equipped)
	if entry and entry.flipSeat then
		targetCFrame = targetCFrame * CFrame.Angles(0, math.pi, 0)
	end
	clone:PivotTo(targetCFrame)

	-- Rotate ONLY the Seat 180° so the player sits facing the opposite
	-- direction. Use when the chair body faces correctly but the Seat was
	-- authored reversed. Skips WeldConstraints targeting the Seat so the body
	-- doesn't drag with the rotation.
	if entry and entry.flipSeatDirection then
		local disabled = {}
		for _, desc in clone:GetDescendants() do
			if desc:IsA("WeldConstraint") then
				if desc.Part0 == cloneSeat or desc.Part1 == cloneSeat then
					if desc.Enabled then
						desc.Enabled = false
						table.insert(disabled, desc)
					end
				end
			end
		end
		cloneSeat.CFrame = cloneSeat.CFrame * CFrame.Angles(0, math.pi, 0)
		for _, wc in disabled do
			wc.Enabled = true
		end
	end

	-- Ground-snap: align the clone's lowest visible point to the original
	-- chair's lowest visible point so chairs don't float (throne with a short
	-- body + tall seat) or clip (chair with a tall body + low seat). Uses the
	-- true world-space AABB per part (8 rotated corners) since many throne
	-- parts are tilted.
	local function lowestVisibleY(root: Instance): number
		local y = math.huge
		local parts = if root:IsA("BasePart") then { root } else (root :: Model):GetDescendants()
		for _, d in parts do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local cf = d.CFrame
				local sx, sy, sz = d.Size.X / 2, d.Size.Y / 2, d.Size.Z / 2
				for ix = -1, 1, 2 do
					for iy = -1, 1, 2 do
						for iz = -1, 1, 2 do
							local corner = cf * Vector3.new(ix * sx, iy * sy, iz * sz)
							if corner.Y < y then y = corner.Y end
						end
					end
				end
			end
		end
		return y
	end
	local origBottom = lowestVisibleY(chair.part)
	local cloneBottom = lowestVisibleY(clone)
	if origBottom ~= math.huge and cloneBottom ~= math.huge then
		local dy = origBottom - cloneBottom
		if math.abs(dy) > 0.01 then
			clone:PivotTo(clone:GetPivot() + Vector3.new(0, dy, 0))
		end
	end

	-- Per-chair manual Y offset for chairs whose "lowest visible part"
	-- lands on an invisible anchor/hitbox lower than the visible mesh.
	if entry and entry.yOffset and entry.yOffset ~= 0 then
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, entry.yOffset, 0))
	end

	-- Hide every BasePart of the original chair (transparency + collision off)
	-- and disable the original Seat so the player can't auto-snap into it.
	local hidden = {}
	if chair.part:IsA("Model") then
		for _, descendant in chair.part:GetDescendants() do
			if descendant:IsA("BasePart") then
				hidden[descendant] = {
					transparency = descendant.Transparency,
					canCollide = descendant.CanCollide,
				}
				descendant.Transparency = 1
				descendant.CanCollide = false
				if descendant:IsA("Seat") then
					hidden[descendant].seatDisabled = descendant.Disabled
					descendant.Disabled = true
				end
			end
		end
	elseif chair.part:IsA("BasePart") then
		hidden[chair.part] = {
			transparency = chair.part.Transparency,
			canCollide = chair.part.CanCollide,
		}
		chair.part.Transparency = 1
		chair.part.CanCollide = false
		if chair.part:IsA("Seat") then
			hidden[chair.part].seatDisabled = chair.part.Disabled
			chair.part.Disabled = true
		end
	end

	clone.Parent = chair.part.Parent
	chair.swap = { clone = clone, hidden = hidden }
	return clone
end

local function removeChairSkin(chair)
	if not chair.swap then
		return
	end
	if chair.swap.clone then
		chair.swap.clone:Destroy()
	end
	for part, restore in chair.swap.hidden do
		if part.Parent then
			part.Transparency = restore.transparency
			part.CanCollide = restore.canCollide
			if part:IsA("Seat") and restore.seatDisabled ~= nil then
				part.Disabled = restore.seatDisabled
			end
		end
	end
	chair.swap = nil
end

local function seatPlayerInChair(player: Player, chairModel)
	local seat = findSeat(chairModel)
	if not seat then
		warn("[TableManager] No Seat found inside", chairModel:GetFullName())
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	seat:Sit(humanoid)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.UseJumpPower = true
end

local function kickFromSeat(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
		humanoid.Sit = false
		humanoid.Jump = true
	end
end

local function seatPlayer(tableId: string, player: Player)
	local tableState = tables[tableId]
	if not tableState then
		return
	end

	-- Already seated elsewhere?
	if playerToTable[player] then
		return
	end

	-- Find first empty chair
	local chairIndex
	for i, chair in tableState.chairs do
		if not chair.player then
			chairIndex = i
			break
		end
	end

	if not chairIndex then
		return -- Table full
	end

	local chair = tableState.chairs[chairIndex]
	chair.player = player
	playerToTable[player] = tableId

	-- Apply equipped chair skin (if any) and seat the player in whichever
	-- chair model ends up in place — the skinned clone if there's one,
	-- otherwise the original chair.
	local activeChair = applyChairSkin(chair, player)
	seatPlayerInChair(player, activeChair)

	local count = getPlayerCount(tableState)
	updateBillboard(tableState)

	local maxPlayers = tableState.maxPlayers or 2

	-- Disable prompt if table is full
	if count >= maxPlayers then
		tableState.prompt.Enabled = false
	end

	-- Notify client they're seated
	PlayerSeatedRemote:FireClient(player, {
		tableId = tableId,
		playerCount = count,
		maxPlayers = maxPlayers,
		solo = maxPlayers == 1,
	})

	local Analytics = require(script.Parent:WaitForChild("Analytics"))
	Analytics.LogOnboarding(player, 2, "Seated")
	Analytics.LogCustom(player, "TableSeated", 1, {
		CustomField04 = if maxPlayers == 1 then "solo" else "1v1",
	}, if maxPlayers == 1 then "solo" else "1v1")

	-- Start match when table is full
	if maxPlayers == 1 and count == 1 then
		-- Solo mode — start immediately
		local match = SoloMatchController.new(player, function()
			resetTable(tableId)
		end)

		tableState.match = match
		task.spawn(function()
			match:Start()
		end)
	elseif maxPlayers == 2 and count == 2 then
		local p1 = tableState.chairs[1].player
		local p2 = tableState.chairs[2].player

		local match = MatchController.new(p1, p2, function()
			resetTable(tableId)
		end, tableState.model, tableState.billboard)

		tableState.match = match
		task.spawn(function()
			match:Start()
		end)
	end
end

local function unseatPlayer(tableId: string, player: Player)
	local tableState = tables[tableId]
	if not tableState then
		return
	end

	for _, chair in tableState.chairs do
		if chair.player == player then
			chair.player = nil
			removeChairSkin(chair)
			break
		end
	end

	playerToTable[player] = nil
	kickFromSeat(player)

	-- Re-enable prompt if table has space
	local count = getPlayerCount(tableState)
	if count < (tableState.maxPlayers or 2) then
		tableState.prompt.Enabled = true
	end

	updateBillboard(tableState)
end

function resetTable(tableId: string)
	local tableState = tables[tableId]
	if not tableState then
		return
	end

	tableState.match = nil

	for _, chair in tableState.chairs do
		if chair.player then
			local player = chair.player
			chair.player = nil
			playerToTable[player] = nil
			kickFromSeat(player)
		end
		removeChairSkin(chair)
	end

	tableState.prompt.Enabled = true
	updateBillboard(tableState)
end

function TableManager.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	PlayerSeatedRemote = remotes:WaitForChild("PlayerSeated")
	LeaveTableRemote = remotes:WaitForChild("LeaveTable")

	local tablesFolder = workspace:WaitForChild("Tables", 5)
	local soloFolder = workspace:FindFirstChild("SoloTables")
	if not tablesFolder and not soloFolder then
		warn("[TableManager] No Tables or SoloTables folder found in Workspace")
		return
	end

	local allTableModels = {}
	if tablesFolder then
		for _, m in tablesFolder:GetChildren() do
			table.insert(allTableModels, m)
		end
	end
	if soloFolder then
		for _, m in soloFolder:GetChildren() do
			table.insert(allTableModels, m)
		end
	end

	for _, tableModel in allTableModels do
		if not tableModel:IsA("Model") then
			continue
		end

		local tablePart = tableModel:FindFirstChild("Table")
		local chair1 = tableModel:FindFirstChild("Chair1")
		local chair2 = tableModel:FindFirstChild("Chair2")

		if not tablePart or not chair1 then
			warn(`[TableManager] {tableModel.Name} missing Table or Chair1`)
			continue
		end

		-- Determine if solo (no Chair2) or 1v1
		local isSolo = chair2 == nil
		local maxPlayers = if isSolo then 1 else 2

		local tableId = tableModel.Name
		local billboard, playerCountLabel = createBillboard(tablePart)

		-- Update reward text for solo tables
		if isSolo then
			local rewardLabel = billboard:FindFirstChild("Reward", true)
			if rewardLabel then
				rewardLabel.Text = "Practice Mode"
				rewardLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
			end
		end

		-- Single ProximityPrompt on the Table part
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = if isSolo then "Practice" else "Join"
		prompt.ObjectText = ""
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = tablePart

		local chairs = { [1] = { part = chair1, player = nil } }
		if not isSolo then
			chairs[2] = { part = chair2, player = nil }
		end

		-- Disable seats so players can't walk into them and auto-sit. The
		-- proximity prompt calls seat:Sit(humanoid) programmatically, which
		-- bypasses the Disabled flag.
		for _, chair in chairs do
			local seat = findSeat(chair.part)
			if seat then
				seat.Disabled = true
			end
		end

		tables[tableId] = {
			model = tableModel,
			prompt = prompt,
			chairs = chairs,
			maxPlayers = maxPlayers,
			billboard = billboard,
			playerCountLabel = playerCountLabel,
			match = nil,
		}

		updateBillboard(tables[tableId])

		prompt.Triggered:Connect(function(player)
			seatPlayer(tableId, player)
		end)
	end

	-- Handle player requesting to leave
	local RateLimit = require(script.Parent:WaitForChild("RateLimit"))
	LeaveTableRemote.OnServerEvent:Connect(function(player)
		if not RateLimit.check("LeaveTable", player, 0.5) then return end
		local tableId = playerToTable[player]
		if not tableId then
			return
		end

		local tableState = tables[tableId]
		if tableState and tableState.match then
			tableState.match:PlayerDisconnected(player)
		else
			unseatPlayer(tableId, player)
		end
	end)

	-- Handle player disconnect
	Players.PlayerRemoving:Connect(function(player)
		local tableId = playerToTable[player]
		if not tableId then
			return
		end

		local tableState = tables[tableId]
		if tableState and tableState.match then
			tableState.match:PlayerDisconnected(player)
		else
			unseatPlayer(tableId, player)
		end
	end)

	print(`[TableManager] Initialized {#allTableModels} tables`)
end

return TableManager
