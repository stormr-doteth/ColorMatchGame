-- InventoryHud
-- Shows owned chairs in a grid. Click to equip/unequip.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))

local InventoryHud = {}

local EQUIPPED_STROKE = Color3.fromRGB(255, 215, 0)

-- Rarity styling: top color is brighter accent, bottom color is deeper base.
-- A vertical UIGradient + stroke + background tint all pull from this table.
local RARITY_STYLE: { [string]: { top: Color3, bottom: Color3, stroke: Color3 } } = {
	common       = { top = Color3.fromRGB(170, 175, 180), bottom = Color3.fromRGB(70, 75, 80),    stroke = Color3.fromRGB(200, 205, 210) },
	uncommon     = { top = Color3.fromRGB(90, 220, 110),  bottom = Color3.fromRGB(30, 110, 50),   stroke = Color3.fromRGB(130, 255, 150) },
	rare         = { top = Color3.fromRGB(80, 150, 255),  bottom = Color3.fromRGB(25, 65, 160),   stroke = Color3.fromRGB(120, 190, 255) },
	epic         = { top = Color3.fromRGB(200, 100, 255), bottom = Color3.fromRGB(95, 30, 160),   stroke = Color3.fromRGB(220, 140, 255) },
	legendary    = { top = Color3.fromRGB(255, 180, 60),  bottom = Color3.fromRGB(180, 90, 0),    stroke = Color3.fromRGB(255, 215, 100) },
	glacial      = { top = Color3.fromRGB(140, 230, 255), bottom = Color3.fromRGB(40, 110, 170),  stroke = Color3.fromRGB(180, 240, 255) },
	stormbringer = { top = Color3.fromRGB(180, 120, 255), bottom = Color3.fromRGB(60, 20, 120),   stroke = Color3.fromRGB(210, 160, 255) },
	gamepass     = { top = Color3.fromRGB(255, 230, 100), bottom = Color3.fromRGB(180, 130, 0),   stroke = Color3.fromRGB(255, 235, 130) },
}

local function getRarityStyle(rarity: string?)
	return RARITY_STYLE[rarity or "common"] or RARITY_STYLE.common
end


local BOUNCE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BOUNCE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local ITEM_POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function popItem(item: Frame)
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	local origSize = item.Size
	TweenService:Create(item, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(origSize.X.Scale * 0.9, origSize.X.Offset * 0.9, origSize.Y.Scale * 0.9, origSize.Y.Offset * 0.9),
	}):Play()
	task.delay(0.08, function()
		TweenService:Create(item, ITEM_POP, { Size = origSize }):Play()
	end)
end

local function flashEquipStroke(stroke: UIStroke)
	stroke.Thickness = 8
	stroke.Color = Color3.fromRGB(255, 255, 200)
	TweenService:Create(stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Thickness = 4,
		Color = EQUIPPED_STROKE,
	}):Play()
end

local function setupViewport(viewport: ViewportFrame, model: Model, flipSeat: boolean?, zoom: number?)
	for _, c in viewport:GetChildren() do
		if not c:IsA("TextLabel") then c:Destroy() end
	end

	local clone = model:Clone()
	clone.Parent = viewport
	clone:PivotTo(CFrame.new(0, 0, 0))

	-- Compute AABB from VISIBLE parts only. `Model:GetBoundingBox()` includes
	-- every descendant BasePart (invisible VFX/attachment anchors, aura
	-- emitters, trail parts) — if any of those sit far from the chair body the
	-- box swells and the camera pulls so far back the chair renders tiny.
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf = d.CFrame
			local sx, sy, sz = d.Size.X / 2, d.Size.Y / 2, d.Size.Z / 2
			for ix = -1, 1, 2 do
				for iy = -1, 1, 2 do
					for iz = -1, 1, 2 do
						local c = cf * Vector3.new(ix * sx, iy * sy, iz * sz)
						if c.X < minX then minX = c.X end
						if c.Y < minY then minY = c.Y end
						if c.Z < minZ then minZ = c.Z end
						if c.X > maxX then maxX = c.X end
						if c.Y > maxY then maxY = c.Y end
						if c.Z > maxZ then maxZ = c.Z end
					end
				end
			end
		end
	end
	local boxCFrame, boxSize
	if minX ~= math.huge then
		boxCFrame = CFrame.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
		boxSize = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	else
		boxCFrame, boxSize = clone:GetBoundingBox()
	end
	clone:PivotTo(CFrame.new(-boxCFrame.Position))
	if flipSeat then
		clone:PivotTo(CFrame.Angles(0, math.pi, 0) * clone:GetPivot())
	end

	local maxExtent = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local cameraDistance = (maxExtent * 1.4 + 0.5) * (zoom or 1)

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(
		Vector3.new(cameraDistance, cameraDistance * 0.6, cameraDistance),
		Vector3.new(0, 0, 0)
	)
	camera.FieldOfView = 45
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Ambient = Color3.fromRGB(180, 180, 180)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
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

	local gradient = item:FindFirstChildOfClass("UIGradient")
	if gradient then gradient:Destroy() end
	local itemImage = item:FindFirstChild("ItemImage")
	if itemImage then itemImage:Destroy() end
	local imgLabel = item:FindFirstChild("ImageLabel")
	if imgLabel then imgLabel:Destroy() end

	local style = getRarityStyle(entry.rarity)
	item.BackgroundColor3 = style.bottom
	item.BackgroundTransparency = 0

	local rarityGradient = Instance.new("UIGradient")
	rarityGradient.Name = "RarityGradient"
	rarityGradient.Rotation = 90
	rarityGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, style.top),
		ColorSequenceKeypoint.new(1, style.bottom),
	})
	rarityGradient.Parent = item

	local viewport = item:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
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
			local flip = if entry.viewportFlip ~= nil then entry.viewportFlip else entry.flipSeat
			setupViewport(viewport, model, flip, entry.viewportZoom)
		end
	end

	for _, child in item:GetChildren() do
		if child:IsA("UIStroke") then child:Destroy() end
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "EquipIndicator"
	stroke.Thickness = if isEquipped then 4 else 2
	stroke.Color = if isEquipped then EQUIPPED_STROKE else style.stroke
	stroke.Transparency = if isEquipped then 0 else 0.15
	stroke.Parent = item

	local clickOverlay = item:FindFirstChild("ClickOverlay")
	if not clickOverlay then
		clickOverlay = Instance.new("TextButton")
		clickOverlay.Name = "ClickOverlay"
		clickOverlay.Size = UDim2.fromScale(1, 1)
		clickOverlay.BackgroundTransparency = 1
		clickOverlay.Text = ""
		clickOverlay.AutoButtonColor = false
		clickOverlay.ZIndex = 10
		clickOverlay.Selectable = true
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
	if not localPlayer then return end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local updateRemote = remotes:WaitForChild("PlayerDataUpdate") :: RemoteEvent
	local equipRemote = remotes:WaitForChild("EquipChair") :: RemoteEvent

	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then return end

	local inventory = screenGui:WaitForChild("Inventory", 10)
	if not inventory then return end

	-- Support both old "Body" and new "ChairsBody" layout
	local body = inventory:FindFirstChild("ChairsBody") or inventory:FindFirstChild("Body")
	local header = inventory:FindFirstChild("Header")
	local closeButton = header and header:FindFirstChild("CloseButton")

	local templateItem = body and body:FindFirstChild("Item1")
	if templateItem then templateItem.Visible = false end

	-- Grid layout
	if body then
		local gridLayout = body:FindFirstChildOfClass("UIGridLayout")
		if gridLayout then
			-- All scale-based so rows stay proportional on mobile (pixel-based
			-- vertical cell size was producing huge empty rows on phones).
			gridLayout.CellSize = UDim2.new(0.22, 0, 0.28, 0)
			gridLayout.CellPadding = UDim2.new(0.012, 0, 0.02, 0)
			gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		end
		local bodyPadding = body:FindFirstChildOfClass("UIPadding")
		if not bodyPadding then
			bodyPadding = Instance.new("UIPadding")
			bodyPadding.Parent = body
		end
		bodyPadding.PaddingTop = UDim.new(0, 12)
		bodyPadding.PaddingBottom = UDim.new(0, 12)
		bodyPadding.PaddingLeft = UDim.new(0, 12)
		bodyPadding.PaddingRight = UDim.new(0, 12)

		-- Make the ScrollingFrame canvas grow with the grid so every owned
		-- chair is reachable via scroll, no matter how many the player has.
		if body:IsA("ScrollingFrame") then
			body.AutomaticCanvasSize = Enum.AutomaticSize.Y
			body.CanvasSize = UDim2.new(0, 0, 0, 0)
			body.ScrollingDirection = Enum.ScrollingDirection.Y
			body.ScrollBarThickness = 8
			body.ScrollBarImageTransparency = 0.3
			body.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		end
	end

	-- Hide AurasBody if it exists (not used in v0)
	local aurasBody = inventory:FindFirstChild("AurasBody")
	if aurasBody then aurasBody.Visible = false end

	-- Clean up any previously-built FilterBar from an earlier version
	local existingFilterBar = inventory:FindFirstChild("FilterBar")
	if existingFilterBar then existingFilterBar:Destroy() end

	-- Open/close
	inventory.Visible = false
	inventory.AnchorPoint = Vector2.new(0.5, 0.5)
	local invOpenSize = inventory.Size
	local invOrigTransparency = inventory.BackgroundTransparency
	local isAnimating = false

	local function openInventory()
		if inventory.Visible and not isAnimating then return end
		UIManager.CloseOthers("Inventory")
		isAnimating = true
		inventory.Visible = true
		inventory.SelectionGroup = true
		inventory.Size = UDim2.new(
			invOpenSize.X.Scale * 0.7, invOpenSize.X.Offset * 0.7,
			invOpenSize.Y.Scale * 0.7, invOpenSize.Y.Offset * 0.7
		)
		inventory.BackgroundTransparency = math.min(invOrigTransparency + 0.3, 1)
		TweenService:Create(inventory, BOUNCE_IN, {
			Size = invOpenSize,
			BackgroundTransparency = invOrigTransparency,
		}):Play()
		task.delay(BOUNCE_IN.Time, function()
			isAnimating = false
			local SafeSelect = require(script.Parent:WaitForChild("ui"):WaitForChild("SafeSelect"))
			for _, d in inventory:GetDescendants() do
				if d:IsA("GuiButton") and d.Selectable and d.Visible and d.Active then
					SafeSelect.Set(d)
					break
				end
			end
		end)
	end

	local function closeInventory()
		if not inventory.Visible then return end
		isAnimating = true
		local tween = TweenService:Create(inventory, BOUNCE_OUT, {
			Size = UDim2.new(
				invOpenSize.X.Scale * 0.7, invOpenSize.X.Offset * 0.7,
				invOpenSize.Y.Scale * 0.7, invOpenSize.Y.Offset * 0.7
			),
			BackgroundTransparency = math.min(invOrigTransparency + 0.3, 1),
		})
		tween:Play()
		tween.Completed:Connect(function()
			inventory.Visible = false
			inventory.Size = invOpenSize
			inventory.BackgroundTransparency = invOrigTransparency
			isAnimating = false
			local sel = GuiService.SelectedObject
			if sel and sel:IsDescendantOf(inventory) then
				GuiService.SelectedObject = nil
			end
		end)
	end

	local function toggleInventory()
		if inventory.Visible then closeInventory() else openInventory() end
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
			overlay.Selectable = true
			overlay.Parent = inventoryButton
			target = overlay
		end
		target.Activated:Connect(toggleInventory)
	end

	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.Activated:Connect(closeInventory)
	end
	if header then
		local CloseHint = require(script.Parent:WaitForChild("ui"):WaitForChild("CloseHint"))
		CloseHint.Attach(header)
	end

	-- Rendering
	local latestData: any = nil

	local totalChairs = #ChairCatalog.GetAll()

	local function updateCountLabel(ownedCount: number)
		local label = inventory:FindFirstChild("IndexLabel", true)
		if label and label:IsA("TextLabel") then
			label.Text = string.format("Chairs Owned: %d/%d", ownedCount, totalChairs)
		end
	end

	local function rerender()
		if not templateItem or not body then return end
		clearBody(body)
		if typeof(latestData) ~= "table" then
			updateCountLabel(0)
			return
		end
		local owned = latestData.Chairs or {}
		local equipped = latestData.EquippedChair or ""

		local ownedCount = 0
		for index, chairId in owned do
			local entry = ChairCatalog.Get(chairId)
			if not entry then continue end
			ownedCount += 1
			local isEquipped = chairId == equipped
			local item = buildItem(templateItem, entry, index, isEquipped, function()
				if isEquipped then
					equipRemote:FireServer("")
				else
					equipRemote:FireServer(chairId)
				end
			end)
			item.Parent = body
		end

		updateCountLabel(ownedCount)
	end

	updateRemote.OnClientEvent:Connect(function(data)
		latestData = data
		rerender()
	end)

	-- Pull the initial snapshot now that OnClientEvent is wired. Without
	-- this, the server's post-load push can fire before we connect —
	-- RemoteEvents drop on the receiver if there's no listener yet — and
	-- the inventory renders empty until the next mutation re-pushes data.
	local requestRemote = remotes:FindFirstChild("RequestPlayerData")
	if requestRemote and requestRemote:IsA("RemoteEvent") then
		requestRemote:FireServer()
	end

	-- Click ripple effect
	local rippleGui = Instance.new("ScreenGui")
	rippleGui.Name = "RippleOverlay"
	rippleGui.ResetOnSpawn = false
	rippleGui.DisplayOrder = 99
	rippleGui.IgnoreGuiInset = false
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

		TweenService:Create(ring,
			TweenInfo.new(RIPPLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(RIPPLE_END, RIPPLE_END), BackgroundTransparency = 1 }
		):Play()
		TweenService:Create(stroke,
			TweenInfo.new(RIPPLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		):Play()
		task.delay(RIPPLE_TIME, function() ring:Destroy() end)
	end

	UserInputService.InputBegan:Connect(function(input, _gameProcessed)
		if not inventory.Visible then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			spawnRipple(input.Position.X, input.Position.Y)
		end
	end)

	UIManager.Register("Inventory", closeInventory, function()
		return inventory.Visible
	end)
end

return InventoryHud
