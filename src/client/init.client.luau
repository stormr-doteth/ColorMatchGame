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
local HintShop = require(script:WaitForChild("HintShop"))
local LuckyBlockClient = require(script:WaitForChild("LuckyBlockClient"))
local LuckyBlockGifting = require(script:WaitForChild("LuckyBlockGifting"))
local LuckyBlockShopUI = require(script:WaitForChild("LuckyBlockShopUI"))
local GamepassSpamRotator = require(script:WaitForChild("GamepassSpamRotator"))
local RewardsUI = require(script:WaitForChild("RewardsUI"))
local SettingsHud = require(script:WaitForChild("SettingsHud"))
local VipChatTag = require(script:WaitForChild("VipChatTag"))
local TablePromptSuppressor = require(script:WaitForChild("TablePromptSuppressor"))
local BoostIconsHud = require(script:WaitForChild("BoostIconsHud"))
local WinsLeaderboardUI = require(script:WaitForChild("WinsLeaderboardUI"))
local MatchPaperHider = require(script:WaitForChild("MatchPaperHider"))
local FeedbackHud = require(script:WaitForChild("FeedbackHud"))
local ShopButtonsHider = require(script:WaitForChild("ShopButtonsHider"))
local MatchBlur = require(script:WaitForChild("MatchBlur"))
local SoundManager = require(script:WaitForChild("SoundManager"))
local DevMenu = require(script:WaitForChild("DevMenu"))
local LuckyBlockHotbar = require(script:WaitForChild("LuckyBlockHotbar"))
local UIEffects = require(script:WaitForChild("UIEffects"))
local App = require(script:WaitForChild("ui"):WaitForChild("App"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Force landscape on mobile. The server also sets this, but server-side
-- PlayerGui.ScreenOrientation occasionally doesn't replicate to the client on
-- first join (race with the PlayerGui being created), so we re-assert here
-- and again whenever it gets reset.
local function forceLandscape()
	pcall(function()
		playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	end)
end
forceLandscape()
playerGui:GetPropertyChangedSignal("ScreenOrientation"):Connect(function()
	if playerGui.ScreenOrientation ~= Enum.ScreenOrientation.LandscapeSensor then
		forceLandscape()
	end
end)

-- Disable Roblox's built-in reset-character button. Roblox requires this to
-- be re-asserted on CharacterAdded because the engine re-enables it on each
-- respawn. Wrapped in pcall + retry loop because SetCore errors if the
-- CoreGui isn't ready yet on join.
local StarterGui = game:GetService("StarterGui")
local function disableResetButton()
	local ok = false
	for _ = 1, 10 do
		ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then break end
		task.wait(0.25)
	end
end
task.spawn(disableResetButton)
localPlayer.CharacterAdded:Connect(disableResetButton)

require(script:WaitForChild("UIManager")).BindControllerClose()
TopBar.Start()
CashHud.Start()
WinsHud.Start()
StreakHud.Start()
InventoryHud.Start()
NotificationHud.Start()
HintShop.Start()
LuckyBlockClient.Start()
LuckyBlockGifting.Start()
LuckyBlockShopUI.Start()
GamepassSpamRotator.Start()
RewardsUI.Start()
SettingsHud.Start()
VipChatTag.Start()
TablePromptSuppressor.Start()
BoostIconsHud.Start()
WinsLeaderboardUI.Start()
MatchPaperHider.Start()
ShopButtonsHider.Start()
MatchBlur.Start()
SoundManager.Start()
FeedbackHud.Start()
DevMenu.Start()
LuckyBlockHotbar.Start()

-- Wire hover/press feedback onto the left-column shop buttons once they're
-- reparented to NoInsetGui. Done in a task so we don't race the reparent below.
task.spawn(function()
	local sbRoot = playerGui:WaitForChild("NoInsetGui", 15)
	if not sbRoot then return end
	local shopButtons = sbRoot:WaitForChild("ShopButtons", 15)
	if not shopButtons then return end
	for _, child in shopButtons:GetDescendants() do
		if child:IsA("GuiButton") then
			UIEffects.BindButton(child)
		end
	end
	shopButtons.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then UIEffects.BindButton(d) end
	end)
end)

-- Reparent frames that should render behind/over the topbar (mobile fix).
-- The shared "ScreenGui" respects the topbar inset, which pushes these frames
-- down on mobile. Move them into a ScreenGui with IgnoreGuiInset = true.
task.spawn(function()
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then return end

	local noInset = Instance.new("ScreenGui")
	noInset.Name = "NoInsetGui"
	noInset.ResetOnSpawn = false
	noInset.IgnoreGuiInset = true
	noInset.ZIndexBehavior = screenGui.ZIndexBehavior
	noInset.DisplayOrder = screenGui.DisplayOrder
	noInset.Parent = playerGui

	for _, name in { "ShopButtons", "IngameAds", "GamepassSpam", "Shop", "CosmeticsShop", "Inventory", "Rewards" } do
		local frame = screenGui:WaitForChild(name, 10)
		if frame then
			frame.Parent = noInset
		end
	end
end)

-- Wire generic hover/press feedback on every GuiButton inside the main
-- lobby ScreenGuis. Runs after modules have built their UIs.
task.delay(2, function()
	local function wireAll(root: Instance)
		for _, d in root:GetDescendants() do
			if d:IsA("GuiButton") then
				UIEffects.BindButton(d)
			end
		end
		root.DescendantAdded:Connect(function(d)
			if d:IsA("GuiButton") then UIEffects.BindButton(d) end
		end)
	end
	local screenGui = playerGui:FindFirstChild("ScreenGui")
	if screenGui then wireAll(screenGui) end
	local noInset = playerGui:FindFirstChild("NoInsetGui")
	if noInset then wireAll(noInset) end
end)

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

local inviteIcon = TopBar.CreateInviteFriendsIcon()
inviteIcon:oneClick()
inviteIcon.selected:Connect(function()
	SocialService:PromptGameInvite(localPlayer)
end)

local feedbackIcon = TopBar.CreateFeedbackIcon()
feedbackIcon:oneClick()
feedbackIcon.selected:Connect(function()
	FeedbackHud.Toggle()
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