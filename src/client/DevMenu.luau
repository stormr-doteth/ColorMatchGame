-- DevMenu
-- A floating panel visible only to the place's creator (or any player in
-- Studio). Lists every entry in LuckyBlockCatalog with a "Give" button that
-- pings DevGrantLuckyBlock on the server. The server re-verifies authorization
-- before granting, so exposing this client-side is safe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))

local DevMenu = {}

local localPlayer = Players.LocalPlayer
local started = false

-- Extra UserIds that should see the dev menu in production (e.g. group-owned
-- games, or trusted collaborators). Keep this list short.
local DEV_USER_IDS: { [number]: boolean } = {
	-- [123456789] = true,
}

local GroupService = game:GetService("GroupService")

local cachedGroupOwnerCheck: boolean? = nil
local function isGroupOwner(): boolean
	if cachedGroupOwnerCheck ~= nil then return cachedGroupOwnerCheck end
	if game.CreatorType ~= Enum.CreatorType.Group then
		cachedGroupOwnerCheck = false
		return false
	end
	local ok, info = pcall(function()
		return GroupService:GetGroupInfoAsync(game.CreatorId)
	end)
	if ok and info and info.Owner and info.Owner.Id == localPlayer.UserId then
		cachedGroupOwnerCheck = true
		return true
	end
	cachedGroupOwnerCheck = false
	return false
end

local function isAuthorized(): boolean
	if RunService:IsStudio() then return true end
	if DEV_USER_IDS[localPlayer.UserId] then return true end
	if game.CreatorType == Enum.CreatorType.User and localPlayer.UserId == game.CreatorId then
		return true
	end
	if isGroupOwner() then return true end
	return false
end

local function buildUi(grantRemote: RemoteEvent)
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 500
	gui.Parent = playerGui

	local toggle = Instance.new("TextButton")
	toggle.AnchorPoint = Vector2.new(0, 0)
	toggle.Position = UDim2.new(1, -48, 0, 200)
	toggle.Size = UDim2.fromOffset(36, 36)
	toggle.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	toggle.BorderSizePixel = 0
	toggle.Text = "D"
	toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggle.Font = Enum.Font.FredokaOne
	toggle.TextSize = 22
	toggle.Active = true
	toggle.Parent = gui
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = toggle

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.new(1, -252, 0, 244)
	panel.Size = UDim2.fromOffset(240, 380)
	panel.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Thickness = 1; ps.Color = Color3.fromRGB(200, 60, 60); ps.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 28)
	title.Position = UDim2.fromOffset(8, 8)
	title.BackgroundTransparency = 1
	title.Text = "DEV · Give Lucky Block"
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.AnchorPoint = Vector2.new(0, 0)
	scroll.Position = UDim2.fromOffset(8, 40)
	scroll.Size = UDim2.new(1, -16, 1, -48)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll

	-- Force the LuckyBlockHotbar into mobile layout regardless of viewport,
	-- because Studio's device emulator viewport detection is unreliable.
	-- Toggling rebuilds the hotbar in place via LuckyBlockHotbar.Restart().
	local LuckyBlockHotbar = require(script.Parent:WaitForChild("LuckyBlockHotbar"))
	local forceMobileRow = Instance.new("TextButton")
	forceMobileRow.Size = UDim2.new(1, -4, 0, 34)
	forceMobileRow.BackgroundColor3 = Color3.fromRGB(80, 60, 40)
	forceMobileRow.BorderSizePixel = 0
	forceMobileRow.AutoButtonColor = true
	forceMobileRow.TextColor3 = Color3.fromRGB(230, 230, 230)
	forceMobileRow.Font = Enum.Font.FredokaOne
	forceMobileRow.TextSize = 14
	forceMobileRow.LayoutOrder = -3
	forceMobileRow.Parent = scroll
	local fmCorner = Instance.new("UICorner"); fmCorner.CornerRadius = UDim.new(0, 6); fmCorner.Parent = forceMobileRow
	local function refreshForceMobileLabel()
		local on = playerGui:GetAttribute("DevForceMobile") == true
		forceMobileRow.Text = `Force Mobile Hotbar: {if on then "ON" else "OFF"}`
	end
	refreshForceMobileLabel()
	forceMobileRow.Activated:Connect(function()
		local on = playerGui:GetAttribute("DevForceMobile") == true
		playerGui:SetAttribute("DevForceMobile", not on)
		refreshForceMobileLabel()
		LuckyBlockHotbar.Restart()
	end)

	-- Reset the server's GroupRewardClaimed flag so the dev can re-test the
	-- claim flow from scratch (server otherwise silently rejects).
	local resetGroupRow = Instance.new("TextButton")
	resetGroupRow.Size = UDim2.new(1, -4, 0, 34)
	resetGroupRow.BackgroundColor3 = Color3.fromRGB(40, 80, 60)
	resetGroupRow.BorderSizePixel = 0
	resetGroupRow.AutoButtonColor = true
	resetGroupRow.Text = "Reset Group Claim"
	resetGroupRow.TextColor3 = Color3.fromRGB(230, 230, 230)
	resetGroupRow.Font = Enum.Font.FredokaOne
	resetGroupRow.TextSize = 14
	resetGroupRow.LayoutOrder = -2
	resetGroupRow.Parent = scroll
	local rgCorner = Instance.new("UICorner"); rgCorner.CornerRadius = UDim.new(0, 6); rgCorner.Parent = resetGroupRow
	local resetGroupRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DevResetGroupClaim") :: RemoteEvent?
	resetGroupRow.Activated:Connect(function()
		if resetGroupRemote then
			resetGroupRemote:FireServer()
		end
	end)

	-- Toggle: pretend the player is NOT in the group, so the GroupRewardPrompt
	-- claim button takes the "Join Group" path and PromptJoinAsync fires.
	-- Useful when testing in Studio while already a member of the real group.
	local notInGroupRow = Instance.new("TextButton")
	notInGroupRow.Size = UDim2.new(1, -4, 0, 34)
	notInGroupRow.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
	notInGroupRow.BorderSizePixel = 0
	notInGroupRow.AutoButtonColor = true
	notInGroupRow.TextColor3 = Color3.fromRGB(230, 230, 230)
	notInGroupRow.Font = Enum.Font.FredokaOne
	notInGroupRow.TextSize = 14
	notInGroupRow.LayoutOrder = -1
	notInGroupRow.Parent = scroll
	local nigCorner = Instance.new("UICorner"); nigCorner.CornerRadius = UDim.new(0, 6); nigCorner.Parent = notInGroupRow
	local function refreshNotInGroupLabel()
		local on = playerGui:GetAttribute("DevForceNotInGroup") == true
		notInGroupRow.Text = `Force "Not In Group": {if on then "ON" else "OFF"}`
	end
	refreshNotInGroupLabel()
	notInGroupRow.Activated:Connect(function()
		local on = playerGui:GetAttribute("DevForceNotInGroup") == true
		playerGui:SetAttribute("DevForceNotInGroup", not on)
		refreshNotInGroupLabel()
	end)

	for i, entry in LuckyBlockCatalog.GetAll() do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -4, 0, 34)
		row.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
		row.BorderSizePixel = 0
		row.AutoButtonColor = true
		row.Text = `Give  {entry.displayName}`
		row.TextColor3 = Color3.fromRGB(230, 230, 230)
		row.Font = Enum.Font.FredokaOne
		row.TextSize = 14
		row.LayoutOrder = i
		row.Parent = scroll
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row
		row.Activated:Connect(function()
			grantRemote:FireServer(entry.id)
		end)
	end

	-- Drag the toggle button around; the panel follows it so they stay a pair.
	-- We track drag start vs. end to distinguish taps (toggle panel) from drags
	-- (just reposition). A 4px threshold avoids treating tiny finger wobbles as
	-- drags on touchscreens.
	local dragging = false
	local dragMoved = false
	local dragStart: Vector2? = nil
	local startPos: UDim2? = nil
	local panelOffset: Vector2? = nil

	toggle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragMoved = false
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			startPos = toggle.Position
			panelOffset = Vector2.new(
				panel.AbsolutePosition.X - toggle.AbsolutePosition.X,
				panel.AbsolutePosition.Y - toggle.AbsolutePosition.Y
			)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local start = dragStart :: Vector2
		local sp = startPos :: UDim2
		local delta = Vector2.new(input.Position.X, input.Position.Y) - start
		if not dragMoved and delta.Magnitude > 4 then
			dragMoved = true
		end
		if dragMoved then
			toggle.Position = UDim2.new(
				sp.X.Scale, sp.X.Offset + delta.X,
				sp.Y.Scale, sp.Y.Offset + delta.Y
			)
			local po = panelOffset :: Vector2
			panel.Position = UDim2.new(
				sp.X.Scale, sp.X.Offset + delta.X + po.X,
				sp.Y.Scale, sp.Y.Offset + delta.Y + po.Y
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = false
		if not dragMoved then
			panel.Visible = not panel.Visible
		end
	end)

	-- F8 as a quick keyboard toggle on desktop.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.F8 then
			panel.Visible = not panel.Visible
		end
	end)
end

function DevMenu.Start()
	if started then return end
	started = true
	if not isAuthorized() then return end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local grantRemote = remotes:WaitForChild("DevGrantLuckyBlock", 10) :: RemoteEvent
	if not grantRemote then return end
	buildUi(grantRemote)
end

return DevMenu
