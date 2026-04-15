-- LuckyBlockShop
-- Server-side lucky block system: purchase, tool grant, weighted roll, award.
--
-- For each block type in LuckyBlockCatalog:
--   1. Attach ProximityPrompt + BillboardGui to the Workspace model
--   2. On purchase: deduct cash, grant a Tool to the player's Backpack
--   3. On open (tool activated): roll weighted loot, award chair (or refund if
--      duplicate), fire result to client for the 3D reveal animation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))
local ProfileService = require(script.Parent.Parent:WaitForChild("data"):WaitForChild("ProfileService"))

local DUPLICATE_REFUND_RATE = 0.25

local LuckyBlockShop = {}

local toolTemplates: Folder? = nil

local function getRemote(name: string): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild(name)
end

---------------------------------------------------------------------------
-- Model lookup (checks Animated Lucky Blocks folder first, then Workspace)
---------------------------------------------------------------------------

local function findBlockModel(name: string): Instance?
	local folder = Workspace:FindFirstChild("Animated Lucky Blocks")
	if folder then
		local found = folder:FindFirstChild(name)
		if found then return found end
	end
	return Workspace:FindFirstChild(name)
end

---------------------------------------------------------------------------
-- Tool template building
---------------------------------------------------------------------------

-- Clone the full workspace model into a scaled-down Tool with a Handle part.
-- All non-handle parts are welded to the handle so the model stays intact.
local function buildToolTemplates()
	local folder = ServerStorage:FindFirstChild("LuckyBlockToolTemplates")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LuckyBlockToolTemplates"
		folder.Parent = ServerStorage
	end

	for _, entry in LuckyBlockCatalog.GetAll() do
		if folder:FindFirstChild(entry.id) then
			continue
		end
		local source = findBlockModel(entry.modelName)
		if not source then
			warn(`[LuckyBlockShop] Missing model in Workspace: {entry.modelName}`)
			continue
		end

		local tool = Instance.new("Tool")
		tool.Name = entry.id
		tool.CanBeDropped = false
		tool.RequiresHandle = true

		-- Clone the full model so we get all visual parts
		local clone: Model | BasePart
		if source:IsA("Model") then
			clone = source:Clone()
		elseif source:IsA("BasePart") then
			clone = source:Clone()
		else
			warn(`[LuckyBlockShop] Unsupported instance type for {entry.modelName}`)
			continue
		end

		-- Collect all BaseParts and compute bounding box for scaling
		local allParts: { BasePart } = {}
		if clone:IsA("BasePart") then
			table.insert(allParts, clone)
		end
		if clone:IsA("Model") then
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then
					table.insert(allParts, desc)
				end
			end
		end

		if #allParts == 0 then
			warn(`[LuckyBlockShop] No BaseParts in {entry.modelName}`)
			clone:Destroy()
			continue
		end

		-- Compute bounding box
		local minV = Vector3.new(math.huge, math.huge, math.huge)
		local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, part in allParts do
			local halfSize = part.Size / 2
			local pos = part.Position
			minV = Vector3.new(math.min(minV.X, pos.X - halfSize.X), math.min(minV.Y, pos.Y - halfSize.Y), math.min(minV.Z, pos.Z - halfSize.Z))
			maxV = Vector3.new(math.max(maxV.X, pos.X + halfSize.X), math.max(maxV.Y, pos.Y + halfSize.Y), math.max(maxV.Z, pos.Z + halfSize.Z))
		end
		local bbSize = maxV - minV
		local maxDim = math.max(bbSize.X, bbSize.Y, bbSize.Z)
		local TOOL_SIZE = 2.0
		local scale = if maxDim > TOOL_SIZE then TOOL_SIZE / maxDim else 1
		local center = (minV + maxV) / 2

		-- Pick the handle part (PrimaryPart or largest part)
		local handlePart: BasePart = allParts[1]
		if clone:IsA("Model") and clone.PrimaryPart then
			handlePart = clone.PrimaryPart
		end

		-- Scale and reposition all parts relative to center, then weld to handle
		for _, part in allParts do
			local offset = part.Position - center
			part.Size = part.Size * scale
			part.Position = offset * scale
			part.Anchored = false
			part.CanCollide = false
		end

		-- Reparent: handle becomes a direct child of Tool named "Handle"
		handlePart.Name = "Handle"
		if clone:IsA("Model") then
			-- Move all parts out of the model and into the tool directly
			-- Weld non-handle parts to the handle
			for _, part in allParts do
				if part ~= handlePart then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = handlePart
					weld.Part1 = part
					weld.Parent = part
				end
				part.Parent = tool
			end
			-- Also move any non-BasePart visual children (meshes, textures, etc.)
			-- that were direct children of the model
			clone:Destroy()
		else
			handlePart.Parent = tool
		end

		local blockIdValue = Instance.new("StringValue")
		blockIdValue.Name = "BlockId"
		blockIdValue.Value = entry.id
		blockIdValue.Parent = tool

		tool.Parent = folder
	end

	toolTemplates = folder
end

---------------------------------------------------------------------------
-- Billboard + ProximityPrompt (mirrors ChairShop pattern)
---------------------------------------------------------------------------

-- For animated lucky blocks, prefer "Cube" (the visible animated mesh) over
-- HumanoidRootPart (which is anchored and doesn't move with the animation).
local function findRootPart(model): BasePart?
	if model:IsA("Model") then
		local cube = model:FindFirstChild("Cube")
		if cube and cube:IsA("BasePart") then
			return cube
		end
		if model.PrimaryPart then
			return model.PrimaryPart
		end
		return model:FindFirstChildWhichIsA("BasePart", true)
	elseif model:IsA("BasePart") then
		return model
	end
	return nil
end

local function makeShopBillboard(parent: BasePart, entry)
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShopBillboard"
	bb.Adornee = parent
	bb.Size = UDim2.fromOffset(200, 70)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 60
	bb.Parent = parent

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Size = UDim2.new(1, 0, 0.5, 0)
	name.BackgroundTransparency = 1
	name.Text = entry.displayName
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.Parent = bb

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 2
	nameStroke.Parent = name

	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.Size = UDim2.new(1, 0, 0.45, 0)
	price.Position = UDim2.fromScale(0, 0.5)
	price.BackgroundTransparency = 1
	local firstPrice = if #entry.buyOptions > 0 then entry.buyOptions[1].price else 0
	price.Text = `${firstPrice}`
	price.TextColor3 = Color3.fromRGB(255, 215, 0)
	price.TextScaled = true
	price.Font = Enum.Font.FredokaOne
	price.Parent = bb

	local priceStroke = Instance.new("UIStroke")
	priceStroke.Color = Color3.fromRGB(0, 0, 0)
	priceStroke.Thickness = 2
	priceStroke.Parent = price
end

local function setupShopBlock(entry)
	local model = findBlockModel(entry.modelName)
	if not model then
		warn(`[LuckyBlockShop] Workspace model not found: {entry.modelName}`)
		return
	end

	local rootPart = findRootPart(model)
	if not rootPart then
		warn(`[LuckyBlockShop] No root part for {entry.modelName}`)
		return
	end

	makeShopBillboard(rootPart, entry)

	local existing = rootPart:FindFirstChild("BuyPrompt")
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Shop"
	prompt.ObjectText = entry.displayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(player)
		-- Open the appropriate shop UI based on block type
		local remoteName = if entry.shopType == "cosmetics" then "OpenCosmeticsShop" else "OpenLuckyBlockShop"
		local shopRemote = getRemote(remoteName)
		if shopRemote then
			(shopRemote :: RemoteEvent):FireClient(player, entry.id)
		end
	end)
end

---------------------------------------------------------------------------
-- Purchase
---------------------------------------------------------------------------

function LuckyBlockShop.AttemptPurchase(player: Player, blockId: string, quantity: number?)
	local entry = LuckyBlockCatalog.Get(blockId)
	if not entry then
		return
	end
	local qty = math.clamp(quantity or 1, 1, 10)

	-- Find matching buyOption for the quantity, or fall back to first option's unit price
	local totalPrice = 0
	local foundOption = false
	for _, opt in entry.buyOptions do
		if opt.quantity == qty then
			totalPrice = opt.price
			foundOption = true
			break
		end
	end
	if not foundOption then
		-- Fallback: use first buy option's unit price
		if #entry.buyOptions > 0 then
			totalPrice = math.ceil(entry.buyOptions[1].price * qty)
		else
			return
		end
	end

	local data = ProfileService.GetData(player)
	if not data then
		return
	end
	if (data.Cash or 0) < totalPrice then
		return
	end

	ProfileService.AddCash(player, -totalPrice)
	for _ = 1, qty do
		ProfileService.AddLuckyBlock(player, blockId)
		LuckyBlockShop.GrantTool(player, blockId)
	end

	local notifyRemote = getRemote("ShowNotification")
	if notifyRemote then
		local label = if qty > 1 then `Purchased {qty}x {entry.displayName}!` else `Purchased {entry.displayName}!`
		local nr = notifyRemote :: RemoteEvent
		nr:FireClient(player, label)
	end
end

---------------------------------------------------------------------------
-- Tool granting
---------------------------------------------------------------------------

function LuckyBlockShop.GrantTool(player: Player, blockId: string)
	if not toolTemplates then
		return
	end
	local template = toolTemplates:FindFirstChild(blockId)
	if not template then
		warn(`[LuckyBlockShop] No tool template for {blockId}`)
		return
	end
	local tool = template:Clone()
	tool.Name = "LuckyBlock_" .. blockId
	tool.Parent = player:FindFirstChild("Backpack") or player
end

---------------------------------------------------------------------------
-- Weighted random roll
---------------------------------------------------------------------------

local function rollLoot(lootTable): string?
	local totalWeight = 0
	for _, loot in lootTable do
		totalWeight += loot.weight
	end
	if totalWeight <= 0 then
		return nil
	end
	local roll = math.random() * totalWeight
	for _, loot in lootTable do
		roll -= loot.weight
		if roll <= 0 then
			return loot.chairId
		end
	end
	return lootTable[#lootTable].chairId
end

---------------------------------------------------------------------------
-- Open (called when client activates the tool)
---------------------------------------------------------------------------

local function onOpenLuckyBlock(player: Player, blockId: any, dropPosition: any)
	if typeof(blockId) ~= "string" or typeof(dropPosition) ~= "Vector3" then
		return
	end

	local entry = LuckyBlockCatalog.Get(blockId)
	if not entry then
		return
	end

	-- Consume one block from inventory
	if not ProfileService.UseLuckyBlock(player, blockId) then
		return
	end

	-- Roll the winner
	local winnerChairId = rollLoot(entry.lootTable)
	if not winnerChairId then
		return
	end

	-- Build loot chair id list for the cycling animation
	local lootChairIds = {}
	for _, loot in entry.lootTable do
		table.insert(lootChairIds, loot.chairId)
	end

	-- Award the chair (or refund if duplicate)
	local added = ProfileService.AddChair(player, winnerChairId)
	local chairEntry = ChairCatalog.Get(winnerChairId)
	local chairName = chairEntry and chairEntry.displayName or winnerChairId

	-- Build the notification message (client will show it after the reveal animation)
	local notificationMsg: string
	if added then
		notificationMsg = `You won {chairName}!`
	else
		local basePrice = if #entry.buyOptions > 0 then entry.buyOptions[1].price else 0
		local refund = math.floor(basePrice * DUPLICATE_REFUND_RATE)
		if refund > 0 then
			ProfileService.AddCash(player, refund)
		end
		notificationMsg = `Already owned {chairName}! Refunded ${refund}`
	end

	-- Destroy the tool from the player
	local character = player.Character
	if character then
		local tool = character:FindFirstChild("LuckyBlock_" .. blockId)
		if tool then
			tool:Destroy()
		end
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		local tool = backpack:FindFirstChild("LuckyBlock_" .. blockId)
		if tool then
			tool:Destroy()
		end
	end

	-- Fire result to ALL clients so everyone sees the reveal animation
	local resultRemote = getRemote("LuckyBlockResult")
	if resultRemote then
		local re = resultRemote :: RemoteEvent
		re:FireAllClients({
			blockId = blockId,
			playerName = player.Name,
			winnerChairId = winnerChairId,
			lootChairIds = lootChairIds,
			dropPosition = dropPosition,
			notificationMsg = notificationMsg,
		})
	end
end

---------------------------------------------------------------------------
-- Grant tools on rejoin for any unspent blocks in profile
---------------------------------------------------------------------------

local function grantExistingBlocks(player: Player)
	local data = ProfileService.GetData(player)
	if not data then
		return
	end
	local blocks = data.LuckyBlocks or {}
	for blockId, count in blocks do
		for _ = 1, count do
			LuckyBlockShop.GrantTool(player, blockId)
		end
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local function bindRemotes()
	local openRemote = getRemote("OpenLuckyBlock")
	if openRemote then
		(openRemote :: RemoteEvent).OnServerEvent:Connect(onOpenLuckyBlock)
	end

	local purchaseRemote = getRemote("PurchaseLuckyBlock")
	if purchaseRemote then
		local pr = purchaseRemote :: RemoteEvent
		pr.OnServerEvent:Connect(function(player, blockId, quantity)
			if typeof(blockId) ~= "string" then
				return
			end
			local qty = if typeof(quantity) == "number" then math.floor(quantity) else 1
			LuckyBlockShop.AttemptPurchase(player, blockId, qty)
		end)
	end
end

-- Play idle animations on all lucky block models in the Animated Lucky Blocks folder
local BLOCK_ANIM_ID = "rbxassetid://126593292951336"

local function playBlockAnimations()
	local folder = Workspace:FindFirstChild("Animated Lucky Blocks")
	if not folder then return end

	for _, block in folder:GetChildren() do
		if not block:IsA("Model") then continue end

		local animController = block:FindFirstChildOfClass("AnimationController")
		if not animController then
			animController = Instance.new("AnimationController")
			animController.Parent = block
		end

		local animator = animController:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = animController
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = BLOCK_ANIM_ID

		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
	end
end

function LuckyBlockShop.Init()
	buildToolTemplates()
	for _, entry in LuckyBlockCatalog.GetAll() do
		setupShopBlock(entry)
	end
	bindRemotes()
	playBlockAnimations()

	-- Grant tools for blocks players already own (e.g. after rejoin)
	for _, player in Players:GetPlayers() do
		task.spawn(grantExistingBlocks, player)
	end
	Players.PlayerAdded:Connect(function(player)
		-- Wait a moment for profile to load
		task.delay(3, function()
			if player.Parent then
				grantExistingBlocks(player)
			end
		end)
	end)
end

return LuckyBlockShop
