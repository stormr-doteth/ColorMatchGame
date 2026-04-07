local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

local function StrokedText(props)
	return e("TextLabel", props, {
		Stroke = e("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, Transparency = 0.3 }),
	})
end

local function WaitingScreen(props: { opponentName: string?, secondsLeft: number? })
	local dots, setDots = React.useState("")

	React.useEffect(function()
		local running = true
		task.spawn(function()
			local count = 0
			while running do
				count = (count % 3) + 1
				setDots(string.rep(".", count))
				task.wait(0.5)
			end
		end)
		return function()
			running = false
		end
	end, {})

	local text = if props.opponentName and props.opponentName ~= ""
		then `Waiting on {props.opponentName}{dots}`
		else `Waiting for opponent{dots}`

	local secondsLeft = props.secondsLeft
	local showTimer = secondsLeft ~= nil
	local urgent = showTimer and secondsLeft <= 5
	local timerBg = if urgent then Color3.fromRGB(200, 50, 50) else Color3.fromRGB(20, 20, 20)

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Label = StrokedText({
			Size = UDim2.fromOffset(600, 60),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 36,
			Font = Enum.Font.FredokaOne,
		}),

		Timer = showTimer and e("Frame", {
			Size = UDim2.fromOffset(88, 46),
			Position = UDim2.new(1, -16, 0, 16),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = timerBg,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 8,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 12) }),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(255, 255, 255),
				Thickness = 1,
				Transparency = 0.5,
			}),
			SecondsText = StrokedText({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = `{math.ceil(secondsLeft)}s`,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 30,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
			}),
		}),
	})
end

return WaitingScreen
