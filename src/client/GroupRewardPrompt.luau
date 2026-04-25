-- GroupRewardPrompt
-- Top-area "GiftBox" call-to-action that opens a standalone GroupReward popup,
-- routed through the same ClaimGroupReward remote as the Rewards panel so
-- claims sync automatically (PlayerDataUpdate updates both UIs).
--
-- Visibility rules:
--   * GiftBox shows when the player has not yet claimed the group reward AND
--     has not dismissed the prompt this session by clicking it.
--   * Clicking the GiftBox opens GroupReward and dismisses the GiftBox for
--     the rest of the session — successful claim or not.
--   * Once GroupRewardClaimed is true (server-confirmed), the GiftBox stays
--     hidden permanently for that profile.
--
-- Reward parity with Rewards panel → Group tab: $250 cash, 1 uncommon block,
-- 2 hints. The server's ClaimGroupReward handler is the single source of
-- truth for what is granted; this UI just labels the items.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GroupService = game:GetService("GroupService")

local GROUP_ID = 626343155

local BOUNCE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BOUNCE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local GroupRewardPrompt = {}

local function setButtonState(btn: TextButton, state: string)
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
	elseif state == "join_group" then
		if green then green.Enabled = false end
		if grey then grey.Enabled = true end
		if label then label.Text = "Join Group" end
		btn.AutoButtonColor = true
	end
end

-- Mirror RewardsUI's overlay trick so the entire claim card is tappable on
-- mobile, not just the Studio-authored sub-region of the button.
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

function GroupRewardPrompt.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then return end

	local topAreaAds = screenGui:WaitForChild("TopAreaAds", 10) :: GuiObject?
	local giftBox = topAreaAds and topAreaAds:WaitForChild("GiftBox", 10) :: GuiObject?
	local rewardFrame = screenGui:WaitForChild("GroupReward", 10) :: Frame?

	if not giftBox or not rewardFrame then
		warn("[GroupRewardPrompt] Missing TopAreaAds.GiftBox or GroupReward frame")
		return
	end

	-- Initial state
	rewardFrame:SetAttribute("OrigSize", rewardFrame.Size)
	rewardFrame.Visible = false
	rewardFrame.AnchorPoint = Vector2.new(0.5, 0.5)

	local groupClaimed = false
	local dismissedThisSession = false
	local isOpen = false
	local isAnimating = false

	-- Dev override: force the GiftBox to appear for testing even after the
	-- player has claimed. Scoped to specific UserIds so it's safe in prod.
	local DEV_FORCE_GIFTBOX_USERS: { [number]: boolean } = {
		[3401001] = true,
	}
	local devForceGiftBox = DEV_FORCE_GIFTBOX_USERS[localPlayer.UserId] == true

	local function syncGiftBoxVisibility()
		if devForceGiftBox then
			giftBox.Visible = not dismissedThisSession
			return
		end
		giftBox.Visible = (not groupClaimed) and (not dismissedThisSession)
	end

	-- "Try claiming without meeting requirements" hint, hidden by default.
	local claimFailedLabel = rewardFrame:FindFirstChild("ClaimFailed", true) :: GuiObject?
	if claimFailedLabel then
		claimFailedLabel.Visible = false
	end

	local failedHideToken = 0
	local function flashClaimFailed()
		if not claimFailedLabel then return end
		claimFailedLabel.Visible = true
		failedHideToken += 1
		local myToken = failedHideToken
		task.delay(2.5, function()
			if myToken == failedHideToken and claimFailedLabel then
				claimFailedLabel.Visible = false
			end
		end)
	end

	-- Apply known state to the popup's claim button
	local claimBtn = rewardFrame:FindFirstChild("ClaimButton", true) :: TextButton?
	local function refreshClaimButton()
		if not claimBtn then return end
		if groupClaimed and not devForceGiftBox then
			setButtonState(claimBtn, "claimed")
		else
			local ok, inGroup = pcall(function()
				if playerGui:GetAttribute("DevForceNotInGroup") then
					return false
				end
				return localPlayer:IsInGroup(GROUP_ID)
			end)
			if ok and inGroup then
				setButtonState(claimBtn, "claimable")
			else
				setButtonState(claimBtn, "join_group")
			end
		end
	end

	---------------------------------------------------------------------------
	-- Open / close popup
	---------------------------------------------------------------------------
	local function openPopup()
		if isAnimating or isOpen then return end
		isAnimating = true

		local target = rewardFrame:GetAttribute("OrigSize") or rewardFrame.Size
		rewardFrame.Size = UDim2.new(
			target.X.Scale * 0.7, target.X.Offset * 0.7,
			target.Y.Scale * 0.7, target.Y.Offset * 0.7
		)
		rewardFrame.Visible = true
		isOpen = true
		refreshClaimButton()
		TweenService:Create(rewardFrame, BOUNCE_IN, { Size = target }):Play()
		task.delay(BOUNCE_IN.Time, function()
			isAnimating = false
		end)
	end

	local function closePopup()
		if isAnimating or not isOpen then return end
		isAnimating = true
		local target = rewardFrame:GetAttribute("OrigSize") or rewardFrame.Size
		local shrunk = UDim2.new(
			target.X.Scale * 0.7, target.X.Offset * 0.7,
			target.Y.Scale * 0.7, target.Y.Offset * 0.7
		)
		local tween = TweenService:Create(rewardFrame, BOUNCE_OUT, { Size = shrunk })
		tween:Play()
		tween.Completed:Connect(function()
			rewardFrame.Visible = false
			rewardFrame.Size = target
			isOpen = false
			isAnimating = false
		end)
	end

	---------------------------------------------------------------------------
	-- GiftBox click → dismiss + open popup
	---------------------------------------------------------------------------
	local function dismissAndOpen()
		dismissedThisSession = true
		syncGiftBoxVisibility()
		openPopup()
	end

	if giftBox:IsA("GuiButton") then
		giftBox.Activated:Connect(dismissAndOpen)
	else
		addFullAreaOverlay(giftBox, "GiftBoxClickArea").Activated:Connect(dismissAndOpen)
	end

	---------------------------------------------------------------------------
	-- Popup close button (optional)
	---------------------------------------------------------------------------
	local closeBtn = rewardFrame:FindFirstChild("CloseButton", true) :: GuiButton?
	if closeBtn then
		closeBtn.Activated:Connect(closePopup)
	end

	---------------------------------------------------------------------------
	-- Claim button → reuse the same ClaimGroupReward remote as the Rewards
	-- panel so server-side grant + persistence runs once and PlayerDataUpdate
	-- syncs both UIs.
	---------------------------------------------------------------------------
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local claimRemote = remotes:WaitForChild("ClaimGroupReward") :: RemoteEvent

	-- Dedicated "Join Group" button (separate from ClaimButton). Always
	-- fires PromptJoinAsync; harmless if the player is already a member.
	local joinBtn = rewardFrame:FindFirstChild("JoinGroupButton", true) :: GuiButton?
	if joinBtn then
		local promptJoin = function()
			pcall(function()
				GroupService:PromptJoinAsync(GROUP_ID)
			end)
		end
		if joinBtn:IsA("GuiButton") then
			joinBtn.Activated:Connect(promptJoin)
		end
		addFullAreaOverlay(joinBtn, "TapArea").Activated:Connect(promptJoin)
	end

	if claimBtn then
		local claim = function()
			if groupClaimed and not devForceGiftBox then return end
			local ok, inGroup = pcall(function()
				if playerGui:GetAttribute("DevForceNotInGroup") then
					return false
				end
				return localPlayer:IsInGroup(GROUP_ID)
			end)
			if ok and inGroup then
				claimRemote:FireServer()
			else
				-- Native in-game group join prompt. Cheaper than sending
				-- players to the website and the click is a single tap.
				pcall(function()
					GroupService:PromptJoinAsync(GROUP_ID)
				end)
				flashClaimFailed()
			end
			-- Refresh in case the player joined the group and re-clicked,
			-- transitioning the button from "Join Group" → "CLAIM".
			refreshClaimButton()
		end
		claimBtn.Activated:Connect(claim)
		addFullAreaOverlay(claimBtn, "TapArea").Activated:Connect(claim)
	end

	---------------------------------------------------------------------------
	-- Sync claimed state from profile. PlayerDataUpdate is the same event
	-- RewardsUI listens to, so claims from either UI propagate to both.
	---------------------------------------------------------------------------
	local dataUpdate = remotes:WaitForChild("PlayerDataUpdate") :: RemoteEvent
	dataUpdate.OnClientEvent:Connect(function(data)
		if not data then return end
		if data.GroupRewardClaimed == true and not groupClaimed then
			groupClaimed = true
			syncGiftBoxVisibility()
			refreshClaimButton()
			-- Auto-close the popup so the player gets a clean confirmation
			-- moment via the cash/inventory HUDs updating, instead of staring
			-- at a "Claimed!" button.
			if isOpen then
				task.delay(0.5, function()
					closePopup()
				end)
			end
		elseif data.GroupRewardClaimed == false and groupClaimed then
			-- Track downward transitions too, so the dev "Reset Group Claim"
			-- flow re-arms the upward edge and the auto-close fires again
			-- on the next real claim.
			groupClaimed = false
			syncGiftBoxVisibility()
			refreshClaimButton()
		end
	end)

	-- Initial paint
	syncGiftBoxVisibility()
	refreshClaimButton()
end

return GroupRewardPrompt
