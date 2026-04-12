-- InventoryHud
-- Hooks up the StarterGui.ScreenGui.Inventory frame to the live profile data:
--   • Toggle visibility via the Shop "InventoryButton" and the inventory
--     Header.CloseButton.
--   • Render one Item per owned chair, each containing a ViewportFrame that
--     shows a 3D preview of the chair model from ReplicatedStorage.ChairTemplates.
--   • Click an item to equip it; click the equipped item again to unequip.
--   • The currently equipped item gets a gold border.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))

local InventoryHud = {}

local EQUIPPED_STROKE = Color3.fromRGB(255, 215, 0)
local DEFAULT_STROKE = Color3.fromRGB(255, 255, 255)

-- Tween configs
local BOUNCE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BOUNCE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local ITEM_POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EQUIP_FLASH = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Bouncy scale animation on an item when clicked
local function popItem(item: Frame)
	-- Scale from anchor point (center)
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Shrink slightly then bounce back
	local origSize = item.Size
	TweenService:Create(item, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(origSize.X.Scale * 0.9, origSize.X.Offset * 0.9, origSize.Y.Scale * 0.9, origSize.Y.Offset * 0.9),
	}):Play()
	task.delay(0.08, function()
		TweenService:Create(item, ITEM_POP, {
			Size = origSize,
		}):Play()
	end)
end

-- Flash the stroke when equipping
local function flashEquipStroke(stroke: UIStroke)
	stroke.Thickness = 8
	stroke.Color = Color3.fromRGB(255, 255, 200)
	TweenService:Create(stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Thickness = 4,
		Color = EQUIPPED_STROKE,
	}):Play()
end

local function setupViewport(viewport: ViewportFrame, model: Model)
	-- Clear existing 3D content (template viewports may have placeholders),
	-- but preserve any TextLabel overlays (chairName, equipLabel) that sit
	-- on top of the viewport.
	for _, c in viewport:GetChildren() do
		if not c:IsA("TextLabel") then
			c:Destroy()
		end
	end

	local clone = model:Clone()
	clone.Parent = viewport

	-- Re-centre the model around the world origin so the viewport camera
	-- frames it cleanly regardless of where it lived in workspace.
	clone:PivotTo(CFrame.new(0, 0, 0))
	local boxCFrame, boxSize = clone:GetBoundingBox()
	clone:PivotTo(CFrame.new(-boxCFrame.Position))

	local maxExtent = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local cameraDistance = maxExtent * 1.8 + 2

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(
		Vector3.new(cameraDistance, cameraDistance * 0.7, cameraDistance),
		Vector3.new(0, 0, 0)
	)
	camera.FieldOfView = 45
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Ambient = Color3.fromRGB(180, 180, 180)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	-- Fix positioning and transparency so the 3D render is centered and
	-- visible against the item frame's own background.
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.BackgroundTransparency = 1
end

local function clearBody(body: ScrollingFrame)
	for _, child in body:GetChildren() do
		if child:IsA("Frame") and child.Name:match("^ChairItem_") then
			child:Destroy()
		end
	end
end

local function buildItem(template: Frame, entry, index: number, isEquipped: boolean, onActivated: () -> ()): Frame
	local item = template:Clone()
	item.Name = "ChairItem_" .. entry.id
	item.LayoutOrder = index
	item.Visible = true

	-- Strip template decoration that fights with the inventory look:
	-- UIGradient can tint the white bg into unexpected colours, and the
	-- template's own UIStroke may have unwanted properties.
	local gradient = item:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
	-- Remove template ItemImage (we use ViewportFrame instead)
	local itemImage = item:FindFirstChild("ItemImage")
	if itemImage then
		itemImage:Destroy()
	end

	-- Neutral dark background so the 3D preview stands out.
	item.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	item.BackgroundTransparency = 0.1

	local viewport = item:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		-- Populate the chair name and equip status labels (live inside the
		-- ViewportFrame in the template, positioned above/below the 3D preview).
		local chairNameLabel = viewport:FindFirstChild("chairName")
		if chairNameLabel and chairNameLabel:IsA("TextLabel") then
			chairNameLabel.Text = entry.displayName
			chairNameLabel.TextColor3 = if isEquipped
				then Color3.fromRGB(255, 215, 0)
				else Color3.fromRGB(255, 255, 255)
		end
		local equipLabel = viewport:FindFirstChild("equipLabel")
		if equipLabel and equipLabel:IsA("TextLabel") then
			equipLabel.Text = if isEquipped then "Equipped" else "Equip"
			equipLabel.TextColor3 = if isEquipped
				then Color3.fromRGB(255, 215, 0)
				else Color3.fromRGB(255, 255, 255)
		end

		local templates = ReplicatedStorage:FindFirstChild("ChairTemplates")
		local model = templates and templates:FindFirstChild(entry.modelName)
		if model and model:IsA("Model") then
			setupViewport(viewport, model)
		end
	end

	-- Remove all template UIStrokes and add a single clean one for the
	-- equip indicator — avoids accidentally modifying a shared/inherited stroke.
	for _, child in item:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "EquipIndicator"
	stroke.Thickness = if isEquipped then 4 else 2
	stroke.Color = if isEquipped then EQUIPPED_STROKE else DEFAULT_STROKE
	stroke.Transparency = if isEquipped then 0 else 0.5
	stroke.Parent = item

	-- Click handling — overlay an invisible TextButton that fills the item.
	local clickOverlay = item:FindFirstChild("ClickOverlay")
	if not clickOverlay then
		clickOverlay = Instance.new("TextButton")
		clickOverlay.Name = "ClickOverlay"
		clickOverlay.Size = UDim2.fromScale(1, 1)
		clickOverlay.BackgroundTransparency = 1
		clickOverlay.Text = ""
		clickOverlay.AutoButtonColor = false
		clickOverlay.ZIndex = 10
		clickOverlay.Parent = item
	end
	clickOverlay.Activated:Connect(function()
		popItem(item)
		local equipStroke = item:FindFirstChild("EquipIndicator")
		if equipStroke and not isEquipped then
			flashEquipStroke(equipStroke)
		end
		onActivated()
	end)

	return item
end

function InventoryHud.Start()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local updateRemote = remotes:WaitForChild("PlayerDataUpdate") :: RemoteEvent
	local equipRemote = remotes:WaitForChild("EquipChair") :: RemoteEvent

	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then
		warn("[InventoryHud] No ScreenGui found")
		return
	end

	local inventory = screenGui:WaitForChild("Inventory", 10)
	if not inventory then
		warn("[InventoryHud] No Inventory frame")
		return
	end
	local body = inventory:WaitForChild("Body", 10)
	local header = inventory:WaitForChild("Header", 10)
	local closeButton = header and header:FindFirstChild("CloseButton")

	-- Item template — we'll clone it for each owned chair, then hide the
	-- original. Without this fallback we'd have nothing to clone.
	local templateItem = body:FindFirstChild("Item1")
	if templateItem then
		templateItem.Visible = false
	end

	-- Override the grid layout for consistent cross-device scaling:
	-- 3 items per row, generous horizontal gaps, tight vertical gaps.
	local gridLayout = body:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then
		gridLayout.CellSize = UDim2.new(0.22, 0, 0, 160)
		gridLayout.CellPadding = UDim2.new(0.012, 0, 0, 14)
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end

	-- Add inner padding so items don't hug the edges of the scrolling frame.
	local bodyPadding = body:FindFirstChildOfClass("UIPadding")
	if not bodyPadding then
		bodyPadding = Instance.new("UIPadding")
		bodyPadding.Parent = body
	end
	bodyPadding.PaddingTop = UDim.new(0, 12)
	bodyPadding.PaddingBottom = UDim.new(0, 12)
	bodyPadding.PaddingLeft = UDim.new(0, 12)
	bodyPadding.PaddingRight = UDim.new(0, 12)

	-- Inventory starts hidden; player opens it via the InventoryButton.
	-- Open/close uses bouncy scale tweens anchored from center.
	inventory.Visible = false
	inventory.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Store the designer-placed position/size so tweens can target them.
	local invOpenPos = inventory.Position
	local invOpenSize = inventory.Size
	local isAnimating = false

	local function openInventory()
		if inventory.Visible and not isAnimating then
			return
		end
		isAnimating = true
		inventory.Visible = true
		-- Start small and transparent, then bounce in
		inventory.Size = UDim2.new(
			invOpenSize.X.Scale * 0.7, invOpenSize.X.Offset * 0.7,
			invOpenSize.Y.Scale * 0.7, invOpenSize.Y.Offset * 0.7
		)
		inventory.BackgroundTransparency = 0.6
		TweenService:Create(inventory, BOUNCE_IN, {
			Size = invOpenSize,
			BackgroundTransparency = 0,
		}):Play()
		task.delay(BOUNCE_IN.Time, function()
			isAnimating = false
		end)
	end

	local function closeInventory()
		if not inventory.Visible or isAnimating then
			return
		end
		isAnimating = true
		-- Shrink + fade, then hide
		local tween = TweenService:Create(inventory, BOUNCE_OUT, {
			Size = UDim2.new(
				invOpenSize.X.Scale * 0.7, invOpenSize.X.Offset * 0.7,
				invOpenSize.Y.Scale * 0.7, invOpenSize.Y.Offset * 0.7
			),
			BackgroundTransparency = 0.6,
		})
		tween:Play()
		tween.Completed:Connect(function()
			inventory.Visible = false
			inventory.Size = invOpenSize
			inventory.BackgroundTransparency = 0
			isAnimating = false
		end)
	end

	local function toggleInventory()
		if inventory.Visible then
			closeInventory()
		else
			openInventory()
		end
	end

	local shopButtons = screenGui:FindFirstChild("ShopButtons")
	local inventoryButton = shopButtons and shopButtons:FindFirstChild("InventoryButton")
	if inventoryButton then
		local imgButton = inventoryButton:FindFirstChild("Button1Image")
		local target = (imgButton and imgButton:IsA("GuiButton")) and imgButton or nil
		if not target then
			local overlay = Instance.new("TextButton")
			overlay.Name = "InventoryClickOverlay"
			overlay.Size = UDim2.fromScale(1, 1)
			overlay.BackgroundTransparency = 1
			overlay.Text = ""
			overlay.ZIndex = 10
			overlay.Parent = inventoryButton
			target = overlay
		end
		target.Activated:Connect(toggleInventory)
	end

	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.Activated:Connect(closeInventory)
	end

	-- Latest profile snapshot received from the server.
	local latestData: any = nil

	local function rerender()
		if not templateItem or not templateItem:IsA("Frame") then
			return
		end
		clearBody(body)
		if typeof(latestData) ~= "table" then
			return
		end
		local owned = latestData.Chairs or {}
		local equipped = latestData.EquippedChair or ""

		for index, chairId in owned do
			local entry = ChairCatalog.Get(chairId)
			if not entry then
				continue
			end
			local isEquipped = chairId == equipped
			local item = buildItem(templateItem, entry, index, isEquipped, function()
				-- Toggle: clicking equipped unequips; clicking other equips it.
				if isEquipped then
					equipRemote:FireServer("")
				else
					equipRemote:FireServer(chairId)
				end
			end)
			item.Parent = body
		end
	end

	updateRemote.OnClientEvent:Connect(function(data)
		latestData = data
		rerender()
	end)

	-- Click ripple effect — a water-drop ring expands outward from every
	-- click/tap while the inventory is open. Multiple ripples can overlap.
	local rippleGui = Instance.new("ScreenGui")
	rippleGui.Name = "RippleOverlay"
	rippleGui.ResetOnSpawn = false
	rippleGui.DisplayOrder = 99
	rippleGui.IgnoreGuiInset = false -- match input.Position coordinate space
	rippleGui.Parent = playerGui

	local RIPPLE_START = 10
	local RIPPLE_END = 200
	local RIPPLE_TIME = 0.45

	local function spawnRipple(x: number, y: number)
		local ring = Instance.new("Frame")
		ring.Name = "Ripple"
		ring.Size = UDim2.fromOffset(RIPPLE_START, RIPPLE_START)
		ring.Position = UDim2.fromOffset(x, y)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		ring.BackgroundTransparency = 0.7
		ring.BorderSizePixel = 0
		ring.Parent = rippleGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ring

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 2
		stroke.Transparency = 0.2
		stroke.Parent = ring

		local expandTween = TweenService:Create(ring,
			TweenInfo.new(RIPPLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = UDim2.fromOffset(RIPPLE_END, RIPPLE_END),
				BackgroundTransparency = 1,
			}
		)
		local strokeTween = TweenService:Create(stroke,
			TweenInfo.new(RIPPLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)

		expandTween:Play()
		strokeTween:Play()
		expandTween.Completed:Connect(function()
			ring:Destroy()
		end)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not inventory.Visible then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			spawnRipple(input.Position.X, input.Position.Y)
		end
	end)
end

return InventoryHud
