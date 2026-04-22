-- FeedbackHud
-- Modal that lets the user type free-form feedback. On submit the text is
-- fired to the server over the SubmitFeedback remote, where it's persisted in
-- a DataStore for the developer to review.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FeedbackHud = {}

local MAX_LEN = 500

local localPlayer = Players.LocalPlayer
local gui: ScreenGui? = nil
local visible = false

local function buildUi(playerGui: PlayerGui): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = "FeedbackHud"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 100
	g.Enabled = false
	g.Parent = playerGui

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.4
	dim.BorderSizePixel = 0
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = g

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.6, 0.55)
	panel.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
	panel.BorderSizePixel = 0
	panel.Parent = g

	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MinSize = Vector2.new(300, 280)
	sizeCap.MaxSize = Vector2.new(640, 480)
	sizeCap.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Text = "Send Feedback"
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.new(0, 0, 0, 32)
	subtitle.Size = UDim2.new(1, 0, 0, 20)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Bugs, ideas, anything. Read by the devs."
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 190)
	subtitle.TextScaled = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = panel

	local inputWrap = Instance.new("Frame")
	inputWrap.Name = "InputWrap"
	inputWrap.Position = UDim2.new(0, 0, 0, 60)
	inputWrap.Size = UDim2.new(1, 0, 1, -120)
	inputWrap.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	inputWrap.BorderSizePixel = 0
	inputWrap.Parent = panel

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 8)
	inputCorner.Parent = inputWrap

	local inputPad = Instance.new("UIPadding")
	inputPad.PaddingTop = UDim.new(0, 8)
	inputPad.PaddingBottom = UDim.new(0, 8)
	inputPad.PaddingLeft = UDim.new(0, 10)
	inputPad.PaddingRight = UDim.new(0, 10)
	inputPad.Parent = inputWrap

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.Size = UDim2.fromScale(1, 1)
	input.BackgroundTransparency = 1
	input.Text = ""
	input.PlaceholderText = "Type your feedback here..."
	input.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
	input.TextColor3 = Color3.fromRGB(240, 240, 245)
	input.Font = Enum.Font.Gotham
	input.TextSize = 16
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = Enum.TextYAlignment.Top
	input.TextWrapped = true
	input.MultiLine = true
	input.ClearTextOnFocus = false
	input.Parent = inputWrap

	local counter = Instance.new("TextLabel")
	counter.Name = "Counter"
	counter.AnchorPoint = Vector2.new(1, 0)
	counter.Position = UDim2.new(1, 0, 1, -54)
	counter.Size = UDim2.new(0, 80, 0, 18)
	counter.BackgroundTransparency = 1
	counter.Text = `0 / {MAX_LEN}`
	counter.Font = Enum.Font.Gotham
	counter.TextColor3 = Color3.fromRGB(140, 140, 150)
	counter.TextSize = 13
	counter.TextXAlignment = Enum.TextXAlignment.Right
	counter.Parent = panel

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "Cancel"
	cancelBtn.AnchorPoint = Vector2.new(0, 1)
	cancelBtn.Position = UDim2.new(0, 0, 1, 0)
	cancelBtn.Size = UDim2.new(0.48, -4, 0, 44)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(70, 74, 88)
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Text = "Cancel"
	cancelBtn.Font = Enum.Font.FredokaOne
	cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancelBtn.TextScaled = true
	cancelBtn.AutoButtonColor = true
	cancelBtn.Parent = panel
	Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 8)

	local submitBtn = Instance.new("TextButton")
	submitBtn.Name = "Submit"
	submitBtn.AnchorPoint = Vector2.new(1, 1)
	submitBtn.Position = UDim2.new(1, 0, 1, 0)
	submitBtn.Size = UDim2.new(0.48, -4, 0, 44)
	submitBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 120)
	submitBtn.BorderSizePixel = 0
	submitBtn.Text = "Submit"
	submitBtn.Font = Enum.Font.FredokaOne
	submitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	submitBtn.TextScaled = true
	submitBtn.AutoButtonColor = true
	submitBtn.Parent = panel
	Instance.new("UICorner", submitBtn).CornerRadius = UDim.new(0, 8)

	input:GetPropertyChangedSignal("Text"):Connect(function()
		if #input.Text > MAX_LEN then
			input.Text = string.sub(input.Text, 1, MAX_LEN)
		end
		counter.Text = `{#input.Text} / {MAX_LEN}`
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local submitRemote = remotes:WaitForChild("SubmitFeedback") :: RemoteEvent

	local function close()
		visible = false
		g.Enabled = false
	end

	cancelBtn.Activated:Connect(close)
	dim.Activated:Connect(close)

	submitBtn.Activated:Connect(function()
		local text = input.Text
		if #text < 3 then
			submitBtn.Text = "Too short!"
			task.delay(1.2, function() submitBtn.Text = "Submit" end)
			return
		end
		submitRemote:FireServer(text)
		input.Text = ""
		submitBtn.Text = "Thanks!"
		task.wait(0.9)
		submitBtn.Text = "Submit"
		close()
	end)

	-- Pop in
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = panel
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	return g
end

function FeedbackHud.Toggle()
	if not gui then
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		gui = buildUi(playerGui)
	end
	visible = not visible;
	(gui :: ScreenGui).Enabled = visible
end

function FeedbackHud.Start()
	-- Build lazily on first toggle to avoid creating the UI for players who
	-- never open it.
end

return FeedbackHud
