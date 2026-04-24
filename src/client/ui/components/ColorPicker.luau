local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

-- Gamepad tuning: thumbstick gives smooth drag, D-pad gives discrete nudge.
local DPAD_STEP = 0.02
local THUMBSTICK_SPEED = 0.9 -- units per second at full deflection
local THUMBSTICK_DEADZONE = 0.2

-- Reusable vertical strip with gradient + draggable thumb
local function VerticalStrip(props: {
	gradient: ColorSequence,
	value: number, -- 0 = top, 1 = bottom
	width: number,
	onChange: (number) -> (),
	LayoutOrder: number?,
	Name: string?,
})
	local stripRef = React.useRef(nil :: Instance?)
	-- Track the specific InputObject (a single finger) that owns this drag so
	-- a second touch on an adjacent strip doesn't hijack the thumb of this one.
	-- On mobile the three strips are ~60px wide and ~10px apart, so fingers
	-- frequently stray across the boundary mid-drag.
	local activeInput = React.useRef(nil :: InputObject?)
	local focused = React.useRef(false)
	-- Latest value/onChange captured in a ref so long-lived Heartbeat/input
	-- callbacks registered once in useEffect always read current values.
	local latest = React.useRef({ value = props.value, onChange = props.onChange })
	latest.current.value = props.value
	latest.current.onChange = props.onChange

	local function computeValue(inputY: number)
		local strip = stripRef.current
		if not strip then
			return nil
		end
		local top = strip.AbsolutePosition.Y
		local height = strip.AbsoluteSize.Y
		if height == 0 then
			return nil
		end
		return math.clamp((inputY - top) / height, 0, 1)
	end

	React.useEffect(function()
		local moveCon = UserInputService.InputChanged:Connect(function(input)
			if activeInput.current ~= input then
				return
			end
			local val = computeValue(input.Position.Y)
			if val then
				props.onChange(val)
			end
		end)

		local endCon = UserInputService.InputEnded:Connect(function(input)
			if activeInput.current == input then
				activeInput.current = nil
			end
		end)

		-- Gamepad: D-pad up/down = discrete step; left thumbstick Y = continuous.
		local dpadCon = UserInputService.InputBegan:Connect(function(input, processed)
			if processed or not focused.current then return end
			if input.KeyCode == Enum.KeyCode.DPadUp then
				local v = math.clamp(latest.current.value - DPAD_STEP, 0, 1)
				latest.current.onChange(v)
			elseif input.KeyCode == Enum.KeyCode.DPadDown then
				local v = math.clamp(latest.current.value + DPAD_STEP, 0, 1)
				latest.current.onChange(v)
			end
		end)

		local heartbeatCon = RunService.Heartbeat:Connect(function(dt)
			if not focused.current then return end
			local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
			for _, input in state do
				if input.KeyCode == Enum.KeyCode.Thumbstick1 then
					local y = input.Position.Y
					if math.abs(y) > THUMBSTICK_DEADZONE then
						-- Thumbstick up is +Y; our "value" grows downward, so subtract.
						local delta = -y * THUMBSTICK_SPEED * dt
						local v = math.clamp(latest.current.value + delta, 0, 1)
						latest.current.onChange(v)
					end
					break
				end
			end
		end)

		return function()
			moveCon:Disconnect()
			endCon:Disconnect()
			dpadCon:Disconnect()
			heartbeatCon:Disconnect()
		end
	end, {})

	return e("TextButton", {
		Name = props.Name or "Strip",
		Size = UDim2.new(0, props.width, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		Text = "",
		AutoButtonColor = false,
		Selectable = true,
		ref = function(rbx)
			stripRef.current = rbx
		end,
		[React.Event.SelectionGained] = function()
			focused.current = true
		end,
		[React.Event.SelectionLost] = function()
			focused.current = false
		end,
		[React.Event.InputBegan] = function(_rbx, input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				-- Refuse the touch if this strip already has a finger down, and
				-- also refuse if ANY strip currently has an active drag (we
				-- check via the shared ref pattern below). This keeps one finger
				-- = one strip, which is the mental model players expect.
				if activeInput.current ~= nil then return end
				activeInput.current = input
				local val = computeValue(input.Position.Y)
				if val then
					props.onChange(val)
				end
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 6),
		}),

		Gradient = e("UIGradient", {
			Color = props.gradient,
			Rotation = 90, -- top to bottom
		}),

		Thumb = e("Frame", {
			Size = UDim2.new(1, 10, 0, 18),
			Position = UDim2.new(0.5, 0, props.value, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(40, 40, 40),
				Thickness = 2,
			}),
		}),
	})
end

-- Hue rainbow gradient (constant)
local HUE_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
	ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
	ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
	ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
	ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
	ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
})

export type ColorPickerProps = {
	guessH: number, -- 0-1
	guessS: number, -- 0-1
	guessV: number, -- 0-1
	onChangeH: (number) -> (),
	onChangeS: (number) -> (),
	onChangeV: (number) -> (),
}

local function ColorPicker(props: ColorPickerProps)
	local hue = props.guessH
	local sat = props.guessS
	local val = props.guessV

	-- Saturation gradient: full sat at top → white at bottom (based on current hue)
	local satGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, 0, 1)),
	})

	-- Brightness gradient: full brightness at top → black at bottom (based on current hue+sat)
	local valGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, sat, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, sat, 0)),
	})

	return e("Frame", {
		Size = UDim2.new(0, 200, 1, 0),
		BackgroundTransparency = 1,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			-- Wider spacing so fingers don't straddle two strips at once on
			-- touch. The per-strip input-lock handles the edge cases, but a
			-- physical gap gives players confidence they're hitting one.
			Padding = UDim.new(0, 18),
		}),

		HueStrip = e(VerticalStrip, {
			Name = "HueStrip",
			gradient = HUE_GRADIENT,
			value = hue,
			width = 60,
			onChange = props.onChangeH,
			LayoutOrder = 1,
		}),

		SatStrip = e(VerticalStrip, {
			Name = "SatStrip",
			gradient = satGradient,
			value = 1 - sat,
			width = 60,
			onChange = function(v)
				props.onChangeS(1 - v)
			end,
			LayoutOrder = 2,
		}),

		ValStrip = e(VerticalStrip, {
			Name = "ValStrip",
			gradient = valGradient,
			value = 1 - val,
			width = 60,
			onChange = function(v)
				props.onChangeV(1 - v)
			end,
			LayoutOrder = 3,
		}),
	})
end

return ColorPicker
