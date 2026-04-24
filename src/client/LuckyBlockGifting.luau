-- LuckyBlockGifting
-- Gift flow for held lucky-block tools. Uses a ProximityPrompt on every other
-- player's torso so Roblox renders the platform-correct hint (E on desktop,
-- touch button on mobile, ButtonX on gamepad) at the right scale automatically.
--
--   1. While the local player has a LuckyBlock_* tool equipped, we enable one
--      ProximityPrompt per other player, parented to their torso.
--   2. Triggering the prompt (hold for HOLD_TIME) opens the confirm modal.
--   3. Confirming fires GiftLuckyBlock; recipient gets LuckyBlockGiftReceived
--      which surfaces as a NotificationHud toast.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))
local NotificationHud = require(script.Parent:WaitForChild("NotificationHud"))

local LuckyBlockGifting = {}

local HOLD_TIME = 0.8
local GIFT_RANGE = 14 -- studs; server allows slightly more

local localPlayer = Players.LocalPlayer
local started = false
local equippedBlockId: string? = nil
local confirmGui: ScreenGui? = nil
local confirmOpen = false

-- One ProximityPrompt per remote player (keyed by Player).
local prompts: { [Player]: ProximityPrompt } = {}
local promptConnections: { [Player]: { RBXScriptConnection } } = {}

local function getRemote(name: string): RemoteEvent?
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	return remotes:FindFirstChild(name) :: RemoteEvent?
end

local function closeConfirm()
	if confirmGui then
		confirmGui:Destroy()
		confirmGui = nil
	end
	confirmOpen = false
end

local function openConfirm(target: Player, blockId: string)
	closeConfirm()
	confirmOpen = true
	local entry = LuckyBlockCatalog.Get(blockId)
	local blockName = entry and entry.displayName or blockId

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "LuckyBlockGiftConfirmGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 210
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	confirmGui = gui

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(380, 200)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local panelCorner = Instance.new("UICorner"); panelCorner.CornerRadius = UDim.new(0, 12); panelCorner.Parent = panel
	local panelStroke = Instance.new("UIStroke"); panelStroke.Thickness = 2; panelStroke.Color = Color3.fromRGB(255, 255, 255); panelStroke.Transparency = 0.6; panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 32)
	title.Position = UDim2.fromOffset(10, 14)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 22
	title.Text = "ARE YOU SURE?"
	title.Parent = panel

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -30, 0, 72)
	body.Position = UDim2.fromOffset(15, 50)
	body.BackgroundTransparency = 1
	body.TextColor3 = Color3.fromRGB(230, 230, 230)
	body.Font = Enum.Font.FredokaOne
	body.TextSize = 17
	body.TextWrapped = true
	body.Text = `Gift 1x {blockName} to {target.DisplayName}?`
	body.Parent = panel

	local function mkButton(text: string, x: number, color: Color3): TextButton
		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(0, 1)
		btn.Position = UDim2.new(0, x, 1, -14)
		btn.Size = UDim2.fromOffset(160, 44)
		btn.BackgroundColor3 = color
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Text = text
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.FredokaOne
		btn.TextSize = 18
		btn.Parent = panel
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = btn
		return btn
	end

	local cancel = mkButton("CANCEL", 20, Color3.fromRGB(90, 90, 90))
	local confirm = mkButton("GIFT", 200, Color3.fromRGB(86, 170, 96))

	cancel.Activated:Connect(function()
		closeConfirm()
	end)
	confirm.Activated:Connect(function()
		local remote = getRemote("GiftLuckyBlock")
		if remote and equippedBlockId then
			remote:FireServer(target.UserId, equippedBlockId)
		end
		closeConfirm()
	end)
end

local function setPromptsEnabled(enabled: boolean)
	for _, prompt in prompts do
		prompt.Enabled = enabled
	end
end

local function removePrompt(player: Player)
	local connections = promptConnections[player]
	if connections then
		for _, c in connections do c:Disconnect() end
		promptConnections[player] = nil
	end
	local prompt = prompts[player]
	if prompt then
		prompt:Destroy()
		prompts[player] = nil
	end
end

local function ensurePromptFor(player: Player)
	if player == localPlayer then return end
	if prompts[player] then return end
	local character = player.Character
	if not character then return end
	local host = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:WaitForChild("UpperTorso", 5)
		or character:WaitForChild("Torso", 1)
	if not host then return end
	-- Character may have already respawned while we were waiting.
	if character ~= player.Character then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LuckyBlockGiftPrompt"
	prompt.ActionText = "Gift"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = HOLD_TIME
	prompt.MaxActivationDistance = GIFT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Enabled = equippedBlockId ~= nil
	prompt.Parent = host

	local conns = {}
	table.insert(conns, prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer ~= localPlayer then return end
		if not equippedBlockId or confirmOpen then return end
		openConfirm(player, equippedBlockId)
	end))

	prompts[player] = prompt
	promptConnections[player] = conns
end

local function watchPlayer(player: Player)
	if player == localPlayer then return end
	local function onChar(char: Model)
		removePrompt(player)
		task.spawn(function()
			if player.Parent and char.Parent then
				ensurePromptFor(player)
			end
		end)
	end
	if player.Character then onChar(player.Character) end
	player.CharacterAdded:Connect(onChar)
end

local function updateEquipped()
	local character = localPlayer.Character
	equippedBlockId = nil
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				local bid = child.Name:match("^LuckyBlock_(.+)$")
				if bid then
					equippedBlockId = bid
					break
				end
			end
		end
	end
	setPromptsEnabled(equippedBlockId ~= nil)
	if not equippedBlockId then
		closeConfirm()
	end
end

local function onLocalCharacter(character: Model)
	updateEquipped()
	character.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then updateEquipped() end
	end)
	character.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then updateEquipped() end
	end)
end

function LuckyBlockGifting.Start()
	if started then return end
	started = true

	if localPlayer.Character then onLocalCharacter(localPlayer.Character) end
	localPlayer.CharacterAdded:Connect(onLocalCharacter)

	for _, p in Players:GetPlayers() do watchPlayer(p) end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(p) removePrompt(p) end)

	local giftReceived = getRemote("LuckyBlockGiftReceived")
	if giftReceived then
		giftReceived.OnClientEvent:Connect(function(data)
			if type(data) ~= "table" then return end
			local name = tostring(data.displayName or "Lucky Block")
			local from = tostring(data.fromName or "someone")
			NotificationHud.Show(`🎁 {from} gifted you a {name}!`)
		end)
	end
end

return LuckyBlockGifting
