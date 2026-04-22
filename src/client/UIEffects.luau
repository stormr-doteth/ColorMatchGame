-- UIEffects
-- Simple hover + press visual feedback for GUI buttons. One click sound
-- plays per Activated. No hover sound, no press-time sound.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SoundManager = require(script.Parent:WaitForChild("SoundManager"))

local UIEffects = {}

local HOVER_IN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_DOWN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PRESS_UP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.92

local function getOrCreateScale(target: GuiObject): UIScale
	local s = target:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Scale = 1
		s.Parent = target
	end
	return s
end

-- Nested-button pattern: a styled Frame "SubmitButton" with a child
-- TextButton also named "SubmitButton". Walk up while parent shares the
-- name so hover/press scales the visual frame, not just the inner text.
local function resolveVisual(target: GuiObject): GuiObject
	local visual: GuiObject = target
	while visual.Parent and visual.Parent:IsA("GuiObject") and (visual.Parent :: GuiObject).Name == visual.Name do
		visual = visual.Parent :: GuiObject
	end
	return visual
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

function UIEffects.BindButton(target: GuiObject)
	if target:GetAttribute("UIEffectsBound") then return end
	target:SetAttribute("UIEffectsBound", true)

	local visual = resolveVisual(target)
	local ui = getOrCreateScale(visual)
	local base = ui.Scale

	if not isTouch() then
		target.MouseEnter:Connect(function()
			TweenService:Create(ui, HOVER_IN, { Scale = base * HOVER_SCALE }):Play()
		end)
		target.MouseLeave:Connect(function()
			TweenService:Create(ui, HOVER_OUT, { Scale = base }):Play()
		end)
	end

	target.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(ui, PRESS_DOWN, { Scale = base * PRESS_SCALE }):Play()
		end
	end)
	target.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(ui, PRESS_UP, { Scale = base }):Play()
		end
	end)

	if target:IsA("GuiButton") then
		(target :: GuiButton).Activated:Connect(function()
			SoundManager.Play("click")
		end)
	end
end

return UIEffects
