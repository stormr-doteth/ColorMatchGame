local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

local function WaitingScreen(props: { opponentName: string? })
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

	local text = if props.opponentName
		then `Playing vs {props.opponentName}{dots}`
		else `Waiting for opponent{dots}`

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Label = e("TextLabel", {
			Size = UDim2.fromOffset(600, 60),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 36,
			Font = Enum.Font.GothamBold,
		}),
	})
end

return WaitingScreen
