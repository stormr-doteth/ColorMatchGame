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
-- Wire a dev product card (cash or wins) — finds SubmitButton inside
---------------------------------------------------------------------------

local function wireDevProductCard(card: Instance, product)
	local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
	if not submitFrame then return end
	local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
	if not submitBtn then return end

	submitBtn.Activated:Connect(function()
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

	submitBtn.Activated:Connect(function()
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

	-- Lucky Blocks: wire existing manually-designed cards (named LuckyBlock_{id})
	for _, entry in LuckyBlockCatalog.GetAll() do
		if entry.shopType == "cosmetics" then continue end
		local card = body:FindFirstChild("LuckyBlock_" .. entry.id) :: Frame?
		if card then
			wireBlockCard(card, entry, purchaseRemote)
		end
	end

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

	-- CosmeticsShop: wire up cards and buttons
	local cosmeticsShop = screenGui:FindFirstChild("CosmeticsShop") :: Frame?
	if cosmeticsShop then
		cosmeticsShop:SetAttribute("OrigSize", cosmeticsShop.Size)
		cosmeticsShop.Visible = false

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

				local cashPrice = if #entry.buyOptions > 0 then entry.buyOptions[1].price else 0
				local qty = if #entry.buyOptions > 0 then entry.buyOptions[1].quantity else 1

				-- Wire RobuxButtons (cash + Robux)
				for _, child in card:GetChildren() do
					if child:IsA("TextButton") and child.Name == "RobuxButton" then
						local rl = child:FindFirstChild("robuxLabel") :: TextLabel?
						if not rl then continue end

						if rl.Text:match("%$") then
							-- Cash buy button
							rl.Text = "$" .. tostring(cashPrice)
							child.Activated:Connect(function()
								popButton(child)
								cosPurchaseRemote:FireServer(entry.id, qty)
							end)
						else
							-- Robux buy button (price text set in UI)
							child.Activated:Connect(function()
								popButton(child)
								local productId = entry.robuxProductId or 0
								if productId > 0 then
									MarketplaceService:PromptProductPurchase(localPlayer, productId)
								end
							end)
						end
					end
				end

				-- Wire SubmitButton if present (alternative button pattern)
				local submitFrame = card:FindFirstChild("SubmitButton") :: Frame?
				if submitFrame then
					local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
					if submitBtn then
						submitBtn.Text = "$" .. tostring(cashPrice)
						submitBtn.Activated:Connect(function()
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

		local function openCosmetics()
			if cosmeticsVisible or cosmeticsAnimating then return end
			UIManager.CloseOthers("Cosmetics")
			cosmeticsAnimating = true
			cosmeticsShop.AnchorPoint = Vector2.new(0.5, 0.5)
			local targetSize = cosmeticsShop:GetAttribute("OrigSize") or cosmeticsShop.Size
			cosmeticsShop.Size = UDim2.new(
				targetSize.X.Scale * 0.7, targetSize.X.Offset * 0.7,
				targetSize.Y.Scale * 0.7, targetSize.Y.Offset * 0.7
			)
			cosmeticsShop.Visible = true
			TweenService:Create(cosmeticsShop, BOUNCE_IN, { Size = targetSize }):Play()
			cosmeticsVisible = true
			task.delay(BOUNCE_IN.Time, function() cosmeticsAnimating = false end)
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
			end)
		end

		local function toggleCosmetics()
			if cosmeticsVisible then closeCosmetics() else openCosmetics() end
		end

		UIManager.Register("Cosmetics", closeCosmetics, function() return cosmeticsVisible end)

		-- Hook up CosmeticsButton
		if shopButtons then
			local cosmBtn = shopButtons:FindFirstChild("CosmeticsButton")
			if cosmBtn then
				local overlay = cosmBtn:FindFirstChild("CosmeticsClickOverlay")
				if not overlay then
					overlay = Instance.new("TextButton")
					overlay.Name = "CosmeticsClickOverlay"
					overlay.Size = UDim2.fromScale(1, 1)
					overlay.BackgroundTransparency = 1
					overlay.Text = ""
					overlay.ZIndex = 10
					overlay.Parent = cosmBtn
				end
				local btn = overlay :: TextButton
				btn.Activated:Connect(toggleCosmetics)
			end
		end

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
	end
end

return LuckyBlockShopUI
