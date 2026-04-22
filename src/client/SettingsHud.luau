-- SettingsHud
-- Accessibility settings menu. Opens from a TopBarPlus icon and exposes
-- a single toggle: "Particle Effects". When disabled, every ParticleEmitter
-- and Trail in the game is disabled (including newly-spawned ones). The
-- preference is stored as an attribute on the LocalPlayer so other modules
-- can react if they ever need to.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local TopBar = require(script.Parent:WaitForChild("TopBar"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))

local ATTRIBUTE = "ParticlesDisabled"

local SettingsHud = {}

local function applyParticleState(disabled: boolean)
	local roots = { Workspace, Lighting, Players.LocalPlayer:FindFirstChild("PlayerGui") }
	for _, root in roots do
		if not root then continue end
		for _, desc in root:GetDescendants() do
			if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Smoke") or desc:IsA("Fire") or desc:IsA("Sparkles") then
				desc.Enabled = not disabled
			end
		end
	end
end

local function watchNewEffects()
	local function hook(root: Instance)
		root.DescendantAdded:Connect(function(desc)
			if not Players.LocalPlayer:GetAttribute(ATTRIBUTE) then
				return
			end
			if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Smoke") or desc:IsA("Fire") or desc:IsA("Sparkles") then
				desc.Enabled = false
			end
		end)
	end
	hook(Workspace)
	hook(Lighting)
end

local function buildPanel(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Enabled = false
	gui.Parent = playerGui

	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.5
	shade.BorderSizePixel = 0
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 260)
	panel.BackgroundColor3 = Color3.fromRGB(40, 42, 58)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(90, 95, 125)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 56)
	title.BackgroundTransparency = 1
	title.Text = "Settings"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = panel

	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingTop = UDim.new(0, 12)
	titlePad.PaddingBottom = UDim.new(0, 8)
	titlePad.PaddingLeft = UDim.new(0, 24)
	titlePad.PaddingRight = UDim.new(0, 24)
	titlePad.Parent = title

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -12, 0, 12)
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 70, 80)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.TextSize = 22
	closeBtn.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn

	-- Row: Particle Effects
	local row = Instance.new("Frame")
	row.Name = "ParticlesRow"
	row.Size = UDim2.new(1, -48, 0, 64)
	row.Position = UDim2.new(0, 24, 0, 80)
	row.BackgroundColor3 = Color3.fromRGB(55, 58, 78)
	row.BorderSizePixel = 0
	row.Parent = panel

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local rowLabel = Instance.new("TextLabel")
	rowLabel.Size = UDim2.new(1, -110, 1, 0)
	rowLabel.Position = UDim2.fromOffset(16, 0)
	rowLabel.BackgroundTransparency = 1
	rowLabel.Text = "Particle Effects"
	rowLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	rowLabel.TextXAlignment = Enum.TextXAlignment.Left
	rowLabel.Font = Enum.Font.FredokaOne
	rowLabel.TextSize = 22
	rowLabel.Parent = row

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, -12, 0.5, 0)
	toggle.Size = UDim2.fromOffset(80, 40)
	toggle.BackgroundColor3 = Color3.fromRGB(70, 180, 90)
	toggle.BorderSizePixel = 0
	toggle.Text = "ON"
	toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggle.Font = Enum.Font.FredokaOne
	toggle.TextSize = 20
	toggle.Parent = row

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 8)
	toggleCorner.Parent = toggle

	-- Hint line
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -48, 0, 40)
	hint.Position = UDim2.new(0, 24, 0, 152)
	hint.BackgroundTransparency = 1
	hint.Text = "Turn off particles if effects feel too intense or cause discomfort."
	hint.TextColor3 = Color3.fromRGB(180, 185, 210)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextWrapped = true
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 14
	hint.Parent = panel

	return gui, panel, toggle, shade, closeBtn
end

function SettingsHud.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local gui, _panel, toggle, shade, closeBtn = buildPanel(playerGui)

	local function refreshToggleVisual(disabled: boolean)
		if disabled then
			toggle.Text = "OFF"
			toggle.BackgroundColor3 = Color3.fromRGB(160, 70, 70)
		else
			toggle.Text = "ON"
			toggle.BackgroundColor3 = Color3.fromRGB(70, 180, 90)
		end
	end

	local function setDisabled(disabled: boolean)
		localPlayer:SetAttribute(ATTRIBUTE, disabled)
		refreshToggleVisual(disabled)
		applyParticleState(disabled)
	end

	-- Initial state (default: particles on)
	refreshToggleVisual(false)

	toggle.Activated:Connect(function()
		setDisabled(not localPlayer:GetAttribute(ATTRIBUTE))
	end)

	local icon = TopBar.CreateSettingsIcon()
	icon.selected:Connect(function()
		UIManager.CloseOthers("Settings")
		gui.Enabled = true
	end)
	icon.deselected:Connect(function()
		gui.Enabled = false
	end)

	local function close()
		gui.Enabled = false
		icon:deselect()
	end
	shade.Activated:Connect(close)
	closeBtn.Activated:Connect(close)

	UIManager.Register("Settings", close, function() return gui.Enabled end)

	watchNewEffects()
end

return SettingsHud
