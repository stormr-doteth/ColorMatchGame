local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

local function StrokedText(props)
	return e("TextLabel", props, {
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(0, 0, 0),
			Thickness = 2,
			Transparency = 0.3,
		}),
	})
end

local function hsvToColor(g: { h: number, s: number, v: number }?): Color3
	if not g then
		return Color3.fromRGB(60, 60, 60)
	end
	return Color3.fromHSV(g.h or 0, g.s or 0, g.v or 0)
end

local function Swatch(props: { color: Color3, Size: UDim2, LayoutOrder: number?, label: string? })
	return e("Frame", {
		Size = props.Size,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 2),
		}),
		Block = e("Frame", {
			Size = UDim2.new(1, 0, 1, -14),
			BackgroundColor3 = props.color,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(255, 255, 255),
				Thickness = 1,
				Transparency = 0.6,
			}),
		}),
		Label = props.label and e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			Text = props.label,
			TextColor3 = Color3.fromRGB(180, 180, 180),
			TextSize = 11,
			Font = Enum.Font.FredokaOne,
			LayoutOrder = 2,
		}),
	})
end

export type RoundEntry = {
	target: { h: number, s: number, v: number },
	myGuess: { h: number, s: number, v: number }?,
	opponentGuess: { h: number, s: number, v: number }?,
	myScore: number,
	opponentScore: number?,
	outcome: string,
}

export type HistoryGridProps = {
	history: { RoundEntry },
	isSolo: boolean?,
	LayoutOrder: number?,
}

local CARD_WIDTH = 110
local CARD_HEIGHT_1V1 = 230
local CARD_HEIGHT_SOLO = 180

local function RoundCard(props: { entry: RoundEntry, roundNumber: number, isSolo: boolean, LayoutOrder: number })
	local entry = props.entry
	local targetColor = hsvToColor(entry.target)
	local myColor = hsvToColor(entry.myGuess)

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 4),
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
		}),

		RoundLabel = StrokedText({
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = `R{props.roundNumber}`,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			TextSize = 14,
			Font = Enum.Font.FredokaOne,
			LayoutOrder = 1,
		}),

		Target = e(Swatch, {
			Size = UDim2.fromOffset(86, 50),
			color = targetColor,
			label = "Target",
			LayoutOrder = 2,
		}),

		MyGuess = e(Swatch, {
			Size = UDim2.fromOffset(86, 50),
			color = myColor,
			label = "You",
			LayoutOrder = 3,
		}),
	}

	if not props.isSolo then
		local oppColor = hsvToColor(entry.opponentGuess)
		children.OppGuess = e(Swatch, {
			Size = UDim2.fromOffset(86, 50),
			color = oppColor,
			label = "Opp",
			LayoutOrder = 4,
		})
	end

	-- Score line
	local scoreText
	if props.isSolo then
		scoreText = `{entry.myScore}%`
	else
		scoreText = `{entry.myScore} / {entry.opponentScore or 0}`
	end

	local outcomeColor
	if entry.outcome == "win" then
		outcomeColor = Color3.fromRGB(100, 255, 100)
	elseif entry.outcome == "loss" then
		outcomeColor = Color3.fromRGB(255, 100, 100)
	else
		outcomeColor = Color3.fromRGB(220, 220, 220)
	end

	children.Score = StrokedText({
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = scoreText,
		TextColor3 = outcomeColor,
		TextSize = 16,
		Font = Enum.Font.FredokaOne,
		LayoutOrder = 5,
	})

	local cardHeight = if props.isSolo then CARD_HEIGHT_SOLO else CARD_HEIGHT_1V1

	return e("Frame", {
		Size = UDim2.fromOffset(CARD_WIDTH, cardHeight),
		BackgroundColor3 = Color3.fromRGB(35, 35, 35),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Stroke = e("UIStroke", {
			Color = outcomeColor,
			Thickness = 2,
			Transparency = 0.4,
		}),
		Inner = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, children),
	})
end

local function HistoryGrid(props: HistoryGridProps)
	local isSolo = props.isSolo or false

	-- Filter out ties (1v1 only — solo entries are always kept)
	local filtered: { RoundEntry } = {}
	for _, entry in props.history do
		if isSolo or entry.outcome ~= "tie" then
			table.insert(filtered, entry)
		end
	end

	local cards: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	}

	for i, entry in filtered do
		cards["Card" .. i] = e(RoundCard, {
			entry = entry,
			roundNumber = i,
			isSolo = isSolo,
			LayoutOrder = i,
		})
	end

	local cardHeight = if isSolo then CARD_HEIGHT_SOLO else CARD_HEIGHT_1V1

	return e("Frame", {
		Size = UDim2.fromOffset(5 * (CARD_WIDTH + 8), cardHeight + 12),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, cards)
end

return HistoryGrid
