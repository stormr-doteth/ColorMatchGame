-- CloseHint
-- Shows a small "Ⓑ Close" pill next to the X button on panel headers so
-- controller users know they can press ButtonB to close. The pill auto-hides
-- when no gamepad is active.

local UserInputService = game:GetService("UserInputService")

local CloseHint = {}

function CloseHint.Attach(header: Instance)
	if header:FindFirstChild("CloseHintPill") then return end
	local pill = Instance.new("Frame")
	pill.Name = "CloseHintPill"
	pill.AnchorPoint = Vector2.new(1, 0.5)
	-- Sit to the left of the CloseButton at right edge of header.
	pill.Position = UDim2.new(1, -52, 0.5, 0)
	pill.Size = UDim2.fromOffset(86, 34)
	pill.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.ZIndex = 20
	pill.Visible = false
	pill.Parent = header

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = pill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "Ⓑ Close"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.ZIndex = 21
	label.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = label

	local function updateVisibility()
		pill.Visible = UserInputService.GamepadEnabled
			and UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	end
	updateVisibility()
	UserInputService.LastInputTypeChanged:Connect(updateVisibility)
end

return CloseHint
