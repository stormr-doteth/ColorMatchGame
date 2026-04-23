-- RewardsUI
-- Wires the manually-designed Rewards panel: Daily, Playtime, Group, VIP tabs.
-- Uses the same bounce tween as the Shop panel for open/close.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local PromptPurchase = require(script.Parent:WaitForChild("ui"):WaitForChild("PromptPurchase"))
local ChairCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChairCatalog"))

local GROUP_ID = 626343155
local VIP_PASS_ID = 1796710377

-- Tweens matching Shop panel
local BOUNCE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BOUNCE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local TAB_FADE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local PLAYTIME_MILESTONES = {
	{ id = "5_min",  seconds = 300 },
	{ id = "10_min", seconds = 600 },
	{ id = "15_min", seconds = 900 },
	{ id = "20_min", seconds = 1200 },
	{ id = "30_min", seconds = 1800 },
	{ id = "45_min", seconds = 2700 },
	{ id = "60_min", seconds = 3600 },
}

local RewardsUI = {}

-- Ensure the entire visible area of a claim/reward container is tappable.
-- Studio-designed ClaimButtons can have a Size that only covers part of the
-- visible card, leaving mobile players with a tiny real hit region (same
-- "far-right corner only" symptom fixed in LuckyBlockShopUI). Adding a
-- transparent full-size TextButton on the container at high ZIndex gives us
-- a consistent hit region without altering the visual layout. Idempotent —
-- re-wiring the panel won't stack overlays.
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
	overlay.Selectable = true
	overlay.Parent = parentFrame
	return overlay
end

function RewardsUI.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then return end

	local rewardsFrame = screenGui:WaitForChild("Rewards", 10) :: Frame?
	if not rewardsFrame then
		warn("[RewardsUI] Rewards frame not found")
		return
	end

	-- Store original size for bounce tween
	rewardsFrame:SetAttribute("OrigSize", rewardsFrame.Size)
	rewardsFrame.Visible = false

	local header = rewardsFrame:FindFirstChild("Header")
	local body = rewardsFrame:FindFirstChild("Body")
	local buttonFrame = rewardsFrame:FindFirstChild("ButtonFrame")
	if not body or not buttonFrame then return end

	local rewardTypeLabel = body:FindFirstChild("RewardTypeLabel") :: TextLabel?
	local rewardTimerLabel = body:FindFirstChild("RewardTimerLabel") :: TextLabel?

	local dailyPanel = body:FindFirstChild("DailyRewards")
	local playtimePanel = body:FindFirstChild("PlaytimeRewards")
	local groupPanel = body:FindFirstChild("GroupRewards")
	local vipPanel = body:FindFirstChild("VIPRewards")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local isVisible = false
	local isAnimating = false

	---------------------------------------------------------------------------
	-- Helper: set claim button state
	---------------------------------------------------------------------------
	local function setButtonState(btn: TextButton, state: string, timerText: string?)
		local green = btn:FindFirstChild("greenGradient") :: UIGradient?
		local grey = btn:FindFirstChild("greyGradient") :: UIGradient?
		local label = btn:FindFirstChild("robuxLabel") :: TextLabel?

		if state == "claimable" then
			if green then green.Enabled = true end
			if grey then grey.Enabled = false end
			if label then label.Text = "CLAIM" end
			btn.AutoButtonColor = true
		elseif state == "claimed" then
			if green then green.Enabled = false end
			if grey then grey.Enabled = true end
			if label then label.Text = "Claimed!" end
			btn.AutoButtonColor = false
		elseif state == "not_ready" then
			if green then green.Enabled = false end
			if grey then grey.Enabled = true end
			if label then label.Text = timerText or "Not Ready" end
		elseif state == "join_group" then
			if green then green.Enabled = false end
			if grey then grey.Enabled = true end
			if label then label.Text = "Join Group" end
		elseif state == "get_vip" then
			if green then green.Enabled = true end
			if grey then grey.Enabled = false end
			if label then label.Text = "Get VIP" end
		end
	end

	---------------------------------------------------------------------------
	-- Tab switching with smooth fade
	---------------------------------------------------------------------------
	-- Forward declaration so showTab() can call it before its definition.
	local updatePlaytimeUI

	local currentTab = "daily"
	local allPanels = {
		daily = dailyPanel,
		playtime = playtimePanel,
		group = groupPanel,
		vip = vipPanel,
	}
	local TAB_NAMES = {
		daily = "Daily Rewards",
		playtime = "Playtime Rewards",
		group = "Group Rewards",
		vip = "VIP Rewards",
	}

	-- Tab button references for highlight state
	local tabButtons: { [string]: Frame } = {}
	local tabMap = {
		DailyRewards = "daily",
		PlaytimeRewards = "playtime",
		GroupRewards = "group",
		VipRewards = "vip",
	}

	-- Tint multiplies with the blueGradient: white = gradient as-authored,
	-- brighter on hover, darker when selected.
	local TINT_IDLE = Color3.fromRGB(200, 200, 200)
	local TINT_HOVER = Color3.fromRGB(255, 255, 255)
	local TINT_SELECTED = Color3.fromRGB(110, 110, 110)
	local TINT_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local hoveredTab: string? = nil

	local function paintTab(tab: string)
		local frame = tabButtons[tab]
		if not frame then return end
		local tint
		if currentTab == tab then
			tint = TINT_SELECTED
		elseif hoveredTab == tab then
			tint = TINT_HOVER
		else
			tint = TINT_IDLE
		end
		TweenService:Create(frame, TINT_TWEEN, { BackgroundColor3 = tint }):Play()
	end

	for _, child in buttonFrame:GetChildren() do
		if child:IsA("Frame") and tabMap[child.Name] then
			tabButtons[tabMap[child.Name]] = child
			child.BackgroundColor3 = TINT_IDLE
		end
	end

	local function showTab(tab: string)
		if currentTab == tab and allPanels[tab] and allPanels[tab].Visible then return end
		local prev = currentTab
		currentTab = tab

		-- Fade out all panels, fade in the target
		for key, panel in allPanels do
			if panel then
				panel.Visible = (key == tab)
			end
		end

		if rewardTypeLabel then
			rewardTypeLabel.Text = TAB_NAMES[tab] or ""
		end

		paintTab(prev)
		paintTab(tab)

		-- Update timer label for current tab
		if tab == "daily" then updateDailyTimerLabel() end
		if tab == "playtime" then updatePlaytimeUI() end
		if tab == "group" then updateGroupUI() end
		if tab == "vip" then updateVipUI() end
	end

	-- Wire tab buttons — connect both the TextButton and an overlay on the Frame
	for _, child in buttonFrame:GetChildren() do
		if child:IsA("Frame") and tabMap[child.Name] then
			local tab = tabMap[child.Name]
			local btn = child:FindFirstChild("ButtonLabel") :: TextButton?
			if btn then
				btn.Activated:Connect(function()
					showTab(tab)
				end)
			end
			-- Also add a transparent click overlay on the frame itself
			local overlay = Instance.new("TextButton")
			overlay.Name = "TabClickOverlay"
			overlay.Size = UDim2.fromScale(1, 1)
			overlay.BackgroundTransparency = 1
			overlay.Text = ""
			overlay.AutoButtonColor = false
			overlay.ZIndex = 10
			overlay.Parent = child
			overlay.Activated:Connect(function()
				showTab(tab)
			end)
			overlay.MouseEnter:Connect(function()
				hoveredTab = tab
				paintTab(tab)
			end)
			overlay.MouseLeave:Connect(function()
				if hoveredTab == tab then hoveredTab = nil end
				paintTab(tab)
			end)
		end
	end

	---------------------------------------------------------------------------
	-- Open / Close with bounce tween (matching Shop)
	---------------------------------------------------------------------------
	local function openRewards()
		if isAnimating or isVisible then return end
		UIManager.CloseOthers("Rewards")
		isAnimating = true

		rewardsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		local targetSize = rewardsFrame:GetAttribute("OrigSize") or rewardsFrame.Size
		rewardsFrame.Size = UDim2.new(
			targetSize.X.Scale * 0.7, targetSize.X.Offset * 0.7,
			targetSize.Y.Scale * 0.7, targetSize.Y.Offset * 0.7
		)
		rewardsFrame.Visible = true
		rewardsFrame.SelectionGroup = true
		TweenService:Create(rewardsFrame, BOUNCE_IN, { Size = targetSize }):Play()

		isVisible = true
		showTab("daily")
		task.delay(BOUNCE_IN.Time, function()
			isAnimating = false
			for _, d in rewardsFrame:GetDescendants() do
				if d:IsA("GuiButton") and d.Selectable and d.Visible and d.Active then
					GuiService.SelectedObject = d
					break
				end
			end
		end)
	end

	local function closeRewards()
		if isAnimating or not isVisible then return end
		isAnimating = true

		local targetSize = rewardsFrame:GetAttribute("OrigSize") or rewardsFrame.Size
		local shrunkSize = UDim2.new(
			targetSize.X.Scale * 0.7, targetSize.X.Offset * 0.7,
			targetSize.Y.Scale * 0.7, targetSize.Y.Offset * 0.7
		)
		local tween = TweenService:Create(rewardsFrame, BOUNCE_OUT, { Size = shrunkSize })
		tween:Play()
		tween.Completed:Connect(function()
			rewardsFrame.Visible = false
			rewardsFrame.Size = targetSize
			isVisible = false
			isAnimating = false
			local sel = GuiService.SelectedObject
			if sel and sel:IsDescendantOf(rewardsFrame) then
				GuiService.SelectedObject = nil
			end
		end)
	end

	UIManager.Register("Rewards", closeRewards, function()
		return isVisible
	end)

	-- Close button
	if header then
		local closeBtn = header:FindFirstChild("CloseButton") :: ImageButton?
		if closeBtn then
			closeBtn.Activated:Connect(closeRewards)
		end
	end

	-- Wire CosmeticsButton (now labeled "Rewards") in ShopButtons
	local cosmeticsPing: GuiObject? = nil
	local shopButtons = screenGui:FindFirstChild("ShopButtons")
	if shopButtons then
		local cosmeticsBtn = shopButtons:FindFirstChild("CosmeticsButton")
		if cosmeticsBtn then
			local btnImage = cosmeticsBtn:FindFirstChild("Button1Image") :: ImageButton?
			if btnImage then
				btnImage.Activated:Connect(function()
					if isVisible then
						closeRewards()
					else
						openRewards()
					end
				end)
			end
			local ping = cosmeticsBtn:FindFirstChild("NotificationPing", true) :: GuiObject?
			if ping then
				cosmeticsPing = ping
				ping.Visible = false
			end
		end
	end

	-- Tab pings on Daily/Playtime tab buttons (default hidden)
	local dailyPing: GuiObject? = nil
	local playtimePing: GuiObject? = nil
	if tabButtons.daily then
		local p = tabButtons.daily:FindFirstChild("NotificationPing", true) :: GuiObject?
		if p then dailyPing = p; p.Visible = false end
	end
	if tabButtons.playtime then
		local p = tabButtons.playtime:FindFirstChild("NotificationPing", true) :: GuiObject?
		if p then playtimePing = p; p.Visible = false end
	end

	-- Forward-declared; assigned later once claim state is known.
	local refreshPings

	---------------------------------------------------------------------------
	-- DAILY REWARDS
	---------------------------------------------------------------------------
	local dailyData = nil
	local dailyFrames: { Frame } = {}

	if dailyPanel then
		for _, child in dailyPanel:GetChildren() do
			if child:IsA("Frame") then
				table.insert(dailyFrames, child)
			end
		end
		table.sort(dailyFrames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
	end

	-- Forward-declared so showTab can call it
	function updateDailyTimerLabel()
		if not rewardTimerLabel or currentTab ~= "daily" then return end
		if dailyData and dailyData.canClaim then
			rewardTimerLabel.Text = "Reward ready to claim!"
		else
			rewardTimerLabel.Text = "Next ready in ~24h"
		end
	end

	local function updateDailyUI()
		if not dailyData then return end
		local currentStreak = dailyData.currentStreak or 0
		local canClaim = dailyData.canClaim or false

		-- A day is "claimed" if i <= currentStreak (within the active 7-day cycle).
		-- The next claimable day is currentStreak + 1 (if canClaim). This stays
		-- correct after local claim bumps (we increment currentStreak, not nextDay).
		local cycleStreak = currentStreak % #dailyFrames
		local pendingDay = cycleStreak + 1

		for i, frame in dailyFrames do
			local itemLabel = frame:FindFirstChild("ItemLabel") :: TextLabel?
			local claimBtn = frame:FindFirstChild("ClaimButton") :: TextButton?

			if itemLabel then
				itemLabel.Text = "Day " .. i
			end

			if claimBtn then
				if i <= cycleStreak then
					setButtonState(claimBtn, "claimed")
				elseif canClaim and i == pendingDay then
					setButtonState(claimBtn, "claimable")
				else
					setButtonState(claimBtn, "not_ready")
				end
			end
		end

		updateDailyTimerLabel()
	end

	for i, frame in dailyFrames do
		local claimBtn = frame:FindFirstChild("ClaimButton") :: TextButton?
		if claimBtn then
			local claim = function()
				if not dailyData or not dailyData.canClaim then return end
				local streak = dailyData.currentStreak or 0
				local pending = (streak % #dailyFrames) + 1
				if i ~= pending then return end
				remotes:WaitForChild("ClaimDailyReward"):FireServer()
				dailyData.canClaim = false
				dailyData.currentStreak = streak + 1
				updateDailyUI()
			end
			claimBtn.Activated:Connect(claim)
			addFullAreaOverlay(frame, "TapArea").Activated:Connect(claim)
		end
	end

	remotes:WaitForChild("DailyRewardData").OnClientEvent:Connect(function(data)
		dailyData = data
		updateDailyUI()
		if refreshPings then refreshPings() end
	end)

	---------------------------------------------------------------------------
	-- PLAYTIME REWARDS
	---------------------------------------------------------------------------
	local joinTime = os.clock()
	local playtimeClaimed: { [string]: boolean } = {}
	local playtimeFrames: { { frame: Frame, id: string, seconds: number } } = {}

	if playtimePanel then
		for _, milestone in PLAYTIME_MILESTONES do
			local frame = playtimePanel:FindFirstChild(milestone.id) :: Frame?
			if frame then
				table.insert(playtimeFrames, {
					frame = frame,
					id = milestone.id,
					seconds = milestone.seconds,
				})

			end
		end
	end

	local function formatTime(secs: number): string
		local m = math.floor(secs / 60)
		local s = math.floor(secs % 60)
		return string.format("%d:%02d", m, s)
	end

	updatePlaytimeUI = function()
		local elapsed = os.clock() - joinTime

		for _, entry in playtimeFrames do
			local claimBtn = entry.frame:FindFirstChild("ClaimButton") :: TextButton?
			if not claimBtn then continue end

			if playtimeClaimed[entry.id] then
				setButtonState(claimBtn, "claimed")
			elseif elapsed >= entry.seconds then
				setButtonState(claimBtn, "claimable")
			else
				local remaining = entry.seconds - elapsed
				setButtonState(claimBtn, "not_ready", formatTime(remaining))
			end
		end

		if rewardTimerLabel and currentTab == "playtime" then
			local nextMilestone = nil
			for _, entry in playtimeFrames do
				if not playtimeClaimed[entry.id] and elapsed < entry.seconds then
					nextMilestone = entry
					break
				end
			end
			if nextMilestone then
				local remaining = nextMilestone.seconds - elapsed
				rewardTimerLabel.Text = "Next reward in " .. formatTime(remaining)
			else
				local allClaimed = true
				for _, entry in playtimeFrames do
					if not playtimeClaimed[entry.id] then
						allClaimed = false
						break
					end
				end
				if allClaimed then
					rewardTimerLabel.Text = "All playtime rewards claimed!"
				else
					rewardTimerLabel.Text = "Reward ready to claim!"
				end
			end
		end
	end

	for _, entry in playtimeFrames do
		local claimBtn = entry.frame:FindFirstChild("ClaimButton") :: TextButton?
		if claimBtn then
			local claim = function()
				local elapsed = os.clock() - joinTime
				if elapsed >= entry.seconds and not playtimeClaimed[entry.id] then
					remotes:WaitForChild("ClaimPlaytimeReward"):FireServer(entry.id)
					playtimeClaimed[entry.id] = true
					updatePlaytimeUI()
				end
			end
			claimBtn.Activated:Connect(claim)
			addFullAreaOverlay(entry.frame, "TapArea").Activated:Connect(claim)
		end
	end

	-- Prime button states immediately so the panel doesn't flash default
	-- "claimable" when the player first opens it.
	updatePlaytimeUI()

	remotes:WaitForChild("PlaytimeRewardData").OnClientEvent:Connect(function(data)
		if data.claimed then
			for id, _ in data.claimed do
				playtimeClaimed[id] = true
			end
		end
		updatePlaytimeUI()
		if refreshPings then refreshPings() end
	end)

	---------------------------------------------------------------------------
	-- GROUP REWARDS
	---------------------------------------------------------------------------
	local groupClaimed = false

	function updateGroupUI()
		if not groupPanel then return end
		local claimBtn = groupPanel:FindFirstChild("ClaimButton") :: TextButton?
		if not claimBtn then return end

		if groupClaimed then
			setButtonState(claimBtn, "claimed")
		else
			local ok, inGroup = pcall(function()
				return localPlayer:IsInGroup(GROUP_ID)
			end)
			if ok and inGroup then
				setButtonState(claimBtn, "claimable")
			else
				setButtonState(claimBtn, "join_group")
			end
		end

		if rewardTimerLabel and currentTab == "group" then
			if groupClaimed then
				rewardTimerLabel.Text = "Group reward claimed!"
			else
				rewardTimerLabel.Text = "Join our group for free rewards!"
			end
		end
	end

	if groupPanel then
		local claimBtn = groupPanel:FindFirstChild("ClaimButton") :: TextButton?
		if claimBtn then
			local claim = function()
				if not groupClaimed then
					remotes:WaitForChild("ClaimGroupReward"):FireServer()
				end
			end
			claimBtn.Activated:Connect(claim)
			-- Child overlay: guarantees this button wins input even if another
			-- decorative sibling has a higher ZIndex with Active = true.
			addFullAreaOverlay(claimBtn, "TapArea").Activated:Connect(claim)
		end

		local grf = groupPanel:FindFirstChild("GroupRewardFrame")
		if grf then
			local items = grf:FindFirstChild("ClaimableItems")
			if items then
				local idx = 0
				for _, item in items:GetChildren() do
					if item:IsA("ImageButton") then
						idx += 1
						local nl = item:FindFirstChild("ItemNameLabel") :: TextLabel?
						if nl then
							if idx == 1 then nl.Text = "+$250"
							elseif idx == 2 then nl.Text = "+1 Block"
							elseif idx == 3 then nl.Text = "+2 Hints"
							end
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- VIP REWARDS
	---------------------------------------------------------------------------
	local vipClaimed = false

	function updateVipUI()
		if not vipPanel then return end
		local claimBtn = vipPanel:FindFirstChild("ClaimButton") :: TextButton?
		if not claimBtn then return end

		if vipClaimed then
			setButtonState(claimBtn, "claimed")
		else
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(localPlayer.UserId, VIP_PASS_ID)
			end)
			if ok and owns then
				setButtonState(claimBtn, "claimable")
			else
				setButtonState(claimBtn, "get_vip")
			end
		end

		if rewardTimerLabel and currentTab == "vip" then
			if vipClaimed then
				rewardTimerLabel.Text = "VIP reward claimed!"
			else
				rewardTimerLabel.Text = "VIP members get exclusive rewards!"
			end
		end
	end

	if vipPanel then
		local claimBtn = vipPanel:FindFirstChild("ClaimButton") :: TextButton?
		if claimBtn then
			local claim = function()
				if vipClaimed then return end
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(localPlayer.UserId, VIP_PASS_ID)
				end)
				if ok and owns then
					remotes:WaitForChild("ClaimVIPReward"):FireServer()
				else
					PromptPurchase.GamePass(localPlayer, VIP_PASS_ID)
				end
			end
			claimBtn.Activated:Connect(claim)
			addFullAreaOverlay(claimBtn, "TapArea").Activated:Connect(claim)
		end

		local grf = vipPanel:FindFirstChild("GroupRewardFrame")
		if grf then
			local items = grf:FindFirstChild("ClaimableItems")
			if items then
				local vipThroneItem = items:FindFirstChild("VIPThrone")
				if vipThroneItem then
					local itemImage = vipThroneItem:FindFirstChild("ItemImage") :: ImageLabel?
					local existingVp = vipThroneItem:FindFirstChild("ThroneViewport") :: ViewportFrame?
					if itemImage and not existingVp then
						local templates = ReplicatedStorage:WaitForChild("ChairTemplates", 10)
						local throneModel = templates and templates:FindFirstChild("VipThrone")
						if throneModel then
							if itemImage:IsA("ImageLabel") or itemImage:IsA("ImageButton") then
								itemImage.Image = ""
							end

							local viewport = Instance.new("ViewportFrame")
							viewport.Name = "ThroneViewport"
							viewport.BackgroundTransparency = 1
							viewport.Size = UDim2.fromScale(1, 1)
							viewport.AnchorPoint = Vector2.new(0.5, 0.5)
							viewport.Position = UDim2.fromScale(0.5, 0.5)
							viewport.ZIndex = (itemImage :: GuiObject).ZIndex + 1
							viewport.Parent = itemImage

							local clone = throneModel:Clone()
							clone.Parent = viewport
							local boxCFrame, boxSize = clone:GetBoundingBox()
							clone:PivotTo(CFrame.new(-boxCFrame.Position))
							local entry = ChairCatalog.Get("vip_throne")
							local flip = if entry and entry.viewportFlip ~= nil then entry.viewportFlip else (entry and entry.flipSeat)
							if flip then
								clone:PivotTo(CFrame.Angles(0, math.pi, 0) * clone:GetPivot())
							end

							local maxExtent = math.max(boxSize.X, boxSize.Y, boxSize.Z)
							local dist = maxExtent * 1.4 + 0.5
							local camera = Instance.new("Camera")
							camera.CFrame = CFrame.lookAt(
								Vector3.new(dist, dist * 0.6, dist),
								Vector3.new(0, 0, 0)
							)
							camera.FieldOfView = 45
							camera.Parent = viewport
							viewport.CurrentCamera = camera
							viewport.LightDirection = Vector3.new(-1, -1, -1)
							viewport.Ambient = Color3.fromRGB(180, 180, 180)
							viewport.LightColor = Color3.fromRGB(255, 255, 255)
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- Sync claimed states from profile data
	---------------------------------------------------------------------------
	remotes:WaitForChild("PlayerDataUpdate").OnClientEvent:Connect(function(data)
		if not data then return end
		if data.GroupRewardClaimed then groupClaimed = true end
		if data.VIPRewardClaimed then vipClaimed = true end
		if currentTab == "group" then updateGroupUI() end
		if currentTab == "vip" then updateVipUI() end
	end)

	---------------------------------------------------------------------------
	-- Notification ping visibility (any tab with claimable rewards)
	---------------------------------------------------------------------------
	refreshPings = function()
		local dailyReady = dailyData and dailyData.canClaim == true or false

		local playtimeReady = false
		local elapsed = os.clock() - joinTime
		for _, entry in playtimeFrames do
			if not playtimeClaimed[entry.id] and elapsed >= entry.seconds then
				playtimeReady = true
				break
			end
		end

		-- Group/VIP claim-readiness is best-effort: only surface the ping when
		-- we already know the player qualifies (updateGroupUI/updateVipUI have
		-- run at least once).
		local groupReady = (not groupClaimed) and (function()
			local ok, inGroup = pcall(function() return localPlayer:IsInGroup(GROUP_ID) end)
			return ok and inGroup
		end)()
		local vipReady = false -- VIP async check is throttled; leave for future

		if dailyPing then dailyPing.Visible = dailyReady end
		if playtimePing then playtimePing.Visible = playtimeReady end
		if cosmeticsPing then
			cosmeticsPing.Visible = dailyReady or playtimeReady or groupReady or vipReady
		end
	end

	---------------------------------------------------------------------------
	-- Playtime timer loop (updates every second when panel is visible)
	---------------------------------------------------------------------------
	task.spawn(function()
		while true do
			if isVisible and currentTab == "playtime" then
				updatePlaytimeUI()
			end
			refreshPings()
			task.wait(1)
		end
	end)

	-- Initial setup
	showTab("daily")

	task.spawn(function()
		task.wait(2)
		updateGroupUI()
		updateVipUI()
	end)

	---------------------------------------------------------------------------
	-- Server-driven zone open/close. Server ZoneTrigger fires these remotes
	-- when the player's HRP enters/exits the TreasureRing. Moving zone
	-- detection to the server avoids StreamingEnabled replication gaps that
	-- previously broke walk-up detection on live servers.
	---------------------------------------------------------------------------
	local openRewardsRemote = remotes:WaitForChild("OpenRewards", 5)
	if openRewardsRemote then
		(openRewardsRemote :: RemoteEvent).OnClientEvent:Connect(function()
			openRewards()
			showTab("group")
		end)
	end
	local closeRewardsRemote = remotes:WaitForChild("CloseRewards", 5)
	if closeRewardsRemote then
		(closeRewardsRemote :: RemoteEvent).OnClientEvent:Connect(closeRewards)
	end
end

return RewardsUI
