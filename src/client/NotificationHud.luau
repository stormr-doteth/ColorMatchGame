-- NotificationHud
-- A lightweight toast-style notification feed near the top of the screen.
-- Supports up to 3 visible notifications at once. The most recent is always
-- at the top; when a new one arrives, existing toasts slide down; the oldest
-- fades out and is destroyed.
--
-- Usage (from any client module):
--   local NotificationHud = require(script.Parent.NotificationHud)
--   NotificationHud.Show("You purchased the Red Chair!")

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local NotificationHud = {}

local MAX_VISIBLE = 3
local DISPLAY_DURATION = 3 -- seconds before auto-dismiss
local TWEEN_IN_TIME = 0.35
local TWEEN_OUT_TIME = 0.3
local TWEEN_SLIDE_TIME = 0.25
local TOAST_HEIGHT = 52
local TOAST_GAP = 8
local TOP_OFFSET = 16 -- px from top of safe area (IgnoreGuiInset = false)
local TOAST_MAX_WIDTH = 500 -- px cap on desktop so toasts don't stretch too wide

local feed: { any } = {} -- ordered newest-first
local feedContainer: Frame? = nil

local function getOrCreateContainer(): Frame
	if feedContainer and feedContainer.Parent then
		return feedContainer
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		error("[NotificationHud] No LocalPlayer")
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = playerGui:FindFirstChild("NotificationHudGui")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "NotificationHudGui"
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 100
		screenGui.IgnoreGuiInset = false -- respect Roblox top bar / phone safe area
		screenGui.Parent = playerGui
	end

	local container = screenGui:FindFirstChild("Container")
	if not container then
		container = Instance.new("Frame")
		container.Name = "Container"
		container.Size = UDim2.new(1, 0, 0, (TOAST_HEIGHT + TOAST_GAP) * MAX_VISIBLE + TOP_OFFSET)
		container.Position = UDim2.fromScale(0.5, 0)
		container.AnchorPoint = Vector2.new(0.5, 0)
		container.BackgroundTransparency = 1
		container.Parent = screenGui
	end

	feedContainer = container :: Frame
	return feedContainer
end

-- Compute the Y position for slot index (0 = top-most visible slot).
local function slotY(index: number): number
	return TOP_OFFSET + index * (TOAST_HEIGHT + TOAST_GAP)
end

local function buildToast(message: string, container: Frame): Frame
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	-- Scale width (50% of screen) so it adapts to any resolution. UISizeConstraint
	-- caps it at TOAST_MAX_WIDTH on large displays so it stays readable.
	toast.Size = UDim2.new(0.5, 0, 0, TOAST_HEIGHT)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	toast.BackgroundTransparency = 0.15
	toast.BorderSizePixel = 0
	toast.Parent = container

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(TOAST_MAX_WIDTH, TOAST_HEIGHT)
	sizeConstraint.MinSize = Vector2.new(200, TOAST_HEIGHT)
	sizeConstraint.Parent = toast

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = toast

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.fromOffset(12, 0)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = toast

	-- Constrain text size so it doesn't shrink too small on phones or grow
	-- too large on ultra-wide displays.
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 16
	textConstraint.MaxTextSize = 26
	textConstraint.Parent = label

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.fromRGB(0, 0, 0)
	labelStroke.Thickness = 2
	labelStroke.Transparency = 0.3
	labelStroke.Parent = label

	return toast
end

local function tweenToSlot(entry, slotIndex: number)
	local targetY = slotY(slotIndex)
	local tween = TweenService:Create(
		entry.toast,
		TweenInfo.new(TWEEN_SLIDE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, targetY) }
	)
	tween:Play()
end

local function dismissEntry(entry)
	if entry.dismissed then
		return
	end
	entry.dismissed = true

	-- Slide up + fade out
	local tween = TweenService:Create(
		entry.toast,
		TweenInfo.new(TWEEN_OUT_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{
			Position = UDim2.new(0.5, 0, 0, (entry.toast.Position.Y.Offset) - 30),
			BackgroundTransparency = 1,
		}
	)
	-- Fade the text too
	local label = entry.toast:FindFirstChild("Label")
	if label then
		TweenService:Create(
			label,
			TweenInfo.new(TWEEN_OUT_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		):Play()
	end

	tween:Play()
	tween.Completed:Connect(function()
		entry.toast:Destroy()
	end)

	-- Remove from feed
	local idx = table.find(feed, entry)
	if idx then
		table.remove(feed, idx)
	end

	-- Slide remaining entries up
	for i, remaining in feed do
		tweenToSlot(remaining, i - 1)
	end
end

function NotificationHud.Show(message: string)
	local container = getOrCreateContainer()

	-- If we're at capacity, immediately dismiss the oldest.
	while #feed >= MAX_VISIBLE do
		local oldest = feed[#feed]
		dismissEntry(oldest)
	end

	-- Slide existing entries down by one slot to make room at the top.
	for i, existing in feed do
		tweenToSlot(existing, i) -- they were at (i-1), now go to (i)
	end

	-- Build the new toast at the top slot, starting off-screen above.
	local toast = buildToast(message, container)
	toast.Position = UDim2.new(0.5, 0, 0, slotY(0) - TOAST_HEIGHT - 10)

	local entry = {
		toast = toast,
		dismissed = false,
	}

	-- Tween in to slot 0
	local tweenIn = TweenService:Create(
		toast,
		TweenInfo.new(TWEEN_IN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, slotY(0)) }
	)
	tweenIn:Play()

	table.insert(feed, 1, entry)

	-- Auto-dismiss after DISPLAY_DURATION
	task.delay(DISPLAY_DURATION, function()
		dismissEntry(entry)
	end)
end

function NotificationHud.Start()
	-- Pre-build the container so it's ready for the first Show() call.
	getOrCreateContainer()
end

return NotificationHud
