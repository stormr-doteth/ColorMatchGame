-- BoostIconsHud
-- Renders active-boost pills in HUD_BoostIcons using the Boost1 template.
-- Shows an icon + "2x Cash"/"2x Wins"/"2x Streak"/"VIP" pill for each
-- gamepass the player owns. Listens to player attributes for live updates.
--
-- Also handles the purchase celebration banner (BoostActivated remote) and
-- the floating "x2!" reward popper (BoostAwarded remote).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BoostIconsHud = {}

-- Icon asset IDs (reused from IngameAds)
local ICON_CASH   = "rbxassetid://83945987909294"
local ICON_WINS   = "rbxassetid://106286618566178"
local ICON_STREAK = "rbxassetid://114192556144330"
local ICON_VIP    = "rbxassetid://128383063987894"

type BoostDef = {
	key: string,       -- attribute suffix
	attr: string,      -- full attribute name on Player
	label: string,
	icon: string,
	glow: Color3,
}

local BOOSTS: { BoostDef } = {
	{ key = "DOUBLE_CASH",   attr = "Boost_DoubleCash",   label = "2x",     icon = ICON_CASH,   glow = Color3.fromRGB(100, 255, 140) },
	{ key = "DOUBLE_WINS",   attr = "Boost_DoubleWins",   label = "2x",     icon = ICON_WINS,   glow = Color3.fromRGB(255, 215, 0) },
	{ key = "DOUBLE_STREAK", attr = "Boost_DoubleStreak", label = "2x",     icon = ICON_STREAK, glow = Color3.fromRGB(255, 120, 60) },
	{ key = "VIP",           attr = "Boost_VIP",          label = "VIP",    icon = ICON_VIP,    glow = Color3.fromRGB(255, 240, 120) },
}

local function findDescendantByName(root: Instance, name: string): Instance?
	for _, d in root:GetDescendants() do
		if d.Name == name then return d end
	end
	return nil
end

-- Build one clone of the Boost1 template wired for a specific boost.
-- Template is an ImageLabel (the icon itself) with a BoostLabel TextLabel child.
local function buildPill(template: GuiObject, parent: Instance, def: BoostDef): GuiObject
	local pill = template:Clone()
	pill.Name = "Boost_" .. def.key
	pill.Visible = false
	pill.Parent = parent

	-- Label
	local label = pill:FindFirstChild("BoostLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = def.label
	end

	-- Icon — Boost1 itself is an ImageLabel, so set .Image on the clone.
	if pill:IsA("ImageLabel") or pill:IsA("ImageButton") then
		(pill :: ImageLabel).Image = def.icon
	else
		for _, d in pill:GetDescendants() do
			if d:IsA("ImageLabel") then
				d.Image = def.icon
				break
			end
		end
	end

	-- No outlines — remove any UIStroke that came from the template.
	local existingStroke = pill:FindFirstChildOfClass("UIStroke")
	if existingStroke then
		existingStroke:Destroy()
	end

	return pill
end

-- Option 2: full-screen celebration banner on purchase.
local function showPurchaseBanner(playerGui: PlayerGui, def: BoostDef)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BoostBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.4)
	frame.Size = UDim2.fromScale(0.7, 0.2)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui

	-- Keep the banner proportional on tall/narrow phones: width-driven aspect
	-- ratio so the frame caps its height instead of stretching.
	local bannerAspect = Instance.new("UIAspectRatioConstraint")
	bannerAspect.AspectRatio = 4
	bannerAspect.AspectType = Enum.AspectType.ScaleWithParentSize
	bannerAspect.DominantAxis = Enum.DominantAxis.Width
	bannerAspect.Parent = frame

	-- Cap the max width on very wide screens so it doesn't dominate desktop.
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(800, 220)
	sizeCap.MinSize = Vector2.new(260, 70)
	sizeCap.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = def.glow
	stroke.Thickness = 4
	stroke.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = frame

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Size = UDim2.new(0, 0, 0.8, 0) -- width set by AspectRatioConstraint
	icon.Position = UDim2.fromScale(0.04, 0.5)
	icon.Image = def.icon
	icon.Parent = frame

	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.AspectType = Enum.AspectType.ScaleWithParentSize
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = icon

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0, 0.5)
	-- Icon is ~20% of banner width (height*0.8 with 4:1 aspect). Title fills the rest.
	title.Size = UDim2.fromScale(0.7, 0.7)
	title.Position = UDim2.fromScale(0.28, 0.5)
	title.Text = string.upper(def.label) .. " UNLOCKED!"
	title.TextColor3 = def.glow
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = title.Parent or frame
	title.Parent = frame

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 3
	titleStroke.Parent = title

	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.2, function()
		local fadeTween = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		fadeTween:Play()
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.5 }):Play()
		TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(icon, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		fadeTween.Completed:Connect(function()
			gui:Destroy()
		end)
	end)
end

-- Option 3: floating "+N x2!" popper near the relevant HUD element.
local function showRewardFloater(playerGui: PlayerGui, def: BoostDef, amount: number, multiplier: number?)
	-- Anchor near CashHud / WinsHud / StreakHud (all top-left). We don't try
	-- to locate exact HUDs — just spawn in the top-left area, stacking below.
	local gui = Instance.new("ScreenGui")
	gui.Name = "BoostFloater"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 500
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.new(0, 180, 0, 80)
	label.Size = UDim2.fromOffset(200, 50)
	label.BackgroundTransparency = 1
	local multText = if multiplier and multiplier ~= 2
		then (multiplier == math.floor(multiplier) and string.format("x%d", multiplier) or string.format("x%.1f", multiplier))
		else "x2"
	label.Text = string.format("+%d %s!", amount, multText)
	label.TextColor3 = def.glow
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = label

	local floatTween = TweenService:Create(
		label,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 180, 0, 20), TextTransparency = 1 }
	)
	floatTween:Play()
	TweenService:Create(stroke, TweenInfo.new(1.1), { Transparency = 1 }):Play()
	floatTween.Completed:Connect(function()
		gui:Destroy()
	end)
end

function BoostIconsHud.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	-- Find the HUD_BoostIcons frame + Boost1 template. The frame is cloned
	-- into PlayerGui from StarterGui, so poll briefly for it to show up.
	task.spawn(function()
		local boostFrame: Instance? = nil
		local deadline = os.clock() + 15
		while os.clock() < deadline do
			boostFrame = findDescendantByName(playerGui, "HUD_BoostIcons")
			if boostFrame and boostFrame:IsA("GuiObject") then break end
			boostFrame = nil
			task.wait(0.25)
		end
		if not boostFrame then
			warn("[BoostIconsHud] HUD_BoostIcons frame not found")
			return
		end

		local template = boostFrame:FindFirstChild("Boost1")
		if not template or not template:IsA("GuiObject") then
			warn("[BoostIconsHud] Boost1 template not found under HUD_BoostIcons")
			return
		end
		template.Visible = false

		local pills: { [string]: GuiObject } = {}
		for _, def in BOOSTS do
			pills[def.key] = buildPill(template :: GuiObject, boostFrame, def)
		end

		local function updateCashLabel()
			-- When both DOUBLE_CASH and VIP are owned, the cash pill shows the
			-- combined multiplier ("3x") instead of "2x".
			local pill = pills["DOUBLE_CASH"]
			if not pill then return end
			local label = pill:FindFirstChild("BoostLabel", true)
			if not (label and label:IsA("TextLabel")) then return end
			local hasVIP = localPlayer:GetAttribute("Boost_VIP") == true
			label.Text = if hasVIP then "3x" else "2x"
		end

		local function refreshFromAttributes()
			for _, def in BOOSTS do
				local owned = localPlayer:GetAttribute(def.attr) == true
				local pill = pills[def.key]
				if pill then
					pill.Visible = owned
				end
			end
			updateCashLabel()
		end

		-- Pop animation when a pill first becomes visible after purchase.
		local wasVisible: { [string]: boolean } = {}
		for _, def in BOOSTS do
			wasVisible[def.key] = false
		end

		local function syncWithPop()
			for _, def in BOOSTS do
				local owned = localPlayer:GetAttribute(def.attr) == true
				local pill = pills[def.key]
				if not pill then continue end
				if owned and not wasVisible[def.key] then
					pill.Visible = true
					local s = pill:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", pill)
					s.Scale = 0.2
					TweenService:Create(s, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				elseif not owned and wasVisible[def.key] then
					pill.Visible = false
				end
				wasVisible[def.key] = owned
			end
			updateCashLabel()
		end

		refreshFromAttributes()
		for _, def in BOOSTS do
			wasVisible[def.key] = pills[def.key].Visible
		end

		for _, def in BOOSTS do
			localPlayer:GetAttributeChangedSignal(def.attr):Connect(syncWithPop)
		end
	end)

	-- Banner + floater remote listeners.
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local defByKey: { [string]: BoostDef } = {}
		for _, d in BOOSTS do defByKey[d.key] = d end

		local activated = remotes:WaitForChild("BoostActivated", 10)
		if activated then
			(activated :: RemoteEvent).OnClientEvent:Connect(function(key)
				local def = defByKey[key]
				if def then showPurchaseBanner(playerGui, def) end
			end)
		end

		local awarded = remotes:WaitForChild("BoostAwarded", 10)
		if awarded then
			(awarded :: RemoteEvent).OnClientEvent:Connect(function(key, amount, multiplier)
				local def = defByKey[key]
				if def and typeof(amount) == "number" then
					showRewardFloater(playerGui, def, amount, if typeof(multiplier) == "number" then multiplier else nil)
				end
			end)
		end
	end)
end

return BoostIconsHud
