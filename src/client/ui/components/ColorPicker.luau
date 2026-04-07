local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

-- Reusable vertical strip with gradient + draggable thumb
local function VerticalStrip(props: {
	gradient: ColorSequence,
	value: number, -- 0 = top, 1 = bottom
	width: number,
	onChange: (number) -> (),
	LayoutOrder: number?,
})
	local stripRef = React.useRef(nil :: Instance?)
	local dragging = React.useRef(false)

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
			if not dragging.current then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local val = computeValue(input.Position.Y)
				if val then
					props.onChange(val)
				end
			end
		end)

		local endCon = UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging.current = false
			end
		end)

		return function()
			moveCon:Disconnect()
			endCon:Disconnect()
		end
	end, {})

	return e("Frame", {
		Size = UDim2.new(0, props.width, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ref = function(rbx)
			stripRef.current = rbx
		end,
		[React.Event.InputBegan] = function(_rbx, input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging.current = true
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
			Padding = UDim.new(0, 10),
		}),

		HueStrip = e(VerticalStrip, {
			gradient = HUE_GRADIENT,
			value = hue,
			width = 60,
			onChange = props.onChangeH,
			LayoutOrder = 1,
		}),

		SatStrip = e(VerticalStrip, {
			gradient = satGradient,
			value = 1 - sat,
			width = 60,
			onChange = function(v)
				props.onChangeS(1 - v)
			end,
			LayoutOrder = 2,
		}),

		ValStrip = e(VerticalStrip, {
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
