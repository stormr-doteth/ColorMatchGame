local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

export type SliderProps = {
	label: string,
	min: number,
	max: number,
	value: number, -- 0-1 normalized
	onChange: (number) -> (),
	trackColor: Color3?,
	LayoutOrder: number?,
}

local function Slider(props: SliderProps)
	local trackRef = React.useRef(nil :: Instance?)
	-- Track the *specific* input object that started this drag, not a boolean.
	-- On mobile each finger is its own InputObject; using a boolean caused a
	-- second touch on an adjacent slider to accidentally control this one too
	-- (both sliders saw the global InputChanged stream and thought it was
	-- "their" drag). Storing the InputObject lets us ignore unrelated touches.
	local activeInput = React.useRef(nil :: InputObject?)

	local displayValue = math.floor(props.value * (props.max - props.min) + props.min + 0.5)

	local function computeValue(inputX: number)
		local track = trackRef.current
		if not track then
			return nil
		end
		local trackLeft = track.AbsolutePosition.X
		local trackWidth = track.AbsoluteSize.X
		if trackWidth == 0 then
			return nil
		end
		return math.clamp((inputX - trackLeft) / trackWidth, 0, 1)
	end

	React.useEffect(function()
		local moveCon = UserInputService.InputChanged:Connect(function(input)
			if activeInput.current ~= input then
				return
			end
			local val = computeValue(input.Position.X)
			if val then
				props.onChange(val)
			end
		end)

		local endCon = UserInputService.InputEnded:Connect(function(input)
			if activeInput.current == input then
				activeInput.current = nil
			end
		end)

		return function()
			moveCon:Disconnect()
			endCon:Disconnect()
		end
	end, {})

	local trackColor = props.trackColor or Color3.fromRGB(80, 80, 80)

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Label = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Text = `{props.label}: {displayValue}`,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 16,
			Font = Enum.Font.FredokaOne,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		Track = e("Frame", {
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 0, 24),
			BackgroundColor3 = trackColor,
			BorderSizePixel = 0,
			ref = function(rbx)
				trackRef.current = rbx
			end,
			[React.Event.InputBegan] = function(_rbx, input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					-- Only claim the drag if no other finger is already driving
					-- this slider. Prevents a second touch on the track from
					-- yanking the thumb mid-drag.
					if activeInput.current ~= nil then return end
					activeInput.current = input
					local val = computeValue(input.Position.X)
					if val then
						props.onChange(val)
					end
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),

			Fill = e("Frame", {
				Size = UDim2.new(props.value, 0, 1, 0),
				BackgroundColor3 = Color3.fromRGB(100, 180, 255),
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 7),
				}),
			}),

			Thumb = e("Frame", {
				Size = UDim2.fromOffset(22, 22),
				Position = UDim2.new(props.value, -11, 0.5, -11),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		}),
	})
end

return Slider
