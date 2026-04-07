local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local ColorDisplay = require(script.Parent.ColorDisplay)

local e = React.createElement

export type ScoreScreenProps = {
	targetColor: Color3,
	guessColor: Color3,
	score: number,
	onPlayAgain: () -> (),
}

local function ScoreScreen(props: ScoreScreenProps)
	return e("Frame", {
		Size = UDim2.fromOffset(800, 600),
		BackgroundTransparency = 1,
	}, {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 24),
		}),

		Title = e("TextLabel", {
			Size = UDim2.fromOffset(500, 56),
			BackgroundTransparency = 1,
			Text = `{props.score}% Match!`,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 48,
			Font = Enum.Font.FredokaOne,
			LayoutOrder = 1,
		}),

		Colors = e("Frame", {
			Size = UDim2.fromOffset(500, 240),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 32),
			}),

			Target = e(ColorDisplay, {
				color = props.targetColor,
				Size = UDim2.fromOffset(200, 200),
				label = "Target",
				LayoutOrder = 1,
			}),

			Guess = e(ColorDisplay, {
				color = props.guessColor,
				Size = UDim2.fromOffset(200, 200),
				label = "Your Guess",
				LayoutOrder = 2,
			}),
		}),

		PlayAgain = e("TextButton", {
			Size = UDim2.fromOffset(260, 60),
			BackgroundColor3 = Color3.fromRGB(60, 140, 255),
			BorderSizePixel = 0,
			Text = "Play Again",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 24,
			Font = Enum.Font.FredokaOne,
			LayoutOrder = 3,
			[React.Event.Activated] = props.onPlayAgain,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
		}),
	})
end

return ScoreScreen
