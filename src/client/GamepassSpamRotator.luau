-- GamepassSpamRotator
-- Rotates promotional items in the "IngameAds" frame on the right side of the
-- screen. Always visible in the lobby. Each promo shows for a set duration
-- then swaps to the next.
--
-- Separate from GamepassSpam (which HintShop uses during rounds for hints).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local PromptPurchase = require(script.Parent:WaitForChild("ui"):WaitForChild("PromptPurchase"))

local SWAP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SWAP_IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function getOrCreateScale(slot: Frame): UIScale
	local s = slot:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Parent = slot
	end
	return s
end

local ChairCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChairCatalog"))
local LuckyBlockShopUI = require(script.Parent:WaitForChild("LuckyBlockShopUI"))

local HINT_ICON = "rbxassetid://137240287993410"
local ROBUX_GLYPH = utf8.char(0xE002)

local function setupChairViewport(viewport: ViewportFrame, model: Model, flipSeat: boolean?, zoom: number?)
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
	viewport.BackgroundTransparency = 1
end

local function setItemLabels(itemFrame: Frame, text: string)
	for _, d in itemFrame:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "chairName" then
			d.Text = text
		end
	end
end

local function findItemImageContainer(itemFrame: Frame): (ImageLabel?, ImageLabel?)
	-- Returns (container ImageLabel that holds ItemImage, the ItemImage itself)
	for _, d in itemFrame:GetDescendants() do
		if d:IsA("ImageLabel") and d.Name == "ItemImage" then
			return d.Parent :: ImageLabel?, d
		end
	end
	return nil, nil
end

local ROTATE_INTERVAL = 8 -- seconds per promo before rotating

type PromoItem = {
	label: string,
	robuxText: string,
	image: string,
	onClick: ((Player) -> ())?,
}

type PromoEntry = {
	id: string,
	items: { PromoItem },
}

local GamepassSpamRotator = {}

function GamepassSpamRotator.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then
		warn("[GamepassSpamRotator] ScreenGui not found")
		return
	end

	local adsFrame = screenGui:WaitForChild("IngameAds", 10) :: Frame?
	if not adsFrame then
		warn("[GamepassSpamRotator] IngameAds not found")
		return
	end

	local starterPackFrame = screenGui:FindFirstChild("StarterPack") :: Frame?

	-- Collect item slots. If the Studio frame only has Item1, auto-clone it
	-- into Item2 so we can always show two ads side-by-side. The clone is
	-- offset downward by its own height (+8px gap) unless the ads frame has
	-- a UIListLayout / UIGridLayout that will position it automatically.
	local itemSlots: { Frame } = {}
	for i = 1, 3 do
		local slot = adsFrame:FindFirstChild("Item" .. i) :: Frame?
		if slot then
			table.insert(itemSlots, slot)
		end
	end
	if #itemSlots < 2 and itemSlots[1] then
		local src = itemSlots[1]
		local clone = src:Clone()
		clone.Name = "Item2"
		clone.Parent = adsFrame
		local hasLayout = adsFrame:FindFirstChildOfClass("UIListLayout")
			or adsFrame:FindFirstChildOfClass("UIGridLayout")
		if not hasLayout then
			local srcSize = src.AbsoluteSize
			local h = if srcSize.Y > 0 then srcSize.Y + 8 else 120
			clone.Position = UDim2.new(
				src.Position.X.Scale, src.Position.X.Offset,
				src.Position.Y.Scale, src.Position.Y.Offset + h
			)
		end
		table.insert(itemSlots, clone)
	end

	---------------------------------------------------------------------------
	-- StarterPack wiring
	---------------------------------------------------------------------------
	if starterPackFrame then
		starterPackFrame.Visible = false
		UIManager.Register(
			"StarterPack",
			function() (starterPackFrame :: Frame).Visible = false end,
			function() return (starterPackFrame :: Frame).Visible end
		)
		local header = starterPackFrame:FindFirstChild("Header")
		if header then
			local closeBtn = header:FindFirstChild("CloseButton") :: ImageButton?
			if closeBtn then
				closeBtn.Activated:Connect(function()
					starterPackFrame.Visible = false
				end)
			end
		end

		local submitFrame = starterPackFrame:FindFirstChild("SubmitButton")
		if submitFrame then
			local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
			if submitBtn then
				submitBtn.Activated:Connect(function()
					PromptPurchase.GamePass(localPlayer, 1796993729)
				end)
			end
		end

		-- Reward slots (three children of Body.Frame, all named "Item1")
		local body = starterPackFrame:FindFirstChild("Body")
		local bodyInner = body and body:FindFirstChild("Frame")
		if bodyInner then
			local slots: { Frame } = {}
			for _, c in bodyInner:GetChildren() do
				if c:IsA("Frame") then
					table.insert(slots, c)
				end
			end

			-- Slot 2 (middle): Office Chair viewport
			local slot2 = slots[2]
			if slot2 then
				setItemLabels(slot2, "Office Chair")
				local container, itemImage = findItemImageContainer(slot2)
				if container and itemImage then
					itemImage.ImageTransparency = 1
					local existing = container:FindFirstChild("ChairViewport") :: ViewportFrame?
					if not existing then
						local vf = Instance.new("ViewportFrame")
						vf.Name = "ChairViewport"
						vf.Size = UDim2.fromScale(1, 1)
						vf.BackgroundTransparency = 1
						vf.ZIndex = itemImage.ZIndex + 1
						vf.Parent = container
						existing = vf
					end
					task.spawn(function()
						local templates = ReplicatedStorage:WaitForChild("ChairTemplates", 15)
						if not templates then return end
						local model = templates:WaitForChild("OfficeChair", 10)
						if model and model:IsA("Model") and existing then
							local entry = ChairCatalog.Get("office_chair")
							local flip = if entry and entry.viewportFlip ~= nil then entry.viewportFlip else (entry and entry.flipSeat)
							setupChairViewport(existing, model, flip, entry and entry.viewportZoom)
						end
					end)
				end
			end

			-- Slot 3 (right): 3 Hints
			local slot3 = slots[3]
			if slot3 then
				setItemLabels(slot3, "3 Hints")
				local _container, itemImage = findItemImageContainer(slot3)
				if itemImage then
					itemImage.Image = HINT_ICON
					itemImage.ImageTransparency = 0
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- Promo library
	---------------------------------------------------------------------------
	local starterPackItem: PromoItem = {
		label = "Starter Pack",
		robuxText = ROBUX_GLYPH .. "19",
		image = "rbxassetid://85951385651654",
		onClick = function(_player)
			if starterPackFrame then
				UIManager.CloseOthers("StarterPack")
				starterPackFrame.Visible = true
			end
		end,
	}
	local vipItem: PromoItem = {
		label = "VIP",
		robuxText = ROBUX_GLYPH .. "49",
		image = "rbxassetid://128383063987894",
		onClick = function(player)
			PromptPurchase.GamePass(player, 1796710377)
		end,
	}
	local doubleCashItem: PromoItem = {
		label = "2x Cash",
		robuxText = ROBUX_GLYPH .. "99",
		image = "rbxassetid://83945987909294",
		onClick = function(player)
			PromptPurchase.GamePass(player, 1797672278)
		end,
	}
	local doubleWinsItem: PromoItem = {
		label = "2x Wins",
		robuxText = ROBUX_GLYPH .. "99",
		image = "rbxassetid://106286618566178",
		onClick = function(player)
			PromptPurchase.GamePass(player, 1796963414)
		end,
	}
	local doubleStreakItem: PromoItem = {
		label = "2x Streak",
		robuxText = ROBUX_GLYPH .. "99",
		image = "rbxassetid://114192556144330",
		onClick = function(player)
			PromptPurchase.GamePass(player, 1797239408)
		end,
	}
	local glacialBlockItem: PromoItem = {
		label = "Glacial Block",
		robuxText = ROBUX_GLYPH .. "99",
		image = "rbxassetid://137563051885989",
		onClick = function(_player)
			LuckyBlockShopUI.Open()
		end,
	}
	local stormBlockItem: PromoItem = {
		label = "Storm Block",
		robuxText = ROBUX_GLYPH .. "99",
		image = "rbxassetid://116470141222904",
		onClick = function(_player)
			LuckyBlockShopUI.Open()
		end,
	}

	-- Flat pool of all promo items. Each rotation picks 2 random distinct
	-- items to show together.
	local itemPool: { PromoItem } = {
		starterPackItem, vipItem,
		doubleCashItem, doubleWinsItem, doubleStreakItem,
		glacialBlockItem, stormBlockItem,
	}

	-- Paid random items regional restriction: pull the two lucky-block promos
	-- from the rotation pool entirely for restricted players. Reapplied if
	-- the server-side policy resolves asynchronously after startup.
	local randomItemPromos = { glacialBlockItem, stormBlockItem }
	local function applyPolicyToPool()
		local restricted = localPlayer:GetAttribute("ArePaidRandomItemsRestricted") == true
		-- Rebuild pool: always-safe promos + lucky blocks only if unrestricted
		table.clear(itemPool)
		table.insert(itemPool, starterPackItem)
		table.insert(itemPool, vipItem)
		table.insert(itemPool, doubleCashItem)
		table.insert(itemPool, doubleWinsItem)
		table.insert(itemPool, doubleStreakItem)
		if not restricted then
			for _, p in randomItemPromos do
				table.insert(itemPool, p)
			end
		end
	end
	applyPolicyToPool()
	localPlayer:GetAttributeChangedSignal("ArePaidRandomItemsRestricted"):Connect(applyPolicyToPool)

	local function pickTwoRandom(lastA: PromoItem?, lastB: PromoItem?): (PromoItem, PromoItem)
		-- Avoid repeating the exact same pair back-to-back when possible.
		local aIdx = math.random(1, #itemPool)
		local bIdx
		repeat
			bIdx = math.random(1, #itemPool)
		until bIdx ~= aIdx
		local a, b = itemPool[aIdx], itemPool[bIdx]
		if lastA and lastB and ((a == lastA and b == lastB) or (a == lastB and b == lastA)) then
			-- One more reshuffle attempt; acceptable to skip if all other
			-- picks also collide (tiny pool case).
			bIdx = ((bIdx) % #itemPool) + 1
			if bIdx == aIdx then bIdx = ((bIdx) % #itemPool) + 1 end
			b = itemPool[bIdx]
		end
		return a, b
	end

	local promos: { PromoEntry } = {} -- unused now; see rotation loop below

	---------------------------------------------------------------------------
	-- Click wiring
	---------------------------------------------------------------------------
	local activeConnections: { RBXScriptConnection } = {}

	local function clearConnections()
		for _, conn in activeConnections do
			conn:Disconnect()
		end
		table.clear(activeConnections)
	end

	local function writeSlotContent(slot: Frame, promoItem: PromoItem?)
		if not promoItem then
			slot.Visible = false
			return
		end
		slot.Visible = true
		local lbl = slot:FindFirstChild("ItemLabel") :: TextLabel?
		local rbx = slot:FindFirstChild("RobuxLabel") :: TextLabel?
		local img = slot:FindFirstChild("ItemImage") :: ImageButton?

		if lbl then
			lbl.Text = promoItem.label
		end
		if rbx then
			if promoItem.robuxText ~= "" then
				rbx.Text = promoItem.robuxText
				rbx.Visible = true
			else
				rbx.Visible = false
			end
		end
		if img and promoItem.image ~= "" then
			img.Image = promoItem.image
		end

		local clickArea = slot:FindFirstChild("PromoClickArea")
		if not clickArea then
			local btn = Instance.new("TextButton")
			btn.Name = "PromoClickArea"
			btn.Size = UDim2.fromScale(1, 1)
			btn.BackgroundTransparency = 1
			btn.Text = ""
			btn.ZIndex = 10
			btn.Parent = slot
			clickArea = btn
		end

		if promoItem.onClick then
			local conn = (clickArea :: TextButton).Activated:Connect(function()
				promoItem.onClick(localPlayer)
			end)
			table.insert(activeConnections, conn)
		end
	end

	-- Stagger the two slots slightly for a nicer effect.
	local function applyPromo(promo: PromoEntry)
		clearConnections()

		for i, slot in itemSlots do
			local promoItem = promo.items[i]
			local scale = getOrCreateScale(slot)
			local stagger = (i - 1) * 0.07

			task.spawn(function()
				if stagger > 0 then task.wait(stagger) end

				-- Shrink-out the old content
				local outTween = TweenService:Create(scale, SWAP_OUT, { Scale = 0.3 })
				outTween:Play()
				outTween.Completed:Wait()

				-- Swap in the new content while hidden-small
				writeSlotContent(slot, promoItem)

				-- Pop-in with slight overshoot
				scale.Scale = 0.3
				TweenService:Create(scale, SWAP_IN, { Scale = 1 }):Play()
			end)
		end
	end

	---------------------------------------------------------------------------
	-- Hide during matches, show in lobby
	---------------------------------------------------------------------------
	local inMatch = false

	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	remotes:WaitForChild("MatchStart").OnClientEvent:Connect(function()
		inMatch = true
		adsFrame.Visible = false
	end)

	remotes:WaitForChild("MatchEnd").OnClientEvent:Connect(function()
		inMatch = false
		adsFrame.Visible = true
	end)

	---------------------------------------------------------------------------
	-- Sunburst spin (eye-catching rotation behind each item icon).
	-- Looks for any descendant named "Sunburst" / "SunBurst" / "Burst" inside
	-- the ad slots and rotates it continuously.
	---------------------------------------------------------------------------
	local sunbursts: { GuiObject } = {}
	for _, slot in itemSlots do
		for _, d in slot:GetDescendants() do
			if d:IsA("GuiObject") then
				local n = d.Name:lower()
				if n == "sunburst" or n == "burst" then
					table.insert(sunbursts, d)
				end
			end
		end
	end
	if #sunbursts > 0 then
		local SPIN_DEG_PER_SEC = 40 -- one full revolution every 9s
		RunService.Heartbeat:Connect(function(dt)
			if not adsFrame.Visible then return end
			local delta = SPIN_DEG_PER_SEC * dt
			for _, sb in sunbursts do
				sb.Rotation = (sb.Rotation + delta) % 360
			end
		end)
	end

	---------------------------------------------------------------------------
	-- Rotation loop
	---------------------------------------------------------------------------
	adsFrame.Visible = true

	task.spawn(function()
		local lastA: PromoItem? = nil
		local lastB: PromoItem? = nil
		while true do
			if inMatch then
				task.wait(1)
				continue
			end

			local a, b = pickTwoRandom(lastA, lastB)
			applyPromo({ id = "random_pair", items = { a, b } })
			lastA, lastB = a, b

			local elapsed = 0
			while elapsed < ROTATE_INTERVAL do
				if inMatch then break end
				task.wait(0.5)
				elapsed += 0.5
			end
		end
	end)
end

return GamepassSpamRotator
