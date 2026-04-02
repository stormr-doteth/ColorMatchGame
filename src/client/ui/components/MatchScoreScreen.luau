local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local ColorDisplay = require(script.Parent.ColorDisplay)

local e = React.createElement

export type MatchScoreScreenProps = {
	targetColor: Color3,
	myColor: Color3,
	opponentColor: Color3?,
	myScore: number,
	opponentScore: number,
	myWins: number,
	opponentWins: number,
	opponentName: string,
	roundsToWin: number,
}

local function MatchScoreScreen(props: MatchScoreScreenProps)
	local myWon = props.myScore > props.opponentScore
	local tied = props.myScore == props.opponentScore

	local roundText
	if tied then
		roundText = "Tie!"
	elseif myWon then
		roundText = "You win this round!"
	else
		roundText = `{props.opponentName} wins this round!`
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 16),
		}),

		RoundLabel = e("TextLabel", {
			Size = UDim2.fromOffset(600, 40),
			BackgroundTransparency = 1,
			Text = roundText,
			TextColor3 = if tied
				then Color3.fromRGB(255, 255, 100)
				elseif myWon then Color3.fromRGB(100, 255, 100)
				else Color3.fromRGB(255, 100, 100),
			TextSize = 32,
			Font = Enum.Font.GothamBold,
			LayoutOrder = 1,
		}),

		-- Scores side by side
		Scores = e("Frame", {
			Size = UDim2.fromOffset(600, 60),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 40),
			}),

			MyScore = e("TextLabel", {
				Size = UDim2.fromOffset(200, 50),
				BackgroundTransparency = 1,
				Text = `You: {props.myScore}%`,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 28,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 1,
			}),

			OppScore = e("TextLabel", {
				Size = UDim2.fromOffset(200, 50),
				BackgroundTransparency = 1,
				Text = `{props.opponentName}: {props.opponentScore}%`,
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextSize = 28,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 2,
			}),
		}),

		-- Color swatches: target + my guess
		Colors = e("Frame", {
			Size = UDim2.fromOffset(500, 180),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 24),
			}),

			Target = e(ColorDisplay, {
				color = props.targetColor,
				Size = UDim2.fromOffset(140, 140),
				label = "Target",
				LayoutOrder = 1,
			}),

			MyGuess = e(ColorDisplay, {
				color = props.myColor,
				Size = UDim2.fromOffset(140, 140),
				label = "You",
				LayoutOrder = 2,
			}),
		}),

		-- Win tally
		Tally = e("TextLabel", {
			Size = UDim2.fromOffset(500, 36),
			BackgroundTransparency = 1,
			Text = `Wins — You: {props.myWins}/{props.roundsToWin}  |  {props.opponentName}: {props.opponentWins}/{props.roundsToWin}`,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 22,
			Font = Enum.Font.GothamMedium,
			LayoutOrder = 4,
		}),
	})
end

return MatchScoreScreen
