-- LuckyBlockShopUI
-- Wires up the manually-designed Shop UI (StarterGui.ScreenGui.Shop).
-- All visual design is done in Studio — this module only:
--   • Populates lucky block cards from LuckyBlockCatalog (clone Item1 template)
--   • Wires buy buttons for blocks, coin packs, and game passes
--   • Sets prices and % chance labels from catalog data
--   • Handles open/close with bouncy tweens
--   • Checks gamepass ownership and shows "Owned"

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))

local LuckyBlockShopUI = {}

local localPlayer = Players.LocalPlayer

local BOUNCE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BOUNCE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local ROBUX_ICON = utf8.char(0xE002)

-- Controller focus: set SelectedObject to the first selectable descendant so
-- Xbox/PS5 users land inside the panel when it opens. Clearing on close so
-- the cursor doesn't get stranded on a hidden button.
local function findFirstSelectable(root: Instance): GuiObject?
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d.Visible and d.Active then
			return d
		end
	end
	return nil
end
local function focusInto(root: Instance)
	if not GuiService.SelectedObject or not GuiService.SelectedObject:IsDescendantOf(root) then
		local first = findFirstSelectable(root)
		if first then GuiService.SelectedObject = first end
	end
end
local function clearFocus(root: Instance)
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function setupViewport(viewport: ViewportFrame, model: Model, zoom: number?, flipSeat: boolean?)
	for _, c in viewport:GetChildren() do
		if c:IsA("Camera") or c:IsA("Model") or c:IsA("BasePart") then
			c:Destroy()
		end
	end

	local clone = model:Clone()
	clone.Parent = viewport
	clone:PivotTo(CFrame.new(0, 0, 0))
	local boxCFrame, boxSize = clone:GetBoundingBox()
	clone:PivotTo(CFrame.new(-boxCFrame.Position))
	if flipSeat then
		-- Rotate 180° around the (now-centered) bounding box center
		clone:PivotTo(CFrame.Angles(0, math.pi, 0) * clone:GetPivot())
	end

	local maxExtent = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local distanceMult = zoom or 1.4
	local cameraDistance = maxExtent * distanceMult + 0.5

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
	viewport.BackgroundTransparency = 1
end

-- Ensure the entire visible area of a purchase Frame is tappable. The
-- Studio-designed templates ship a nested TextButton whose Size/Position
-- only covers part of the visual button, which on mobile leaves big "dead
-- zones" where a finger press hits nothing (symptom: only the far-right
-- corner seems to work). Overlaying a transparent full-size TextButton
-- with a higher ZIndex than the nested one gives us a consistent hit
-- region without disturbing the template's visual layout. Mirrors the
-- pattern already in HintShop.luau:176.
local function addFullAreaOverlay(parentFrame: GuiObject, name: string): TextButton
	local existing = parentFrame:FindFirstChild(name)
	if existing and existing:IsA("TextButton") then
		return existing
	end
	local overlay = Instance.new("TextButton")
	overlay.Name = name
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.ZIndex = 50
	-- Selectable = true exposes the overlay to controller D-pad navigation
	-- (GuiService.SelectedObject). Without it, Xbox/PS5 users can't reach
	-- purchase buttons.
	overlay.Selectable = true
	overlay.Parent = parentFrame
	return overlay
end

local function popButton(btn: GuiObject)
	local origSize = btn.Size
	TweenService:Create(btn, TweenInfo.new(0.06), {
		Size = UDim2.new(
			origSize.X.Scale * 0.93, origSize.X.Offset * 0.93,
			origSize.Y.Scale * 0.93, origSize.Y.Offset * 0.93
		),
	}):Play()
	task.delay(0.06, function()
		TweenService:Create(btn,
			TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = origSize }
		):Play()
	end)
end

---------------------------------------------------------------------------
-- Wire up a lucky block card (Item template clone)
---------------------------------------------------------------------------

local function wireBlockCard(card: Frame, entry, purchaseRemote: RemoteEvent)
	local chances = LuckyBlockCatalog.GetChances(entry.id)
	local chairTemplates = ReplicatedStorage:FindFirstChild("ChairTemplates")

	-- Block name
	local itemLabel = card:FindFirstChild("ItemLabel") :: TextLabel?
	if itemLabel then
		itemLabel.Text = entry.displayName
	end

	-- Block image
	local blockImage = card:FindFirstChild("BlockImage") :: ImageLabel?
	if blockImage and entry.imageId then
		blockImage.Image = "rbxassetid://" .. tostring(entry.imageId)
	end

	-- Buy buttons. Two supported layouts:
	--   Legacy: a single `SubmitButton` frame with a child SubmitButton button.
	--   Multi-package: `Purchase_1x`, `Purchase_3x`, `Purchase_5x` frames each
	--      with a child SubmitButton — one per robuxPackages entry.
	local function wirePackageButton(frame: Frame, pkg)
		local submitBtn = frame:FindFirstChild("SubmitButton") :: TextButton?
		if not submitBtn then return end
		local tap = addFullAreaOverlay(frame, "TapArea")
		if pkg.productId and pkg.productId > 0 then
			tap.Activated:Connect(function()
				popButton(frame)
				MarketplaceService:PromptProductPurchase(localPlayer, pkg.productId)
			end)
		else
			tap.Activated:Connect(function()
				popButton(frame)
				warn(`[LuckyBlockShop] No productId set for {entry.id} x{pkg.quantity}`)
			end)
		end
	end

	if entry.robuxPackages and (card:FindFirstChild("Purchase_1x") or card:FindFirstChild("Purchase_3x") or card:FindFirstChild("Purchase_5x")) then
		for _, pkg in entry.robuxPackages do
			local frame = card:FindFirstChild("Purchase_" .. tostring(pkg.quantity) .. "x") :: Frame?
			if frame then
				wirePackageButton(frame, pkg)
			end
		end
	else
		local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
		if submitFrame then
			local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
			if submitBtn then
				local tap = addFullAreaOverlay(submitFrame, "TapArea")
				local productId = entry.robuxProductId or 0
				if productId > 0 then
					tap.Activated:Connect(function()
						popButton(submitFrame)
						MarketplaceService:PromptProductPurchase(localPlayer, productId)
					end)
				else
					local price = if #entry.buyOptions > 0 then entry.buyOptions[1].price else 0
					submitBtn.Text = ROBUX_ICON .. " " .. tostring(price)
					tap.Activated:Connect(function()
						popButton(submitFrame)
						local qty = if #entry.buyOptions > 0 then entry.buyOptions[1].quantity else 1
						purchaseRemote:FireServer(entry.id, qty)
					end)
				end
			end
		end
	end

	-- Possible items: populate % and ViewportFrames
	local possibleItems = card:FindFirstChild("PossibleItems") :: Frame?
	if not possibleItems then return end

	-- Slots may be ImageButton (legacy) or Frame (new Glacial-style layout)
	local slots: { GuiObject } = {}
	for _, child in possibleItems:GetChildren() do
		if child:IsA("ImageButton") or child:IsA("Frame") then
			table.insert(slots, child)
		end
	end
	-- UIListLayout orders by LayoutOrder then by Name — match that for consistency
	table.sort(slots, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)

	local sortedLoot = table.clone(entry.lootTable)
	table.sort(sortedLoot, function(a, b) return a.weight > b.weight end)

	-- Per-block viewport overrides: `zoom` = camera distance multiplier (smaller
	-- = tighter crop). `frameScale` > 1 makes the viewport overflow its slot so
	-- the chair appears to "burst out" beyond the card bounds.
	local VIEWPORT_OVERRIDE: { [string]: { zoom: number, frameScale: number } } = {
		legendary_block = { zoom = 0.7, frameScale = 1.4 },
	}
	local override = VIEWPORT_OVERRIDE[entry.id]
	local zoom = override and override.zoom or nil
	local frameScale = override and override.frameScale or 1

	for i, slot in slots do
		local loot = sortedLoot[i]
		if not loot then
			slot.Visible = false
			continue
		end

		local chairEntry = ChairCatalog.Get(loot.chairId)
		local pct = chances[loot.chairId] or 0

		-- Chance label: prefer explicit ChanceLabel, fall back to ItemLabel
		local chanceLabel = slot:FindFirstChild("ChanceLabel") :: TextLabel?
		local itemSlotLabel = slot:FindFirstChild("ItemLabel") :: TextLabel?
		if chanceLabel then
			chanceLabel.Text = `{pct}%`
			if itemSlotLabel and chairEntry then
				itemSlotLabel.Text = chairEntry.displayName
			end
		elseif itemSlotLabel then
			-- Legacy layout: single label shows % only
			itemSlotLabel.Text = `{pct}%`
		end

		-- Slot image may be named "ItemImage" (legacy) or "ImageLabel" (new)
		local slotImage = slot:FindFirstChild("ItemImage") :: ImageLabel?
		if not slotImage then
			slotImage = slot:FindFirstChild("ImageLabel") :: ImageLabel?
		end
		-- Blocks listed here keep their pre-designed slot images instead of
		-- having a ViewportFrame overlaid on top.
		local SKIP_VIEWPORT: { [string]: boolean } = {
			glacial_block = true,
			stormbringer_block = true,
		}

		if slotImage and chairEntry and chairTemplates and not SKIP_VIEWPORT[entry.id] then
			local template = chairTemplates:FindFirstChild(chairEntry.modelName)
			if template and template:IsA("Model") then
				-- Remove any pre-existing ItemViewport (templates ship with
				-- placeholder chair models that must be cleared).
				for _, child in slot:GetChildren() do
					if child:IsA("ViewportFrame") then
						child:Destroy()
					end
				end
				local vf = Instance.new("ViewportFrame")
				vf.Name = "ItemViewport"
				local baseSize = slotImage.Size
				vf.Size = UDim2.new(
					baseSize.X.Scale * frameScale, baseSize.X.Offset * frameScale,
					baseSize.Y.Scale * frameScale, baseSize.Y.Offset * frameScale
				)
				vf.Position = UDim2.fromScale(0.5, 0.5)
				vf.AnchorPoint = Vector2.new(0.5, 0.5)
				vf.BackgroundTransparency = 1
				vf.ZIndex = slotImage.ZIndex
				vf.ClipsDescendants = false
				if frameScale > 1 then
					slot.ClipsDescendants = false
				end
				vf.Parent = slot
				local flip = if chairEntry.viewportFlip ~= nil then chairEntry.viewportFlip else chairEntry.flipSeat
				setupViewport(vf, template, zoom, flip)
				slotImage.Visible = false
			end
		end
	end
end

---------------------------------------------------------------------------
-- Wire a dev product card (cash or wins) — finds SubmitButton inside
---------------------------------------------------------------------------

local function wireDevProductCard(card: Instance, product)
	local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
	if not submitFrame then return end
	local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
	if not submitBtn then return end

	local tap = addFullAreaOverlay(submitFrame, "TapArea")
	tap.Activated:Connect(function()
		popButton(submitFrame)
		if product.productId > 0 then
			MarketplaceService:PromptProductPurchase(localPlayer, product.productId)
		end
	end)
end

---------------------------------------------------------------------------
-- Wire a gamepass card — finds SubmitButton inside, checks ownership
---------------------------------------------------------------------------

local function wireGamePassCard(card: Instance, pass)
	local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
	if not submitFrame then return end
	local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
	if not submitBtn then return end

	local tap = addFullAreaOverlay(submitFrame, "TapArea")
	tap.Activated:Connect(function()
		popButton(submitFrame)
		if pass.gamePassId > 0 then
			MarketplaceService:PromptGamePassPurchase(localPlayer, pass.gamePassId)
		end
	end)

	if pass.gamePassId > 0 then
		task.spawn(function()
			local ok, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(localPlayer.UserId, pass.gamePassId)
			end)
			if ok and owned and submitBtn then
				submitBtn.Text = "Owned"
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Build: wire everything in the manually-designed shop
---------------------------------------------------------------------------

local function buildShop(shopFrame: Frame)
	local body = shopFrame:FindFirstChild("Body") :: ScrollingFrame?
	if not body then
		warn("[Shop] Body not found")
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local purchaseRemote = remotes:WaitForChild("PurchaseLuckyBlock") :: RemoteEvent

	-- Paid random items policy. Restricted players (e.g. Belgium, Netherlands)
	-- must not be offered any lucky block purchase. The attribute is set on
	-- the player by the server PolicyGate; we check it per-card at open time
	-- and react to changes in case the server's async fetch resolves late.
	local function luckyBlocksRestricted(): boolean
		return localPlayer:GetAttribute("ArePaidRandomItemsRestricted") == true
	end

	local lbCards: { Frame } = {}

	-- Lucky Blocks: wire existing manually-designed cards (named LuckyBlock_{id})
	for _, entry in LuckyBlockCatalog.GetAll() do
		if entry.shopType == "cosmetics" then continue end
		local card = body:FindFirstChild("LuckyBlock_" .. entry.id) :: Frame?
		if card then
			wireBlockCard(card, entry, purchaseRemote)
			table.insert(lbCards, card)
		end
	end

	local function applyRestriction()
		local hide = luckyBlocksRestricted()
		for _, card in lbCards do
			card.Visible = not hide
		end
	end
	applyRestriction()
	localPlayer:GetAttributeChangedSignal("ArePaidRandomItemsRestricted"):Connect(applyRestriction)

	-- Dev Products: wire cards by matching ItemLabel.Text to catalog displayName
	-- Searches inside DevProducts, DevProducts_Wins, and top-level frames (BigCash, BigWins)
	local devProductsByName: { [string]: any } = {}
	for _, product in ShopCatalog.GetDevProducts() do
		devProductsByName[product.displayName] = product
	end

	local function wireDevProductsInContainer(container: Instance)
		for _, card in container:GetChildren() do
			if not card:IsA("GuiObject") then continue end
			-- Check ItemLabel or VIP_Label for the display name
			local label = card:FindFirstChild("ItemLabel") or card:FindFirstChild("VIP_Label")
			if label and label:IsA("TextLabel") then
				local product = devProductsByName[label.Text]
				if product then
					wireDevProductCard(card, product)
				end
			end
		end
	end

	local devProducts = body:FindFirstChild("DevProducts")
	if devProducts then wireDevProductsInContainer(devProducts) end

	local devWins = body:FindFirstChild("DevProducts_Wins")
	if devWins then wireDevProductsInContainer(devWins) end

	-- BigCash and BigWins are top-level frames in Body
	local bigCash = body:FindFirstChild("BigCash")
	if bigCash then
		local label = bigCash:FindFirstChild("VIP_Label")
		if label and label:IsA("TextLabel") then
			local product = devProductsByName[label.Text]
			if product then wireDevProductCard(bigCash, product) end
		end
	end

	local bigWins = body:FindFirstChild("BigWins")
	if bigWins then
		local label = bigWins:FindFirstChild("VIP_Label")
		if label and label:IsA("TextLabel") then
			local product = devProductsByName[label.Text]
			if product then wireDevProductCard(bigWins, product) end
		end
	end

	-- Game Passes: wire by matching ItemLabel.Text to catalog displayName
	-- Passes live in GamePasses frame + VIP frame at top level
	local gamePassesByName: { [string]: any } = {}
	for _, pass in ShopCatalog.GetGamePasses() do
		gamePassesByName[pass.displayName] = pass
	end

	local gamePassesFrame = body:FindFirstChild("GamePasses") :: Frame?
	if gamePassesFrame then
		for _, card in gamePassesFrame:GetChildren() do
			if not card:IsA("GuiObject") then continue end
			local label = card:FindFirstChild("ItemLabel")
			if label and label:IsA("TextLabel") then
				local pass = gamePassesByName[label.Text]
				if pass then wireGamePassCard(card, pass) end
			end
		end
	end

	-- VIP card is a top-level frame
	local vipCard = body:FindFirstChild("VIP")
	if vipCard then
		local pass = gamePassesByName["VIP"]
		if pass then wireGamePassCard(vipCard, pass) end

		-- Rewrite any stale "2x Cash" text authored in Studio → "1.5x Cash Rewards".
		for _, d in vipCard:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				local t = string.lower(d.Text)
				if string.find(t, "2x%s*cash") then
					d.Text = "1.5x Cash Rewards"
				end
			end
		end
	end

	-- Close button
	local header = shopFrame:FindFirstChild("Header") :: Frame?
	if header then
		local closeBtn = header:FindFirstChild("CloseButton")
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.Activated:Connect(function()
				LuckyBlockShopUI.Close()
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Open / Close
---------------------------------------------------------------------------

local shopFrame: Frame? = nil
local isVisible = false
local isAnimating = false

function LuckyBlockShopUI.Open(focusBlockId: string?)
	if isVisible or isAnimating then return end
	if not shopFrame then return end
	UIManager.CloseOthers("Shop")
	isAnimating = true

	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	local targetSize = shopFrame:GetAttribute("OrigSize") or shopFrame.Size
	shopFrame.Size = UDim2.new(
		targetSize.X.Scale * 0.7, targetSize.X.Offset * 0.7,
		targetSize.Y.Scale * 0.7, targetSize.Y.Offset * 0.7
	)
	shopFrame.Visible = true
	shopFrame.SelectionGroup = true
	TweenService:Create(shopFrame, BOUNCE_IN, { Size = targetSize }):Play()

	isVisible = true
	task.delay(BOUNCE_IN.Time, function()
		isAnimating = false
		focusInto(shopFrame)
	end)

	-- Auto-scroll: legendary block lives at the bottom of the Body scrolling
	-- frame, so when it's the focus, jump the scroll to max Y once layout
	-- has settled.
	if focusBlockId == "legendary_block" then
		local body = shopFrame:FindFirstChild("Body")
		if body and body:IsA("ScrollingFrame") then
			task.defer(function()
				local sf = body :: ScrollingFrame
				local canvas = sf.AbsoluteCanvasSize
				sf.CanvasPosition = Vector2.new(0, math.max(0, canvas.Y))
			end)
		end
	end
end

function LuckyBlockShopUI.Close()
	if not isVisible then return end
	if not shopFrame then return end
	isAnimating = true

	local targetSize = shopFrame:GetAttribute("OrigSize") or shopFrame.Size
	local shrunkSize = UDim2.new(
		targetSize.X.Scale * 0.7, targetSize.X.Offset * 0.7,
		targetSize.Y.Scale * 0.7, targetSize.Y.Offset * 0.7
	)
	local tween = TweenService:Create(shopFrame, BOUNCE_OUT, { Size = shrunkSize })
	tween:Play()
	tween.Completed:Connect(function()
		shopFrame.Visible = false
		shopFrame.Size = targetSize
		isVisible = false
		isAnimating = false
		clearFocus(shopFrame)
	end)
end

function LuckyBlockShopUI.Toggle()
	if isVisible then
		LuckyBlockShopUI.Close()
	else
		LuckyBlockShopUI.Open()
	end
end

function LuckyBlockShopUI.IsOpen(): boolean
	return isVisible
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function LuckyBlockShopUI.Start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then
		warn("[Shop] ScreenGui not found")
		return
	end

	local shop = screenGui:FindFirstChild("Shop") :: Frame?
	if not shop then
		warn("[Shop] Shop frame not found")
		return
	end

	shopFrame = shop
	shopFrame:SetAttribute("OrigSize", shopFrame.Size)
	shopFrame.Visible = false

	buildShop(shopFrame)

	-- Hook up shop open buttons
	local shopButtons = screenGui:FindFirstChild("ShopButtons")
	if shopButtons then
		for _, child in shopButtons:GetChildren() do
			if child:IsA("Frame") and child.Name == "ShopButton" then
				local overlay = child:FindFirstChild("ShopClickOverlay")
				if not overlay then
					overlay = Instance.new("TextButton")
					overlay.Name = "ShopClickOverlay"
					overlay.Size = UDim2.fromScale(1, 1)
					overlay.BackgroundTransparency = 1
					overlay.Text = ""
					overlay.ZIndex = 10
					overlay.Selectable = true
					overlay.Parent = child
				end
				local btn = overlay :: TextButton
				btn.Selectable = true
				btn.Activated:Connect(function()
					LuckyBlockShopUI.Toggle()
				end)
			end
		end
	end

	-- Listen for server telling us to open the shop
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local openShopRemote = remotes:WaitForChild("OpenLuckyBlockShop", 5)
	if openShopRemote then
		local remote = openShopRemote :: RemoteEvent
		remote.OnClientEvent:Connect(function(blockId)
			LuckyBlockShopUI.Open(blockId)
		end)
	end

	UIManager.Register("Shop", LuckyBlockShopUI.Close, LuckyBlockShopUI.IsOpen)

	-- CosmeticsShop: wire up cards and buttons
	local cosmeticsShop = screenGui:FindFirstChild("CosmeticsShop") :: Frame?
	if cosmeticsShop then
		cosmeticsShop:SetAttribute("OrigSize", cosmeticsShop.Size)
		cosmeticsShop.Visible = false

		-- Collected at card-wire time below; mutated from inside the `if
		-- cosBody` block, read from the attribute-change handler at the end
		-- of this scope.
		local cosCardsOuter: { Frame } = {}
		local restrictionBanner: TextLabel? = nil
		local function ensureRestrictionBanner(): TextLabel
			if restrictionBanner then return restrictionBanner end
			local banner = Instance.new("TextLabel")
			banner.Name = "PaidRandomItemsRestrictedBanner"
			banner.Size = UDim2.new(1, -40, 0, 70)
			banner.Position = UDim2.new(0.5, 0, 0.5, 0)
			banner.AnchorPoint = Vector2.new(0.5, 0.5)
			banner.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
			banner.BackgroundTransparency = 0.05
			banner.BorderSizePixel = 0
			banner.Text = "Paid random items aren't allowed in your region."
			banner.TextColor3 = Color3.fromRGB(255, 230, 200)
			banner.TextScaled = true
			banner.Font = Enum.Font.FredokaOne
			banner.ZIndex = 50
			banner.Visible = false
			banner.Parent = cosmeticsShop
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 12)
			corner.Parent = banner
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 140, 90)
			stroke.Thickness = 2
			stroke.Parent = banner
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 12)
			padding.PaddingRight = UDim.new(0, 12)
			padding.Parent = banner
			restrictionBanner = banner
			return banner
		end
		local function applyCosmeticsRestriction()
			local hide = localPlayer:GetAttribute("ArePaidRandomItemsRestricted") == true
			for _, card in cosCardsOuter do
				card.Visible = not hide
			end
			local banner = ensureRestrictionBanner()
			banner.Visible = hide
		end

		local cosBody = cosmeticsShop:FindFirstChild("Body") :: ScrollingFrame?
		if cosBody then
			local cosRemotes = ReplicatedStorage:WaitForChild("Remotes")
			local cosPurchaseRemote = cosRemotes:WaitForChild("PurchaseLuckyBlock") :: RemoteEvent

			-- Build lookup: displayName -> catalog entry for cosmetics blocks
			local cosmeticsByName: { [string]: any } = {}
			for _, entry in LuckyBlockCatalog.GetAll() do
				if entry.shopType == "cosmetics" then
					cosmeticsByName[entry.displayName] = entry
				end
			end

			-- Wire each manually-designed card by matching its ItemLabel text
			for _, card in cosBody:GetChildren() do
				if not card:IsA("Frame") then continue end

				local itemLabel = card:FindFirstChild("ItemLabel") :: TextLabel?
				if not itemLabel then continue end

				local entry = cosmeticsByName[itemLabel.Text]
				if not entry then continue end

				table.insert(cosCardsOuter, card)

				-- Block image
				local blockImage = card:FindFirstChild("BlockImage") :: ImageLabel?
				if blockImage and entry.imageId then
					blockImage.Image = "rbxassetid://" .. tostring(entry.imageId)
				end

				local cashPrice = if #entry.buyOptions > 0 then entry.buyOptions[1].price else 0
				local qty = if #entry.buyOptions > 0 then entry.buyOptions[1].quantity else 1

				-- Wire RobuxButtons (cash + Robux). RobuxButton is itself a
				-- TextButton, so its own Size defines the hit region — but we
				-- still add a child overlay so that if any sibling decoration
				-- has a higher ZIndex with Active = true, touches on the
				-- visible button still register.
				for _, child in card:GetChildren() do
					if child:IsA("TextButton") and child.Name == "RobuxButton" then
						local rl = child:FindFirstChild("robuxLabel") :: TextLabel?
						if not rl then continue end

						if rl.Text:match("%$") then
							-- Cash buy button
							rl.Text = "$" .. tostring(cashPrice)
							local cb = child
							local onClick = function()
								popButton(cb)
								cosPurchaseRemote:FireServer(entry.id, qty)
							end
							cb.Activated:Connect(onClick)
							addFullAreaOverlay(cb, "TapArea").Activated:Connect(onClick)
						else
							-- Robux buy button — Roblox Robux glyph + price
							if entry.robuxPrice then
								rl.Text = utf8.char(0xE002) .. tostring(entry.robuxPrice)
							end
							local cb = child
							local onClick = function()
								popButton(cb)
								local productId = entry.robuxProductId or 0
								if productId > 0 then
									MarketplaceService:PromptProductPurchase(localPlayer, productId)
								end
							end
							cb.Activated:Connect(onClick)
							addFullAreaOverlay(cb, "TapArea").Activated:Connect(onClick)
						end
					end
				end

				-- Wire SubmitButton if present (alternative button pattern)
				local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
				if submitFrame then
					local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
					if submitBtn then
						submitBtn.Text = "$" .. tostring(cashPrice)
						local tap = addFullAreaOverlay(submitFrame, "TapArea")
						tap.Activated:Connect(function()
							popButton(submitFrame)
							cosPurchaseRemote:FireServer(entry.id, qty)
						end)
					end
				end

				-- Wire item slots (% labels, chair names, ViewportFrames)
				local chairTemplates = ReplicatedStorage:FindFirstChild("ChairTemplates")
				local chances = LuckyBlockCatalog.GetChances(entry.id)
				local possibleItems = card:FindFirstChild("PossibleItems") :: Frame?
				if possibleItems then
					local slots: { ImageButton } = {}
					for _, child in possibleItems:GetChildren() do
						if child:IsA("ImageButton") then
							table.insert(slots, child)
						end
					end

					local sortedLoot = table.clone(entry.lootTable)
					table.sort(sortedLoot, function(a, b) return a.weight > b.weight end)

					for i, slot in slots do
						local loot = sortedLoot[i]
						if not loot then
							slot.Visible = false
							continue
						end

						local chairEntry = ChairCatalog.Get(loot.chairId)
						local pct = chances[loot.chairId] or 0

						local rarityLabel = slot:FindFirstChild("RarityLabel") :: TextLabel?
						if rarityLabel then
							rarityLabel.Text = `{pct}%`
						end

						local nameLabel = slot:FindFirstChild("ItemNameLabel") :: TextLabel?
						if nameLabel and chairEntry then
							nameLabel.Text = chairEntry.displayName
						end

						local slotImage = slot:FindFirstChild("ItemImage") :: ImageLabel?
						if slotImage and chairEntry and chairTemplates then
							local template = chairTemplates:FindFirstChild(chairEntry.modelName)
							if template and template:IsA("Model") then
								for _, child in slot:GetChildren() do
									if child:IsA("ViewportFrame") then
										child:Destroy()
									end
								end
								local vf = Instance.new("ViewportFrame")
								vf.Name = "ItemViewport"
								vf.Size = slotImage.Size
								vf.Position = slotImage.Position
								vf.AnchorPoint = slotImage.AnchorPoint
								vf.BackgroundTransparency = 1
								vf.ZIndex = slotImage.ZIndex
								vf.Parent = slot
								setupViewport(vf, template)
								slotImage.Visible = false
							end
						end
					end
				end
			end
		end

		local cosmeticsVisible = false
		local cosmeticsAnimating = false

		-- Snappier open for walk-up: tighter duration, smaller start scale,
		-- less overshoot. Walk-up should feel instant.
		local COSMETICS_OPEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local function openCosmetics()
			if cosmeticsVisible or cosmeticsAnimating then return end
			UIManager.CloseOthers("Cosmetics")
			cosmeticsAnimating = true
			cosmeticsShop.AnchorPoint = Vector2.new(0.5, 0.5)
			local targetSize = cosmeticsShop:GetAttribute("OrigSize") or cosmeticsShop.Size
			cosmeticsShop.Size = UDim2.new(
				targetSize.X.Scale * 0.85, targetSize.X.Offset * 0.85,
				targetSize.Y.Scale * 0.85, targetSize.Y.Offset * 0.85
			)
			cosmeticsShop.Visible = true
			cosmeticsShop.SelectionGroup = true
			TweenService:Create(cosmeticsShop, COSMETICS_OPEN, { Size = targetSize }):Play()
			cosmeticsVisible = true
			task.delay(COSMETICS_OPEN.Time, function()
				cosmeticsAnimating = false
				focusInto(cosmeticsShop)
			end)
		end

		local function closeCosmetics()
			if not cosmeticsVisible or cosmeticsAnimating then return end
			cosmeticsAnimating = true
			local targetSize = cosmeticsShop:GetAttribute("OrigSize") or cosmeticsShop.Size
			local shrunkSize = UDim2.new(
				targetSize.X.Scale * 0.7, targetSize.X.Offset * 0.7,
				targetSize.Y.Scale * 0.7, targetSize.Y.Offset * 0.7
			)
			local tween = TweenService:Create(cosmeticsShop, BOUNCE_OUT, { Size = shrunkSize })
			tween:Play()
					tween.Completed:Connect(function()
				cosmeticsShop.Visible = false
				cosmeticsShop.Size = targetSize
				cosmeticsVisible = false
				cosmeticsAnimating = false
				clearFocus(cosmeticsShop)
			end)
		end

		local function toggleCosmetics()
			if cosmeticsVisible then closeCosmetics() else openCosmetics() end
		end

		UIManager.Register("Cosmetics", closeCosmetics, function() return cosmeticsVisible end)
		applyCosmeticsRestriction()
		localPlayer:GetAttributeChangedSignal("ArePaidRandomItemsRestricted"):Connect(applyCosmeticsRestriction)

		-- CosmeticsButton is now used for Rewards panel (wired in RewardsUI.luau)

		-- Close button inside CosmeticsShop
		local cosHeader = cosmeticsShop:FindFirstChild("Header") :: Frame?
		if cosHeader then
			local closeBtn = cosHeader:FindFirstChild("CloseButton")
			if closeBtn and closeBtn:IsA("GuiButton") then
				closeBtn.Activated:Connect(closeCosmetics)
			end
		end

		-- Listen for server telling us to open the cosmetics shop (from ProximityPrompt)
		local openCosRemote = remotes:WaitForChild("OpenCosmeticsShop", 5)
		if openCosRemote then
			local remote = openCosRemote :: RemoteEvent
			remote.OnClientEvent:Connect(function()
				openCosmetics()
			end)
		end

		-- Close listener: server ZoneTrigger fires CloseCosmeticsShop on exit.
		local closeCosRemote = remotes:WaitForChild("CloseCosmeticsShop", 5)
		if closeCosRemote then
			(closeCosRemote :: RemoteEvent).OnClientEvent:Connect(closeCosmetics)
		end
	end
end

return LuckyBlockShopUI
