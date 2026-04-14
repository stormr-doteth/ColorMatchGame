-- LuckyBlockShopUI
-- Wires up the manually-designed Shop UI (StarterGui.ScreenGui.Shop).
-- All visual design is done in Studio — this module only:
--   • Populates lucky block cards from LuckyBlockCatalog (clone Item1 template)
--   • Wires buy buttons for blocks, coin packs, and game passes
--   • Sets prices and % chance labels from catalog data
--   • Handles open/close with bouncy tweens
--   • Checks gamepass ownership and shows "Owned"

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function setupViewport(viewport: ViewportFrame, model: Model)
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

	local maxExtent = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local cameraDistance = maxExtent * 1.4 + 0.5

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

	-- Buy button
	local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
	if submitFrame then
		local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
		if submitBtn then
			local price = if #entry.buyOptions > 0 then entry.buyOptions[1].price else 0
			submitBtn.Text = ROBUX_ICON .. " " .. tostring(price)
			submitBtn.Activated:Connect(function()
				popButton(submitFrame)
				local qty = if #entry.buyOptions > 0 then entry.buyOptions[1].quantity else 1
				purchaseRemote:FireServer(entry.id, qty)
			end)
		end
	end

	-- Possible items: populate % and ViewportFrames
	local possibleItems = card:FindFirstChild("PossibleItems") :: Frame?
	if not possibleItems then return end

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

		local slotLabel = slot:FindFirstChild("ItemLabel") :: TextLabel?
		if slotLabel then
			slotLabel.Text = `{pct}%`
		end

		local slotImage = slot:FindFirstChild("ItemImage") :: ImageLabel?
		if slotImage and chairEntry and chairTemplates then
			local template = chairTemplates:FindFirstChild(chairEntry.modelName)
			if template and template:IsA("Model") then
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

---------------------------------------------------------------------------
-- Wire up a gamepass card (manually designed frame)
---------------------------------------------------------------------------

local function wirePassCard(card: Frame, pass)
	local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
	if not submitFrame then return end

	local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
	if not submitBtn then return end

	submitBtn.Text = ROBUX_ICON .. " " .. tostring(pass.robuxPrice)

	submitBtn.Activated:Connect(function()
		popButton(submitFrame)
		if pass.gamePassId > 0 then
			MarketplaceService:PromptGamePassPurchase(localPlayer, pass.gamePassId)
		end
	end)

	-- Check ownership
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
-- Wire up a coin pack card (manually designed frame)
---------------------------------------------------------------------------

local function wireCoinCard(card: Frame, pack)
	local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
	if not submitFrame then return end

	local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
	if not submitBtn then return end

	submitBtn.Text = ROBUX_ICON .. " " .. tostring(pack.robuxPrice)

	submitBtn.Activated:Connect(function()
		popButton(submitFrame)
		if pack.productId > 0 then
			MarketplaceService:PromptProductPurchase(localPlayer, pack.productId)
		end
	end)
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

	-- Lucky Blocks: find Item template, clone per catalog entry
	local template: Frame? = nil
	local existingItems: { Frame } = {}
	for _, child in body:GetChildren() do
		if child:IsA("Frame") and child.Name:match("^Item%d") then
			table.insert(existingItems, child)
			if not template then
				template = child
			end
		end
	end

	for _, item in existingItems do
		item.Visible = false
	end

	if template then
		for idx, entry in LuckyBlockCatalog.GetAll() do
			local card = template:Clone()
			card.Name = "LuckyBlock_" .. entry.id
			card.Visible = true
			card.LayoutOrder = idx
			card.Parent = body
			wireBlockCard(card, entry, purchaseRemote)
		end
	end

	-- Game Passes: wire existing frames
	local gamePassesFrame = body:FindFirstChild("GamePasses") :: Frame?
	if gamePassesFrame then
		for _, pass in ShopCatalog.GetGamePasses() do
			local frameName = pass.frameName
			if not frameName then continue end
			local card = gamePassesFrame:FindFirstChild(frameName) :: Frame?
			if card then
				wirePassCard(card, pass)
			end
		end
	end

	-- Coin Packs: wire existing frames (look for CoinPacks frame or individual cards)
	local coinPacksFrame = body:FindFirstChild("CoinPacks") :: Frame?
	if coinPacksFrame then
		for _, pack in ShopCatalog.GetCoinPacks() do
			local frameName = pack.frameName
			if not frameName then continue end
			local card = coinPacksFrame:FindFirstChild(frameName) :: Frame?
			if card then
				wireCoinCard(card, pack)
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

function LuckyBlockShopUI.Open()
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
	TweenService:Create(shopFrame, BOUNCE_IN, { Size = targetSize }):Play()

	isVisible = true
	task.delay(BOUNCE_IN.Time, function() isAnimating = false end)
end

function LuckyBlockShopUI.Close()
	if not isVisible or isAnimating then return end
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
					overlay.Parent = child
				end
				local btn = overlay :: TextButton
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
		remote.OnClientEvent:Connect(function()
			LuckyBlockShopUI.Open()
		end)
	end

	UIManager.Register("Shop", LuckyBlockShopUI.Close, LuckyBlockShopUI.IsOpen)
end

return LuckyBlockShopUI
