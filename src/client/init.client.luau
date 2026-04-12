local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)

local TopBar = require(script:WaitForChild("TopBar"))
local CashHud = require(script:WaitForChild("CashHud"))
local WinsHud = require(script:WaitForChild("WinsHud"))
local StreakHud = require(script:WaitForChild("StreakHud"))
local InventoryHud = require(script:WaitForChild("InventoryHud"))
local NotificationHud = require(script:WaitForChild("NotificationHud"))
local App = require(script:WaitForChild("ui"):WaitForChild("App"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

TopBar.Start()
CashHud.Start()
WinsHud.Start()
StreakHud.Start()
InventoryHud.Start()
NotificationHud.Start()

-- Listen for server-sent notifications (e.g. purchase confirmations).
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local notifyRemote = remotes:WaitForChild("ShowNotification", 5)
if notifyRemote then
	(notifyRemote :: RemoteEvent).OnClientEvent:Connect(function(message)
		if typeof(message) == "string" then
			NotificationHud.Show(message)
		end
	end)
end

-- Test window toggled by the settings icon
local testGui = Instance.new("ScreenGui")
testGui.Name = "TestWindow"
testGui.ResetOnSpawn = false
testGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(220, 120)
frame.Position = UDim2.new(0.5, -110, 0.5, -60)
frame.AnchorPoint = Vector2.new(0, 0)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = testGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = "hi"
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextSize = 32
label.Font = Enum.Font.GothamBold
label.Parent = frame

local settingsIcon = TopBar.CreateSettingsIcon()
settingsIcon:bindToggleItem(frame)

local inviteIcon = TopBar.CreateInviteFriendsIcon()
inviteIcon:oneClick()
inviteIcon.selected:Connect(function()
	SocialService:PromptGameInvite(localPlayer)
end)

local reactGui = Instance.new("ScreenGui")
reactGui.Name = "ReactApp"
reactGui.ResetOnSpawn = false
reactGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
reactGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
reactGui.Parent = playerGui

local root = ReactRoblox.createRoot(reactGui)
root:render(React.createElement(App))

script.Destroying:Connect(function()
	root:unmount()
end)