local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local MatchController = require(script.Parent.MatchController)
local SoloMatchController = require(script.Parent.SoloMatchController)

local TableManager = {}

local tables = {} -- tableId -> TableState
local playerToTable = {} -- Player -> tableId

-- Lazy remote refs
local PlayerSeatedRemote
local LeaveTableRemote

local function getRemote(name: string): RemoteEvent
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild(name)
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
end

local function kickFromSeat(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
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

	-- Anchor player at chair
	seatPlayerInChair(player, chair.part)

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
		end)

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
	end

	tableState.prompt.Enabled = true
	updateBillboard(tableState)
end

function TableManager.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	PlayerSeatedRemote = remotes:WaitForChild("PlayerSeated")
	LeaveTableRemote = remotes:WaitForChild("LeaveTable")

	local tablesFolder = workspace:WaitForChild("Tables", 5)
	if not tablesFolder then
		warn("[TableManager] No Tables folder found in Workspace")
		return
	end

	for _, tableModel in tablesFolder:GetChildren() do
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
	LeaveTableRemote.OnServerEvent:Connect(function(player)
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

	print(`[TableManager] Initialized {#tablesFolder:GetChildren()} tables`)
end

return TableManager
