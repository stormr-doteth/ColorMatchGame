local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

local function StrokedText(props)
	local strokeTransparency = math.max(props.TextTransparency or 0, 0.3)
	return e("TextLabel", props, {
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(0, 0, 0),
			Thickness = 2,
			Transparency = strokeTransparency,
		}),
	})
end

-- Profile picture from Roblox
local function PlayerAvatar(props: { userId: number, Size: UDim2, LayoutOrder: number? })
	local imageUrl = ""
	if props.userId and props.userId > 0 then
		imageUrl = `rbxthumb://type=AvatarHeadShot&id={props.userId}&w=150&h=150`
	end

	return e("ImageLabel", {
		Size = props.Size,
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Image = imageUrl,
		LayoutOrder = props.LayoutOrder,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 2,
			Transparency = 0.3,
		}),
	})
end

-- Per-round dots: checkmark for win, X for loss, blank for tie/future
local function RoundDots(props: { roundOutcomes: { string }, maxRounds: number, LayoutOrder: number? })
	local dots = {}
	dots.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})

	for i = 1, props.maxRounds do
		local outcome = props.roundOutcomes[i]
		local bgColor
		if outcome == "win" then
			bgColor = Color3.fromRGB(50, 220, 50)
		elseif outcome == "loss" then
			bgColor = Color3.fromRGB(220, 60, 60)
		else
			bgColor = Color3.fromRGB(60, 60, 60)
		end

		local children: { [string]: any } = {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}

		if outcome == "win" then
			children.Check = e("ImageLabel", {
				Size = UDim2.fromScale(0.8, 0.8),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = "rbxassetid://121564337913131",
				ScaleType = Enum.ScaleType.Fit,
			})
		elseif outcome == "loss" then
			children.X = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "✕",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 18,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
			})
		end

		dots["Dot" .. i] = e("Frame", {
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, children)
	end

	return e("Frame", {
		Size = UDim2.fromOffset(props.maxRounds * 28, 24),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, dots)
end

local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- Flavor text shown under the solo score, picked once per round from the
-- tier matching the player's score. Tiers are ordered high → low.
local SCORE_FLAIR = {
	{ min = 95, lines = {
		"Your eyes don't lie.",
		"Practically photographic.",
		"Suspiciously good.",
	}},
	{ min = 85, lines = {
		"Sharp eye.",
		"Off by a hair.",
		"Almost nailed it.",
	}},
	{ min = 70, lines = {
		"In the right neighborhood.",
		"Close enough to be proud.",
		"Your brain held on to most of it.",
	}},
	{ min = 50, lines = {
		"You're hovering near it.",
		"Half-remembered.",
		"Adjacent to correct.",
		"Recognizable, at least.",
	}},
	{ min = 25, lines = {
		"Your memory wandered.",
		"The color drifted on the way over.",
		"You remembered a different color.",
	}},
	{ min = 0, lines = {
		"Your brain autocorrected to a different color entirely.",
		"Was that even a color?",
		"Bold choice. Wrong, but bold.",
		"Even a random guess would've done better.",
	}},
}

local function pickFlair(score: number): string
	for _, tier in SCORE_FLAIR do
		if score >= tier.min then
			return tier.lines[math.random(1, #tier.lines)]
		end
	end
	return ""
end

export type RevealScreenProps = {
	targetColor: Color3,
	guessColor: Color3,
	score: number,
	roundNumber: number?,
	totalRounds: number?,
	onNext: (() -> ())?,
	solo: boolean?,
	opponentScore: number?,
	opponentName: string?,
	opponentGuessColor: Color3?,
	myWins: number?,
	opponentWins: number?,
	myUserId: number?,
	opponentUserId: number?,
	roundsToWin: number?,
	myRoundOutcomes: { string }?,
	opponentRoundOutcomes: { string }?,
}

-- Vertical bar with player info for 1v1 reveal
local function PlayerBar(props: {
	barColor: Color3,
	barHeight: number,
	contentAlpha: number,
	animatedScore: number,
	userId: number,
	displayName: string,
	roundOutcomes: { string },
	maxRounds: number,
	dotsRevealed: boolean,
	hsvText: string,
	isWinner: boolean,
	winnerGlow: number,
	checkmarkScale: number,
	xPosition: number,
	layoutOrder: number,
})
	local barPixelHeight = math.max(0, props.barHeight * 560)
	local textAlpha = 1 - props.contentAlpha
	local scoreText = string.format("%.2f", props.animatedScore)

	return e("Frame", {
		Size = UDim2.fromOffset(248, barPixelHeight),
		Position = UDim2.new(0, props.xPosition, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = props.barColor,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 14) }),

		-- Gold winner glow
		WinnerStroke = props.isWinner and e("UIStroke", {
			Color = Color3.fromRGB(255, 215, 0),
			Thickness = 3,
			Transparency = 1 - props.winnerGlow,
		}),

		-- Content container anchored to bottom of bar
		Content = e("Frame", {
			Size = UDim2.new(1, 0, 0, 560),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 20),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),

			-- Green checkmark (only for round winner)
			Checkmark = props.isWinner and e("ImageLabel", {
				Size = UDim2.fromOffset(
					math.floor(96 * math.clamp(props.checkmarkScale, 0, 1.2)),
					math.floor(96 * math.clamp(props.checkmarkScale, 0, 1.2))
				),
				BackgroundTransparency = 1,
				Image = "rbxassetid://121564337913131",
				ImageTransparency = textAlpha,
				ScaleType = Enum.ScaleType.Fit,
				LayoutOrder = 0,
			}),

			Avatar = e(PlayerAvatar, {
				userId = props.userId,
				Size = UDim2.fromOffset(84, 84),
				LayoutOrder = 1,
			}),

			Name = StrokedText({
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				Text = props.displayName,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = textAlpha,
				TextSize = 24,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 2,
			}),

			Dots = e("Frame", {
				Size = UDim2.new(0, props.maxRounds * 28, 0, 24),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, {
				Inner = e(RoundDots, {
					roundOutcomes = (function()
						-- Hide the latest dot until the result is revealed,
						-- so the dot color doesn't spoil who won.
						if props.dotsRevealed then
							return props.roundOutcomes
						end
						local sliced = {}
						for i = 1, #props.roundOutcomes - 1 do
							table.insert(sliced, props.roundOutcomes[i])
						end
						return sliced
					end)(),
					maxRounds = props.maxRounds,
				}),
			}),

			ScoreLabel = StrokedText({
				Size = UDim2.new(1, 0, 0, 80),
				BackgroundTransparency = 1,
				Text = scoreText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = textAlpha,
				TextSize = 72,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 4,
			}),

			HSV = StrokedText({
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				Text = props.hsvText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = math.max(textAlpha, 0.3),
				TextSize = 18,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 5,
			}),
		}),
	})
end

local function RevealScreen(props: RevealScreenProps)
	-- Animation state for 1v1 vertical bars
	local leftBarT, setLeftBarT = React.useState(0)
	local rightBarT, setRightBarT = React.useState(0)
	local centerBarT, setCenterBarT = React.useState(0)
	local contentAlpha, setContentAlpha = React.useState(0)
	local animatedScore, setAnimatedScore = React.useState(0)
	local animatedOppScore, setAnimatedOppScore = React.useState(0)
	local winnerGlow, setWinnerGlow = React.useState(0)
	local checkmarkScale, setCheckmarkScale = React.useState(0)
	local dotsRevealed, setDotsRevealed = React.useState(false)

	-- Solo mode: staggered panel entrance (top first, then bottom)
	local topPanelT, setTopPanelT = React.useState(0)
	local bottomPanelT, setBottomPanelT = React.useState(0)
	-- Flair line under the score — picked once per mount via a ref so it
	-- stays stable across re-renders within the same round (Roact-compat
	-- doesn't honor function initializers for useState).
	local flairRef = React.useRef(nil :: string?)
	if flairRef.current == nil then
		flairRef.current = pickFlair(props.score)
	end
	local flairText = flairRef.current

	local is1v1 = not props.solo and props.opponentName and props.opponentName ~= ""

	React.useEffect(function()
		local running = true

		if is1v1 then
			-- Staggered vertical bar animation — slower for drama
			task.spawn(function()
				local startTime = tick()

				-- Timing offsets (slowed down)
				local LEFT_START = 0
				local LEFT_DUR = 0.6
				local RIGHT_START = 0.3
				local RIGHT_DUR = 0.6
				local CENTER_START = 1.2       -- dramatic pause before target reveal
				local CENTER_DUR = 0.7
				local CONTENT_START = 2.0
				local CONTENT_DUR = 0.4
				local SCORE_START = 2.5
				local SCORE_DUR = 1.0
				local GLOW_START = 2.5
				local GLOW_DUR = 0.4
				local CHECK_START = 3.5        -- checkmark pops in after scores settle
				local CHECK_DUR = 0.35
				local TOTAL = CHECK_START + CHECK_DUR

				while running do
					local elapsed = tick() - startTime

					-- Left bar
					local lt = math.clamp((elapsed - LEFT_START) / LEFT_DUR, 0, 1)
					setLeftBarT(if lt > 0 then easeOutBack(lt) else 0)

					-- Right bar
					local rt = math.clamp((elapsed - RIGHT_START) / RIGHT_DUR, 0, 1)
					setRightBarT(if rt > 0 then easeOutBack(rt) else 0)

					-- Center bar
					local ct = math.clamp((elapsed - CENTER_START) / CENTER_DUR, 0, 1)
					setCenterBarT(if ct > 0 then easeOutBack(ct) else 0)

					-- Content fade
					local ca = math.clamp((elapsed - CONTENT_START) / CONTENT_DUR, 0, 1)
					setContentAlpha(ca)

					-- Score counters
					local st = math.clamp((elapsed - SCORE_START) / SCORE_DUR, 0, 1)
					local scoreEased = 1 - (1 - st) * (1 - st)
					setAnimatedScore(math.floor(scoreEased * props.score * 100 + 0.5) / 100)
					setAnimatedOppScore(math.floor(scoreEased * (props.opponentScore or 0) * 100 + 0.5) / 100)

					-- Winner glow
					local gt = math.clamp((elapsed - GLOW_START) / GLOW_DUR, 0, 1)
					setWinnerGlow(gt)

					-- Checkmark bounce in
					local ck = math.clamp((elapsed - CHECK_START) / CHECK_DUR, 0, 1)
					setCheckmarkScale(if ck > 0 then easeOutBack(ck) else 0)

					-- Reveal the latest dot at the same moment the checkmark pops in
					if elapsed >= CHECK_START then
						setDotsRevealed(true)
					end

					if elapsed >= TOTAL then break end
					task.wait()
				end

				if running then
					setAnimatedScore(props.score)
					setAnimatedOppScore(props.opponentScore or 0)
					setContentAlpha(1)
					setWinnerGlow(1)
					setCheckmarkScale(1)
					setLeftBarT(1)
					setRightBarT(1)
					setCenterBarT(1)
					setDotsRevealed(true)
				end
			end)
		else
			-- Solo mode: top panel slides in from above, then bottom from below,
			-- then the score counts up. Each panel's color also lerps from grey
			-- to its real color across its own slide so the reveal feels smooth.
			task.spawn(function()
				local startTime = tick()
				local TOP_START = 0.0
				local TOP_DUR = 0.55
				local BOT_START = 0.40
				local BOT_DUR = 0.55
				local SCORE_START = 1.05
				local SCORE_DUR = 0.85
				local TOTAL = SCORE_START + SCORE_DUR

				while running do
					local elapsed = tick() - startTime

					local tt = math.clamp((elapsed - TOP_START) / TOP_DUR, 0, 1)
					setTopPanelT(1 - (1 - tt) * (1 - tt))

					local bt = math.clamp((elapsed - BOT_START) / BOT_DUR, 0, 1)
					setBottomPanelT(1 - (1 - bt) * (1 - bt))

					local st = math.clamp((elapsed - SCORE_START) / SCORE_DUR, 0, 1)
					local scoreEased = 1 - (1 - st) * (1 - st)
					setAnimatedScore(math.floor(scoreEased * props.score * 100 + 0.5) / 100)

					if elapsed >= TOTAL then break end
					task.wait()
				end
				if running then
					setTopPanelT(1)
					setBottomPanelT(1)
					setAnimatedScore(props.score)
				end
			end)
		end

		return function()
			running = false
		end
	end, {})

	local gH, gS, gV = props.guessColor:ToHSV()
	local tH, tS, tV = props.targetColor:ToHSV()
	local guessHSV = `H{math.floor(gH * 360)} S{math.floor(gS * 100)} B{math.floor(gV * 100)}`
	local targetHSV = `H{math.floor(tH * 360)} S{math.floor(tS * 100)} B{math.floor(tV * 100)}`

	-- 1v1 mode: three vertical bars
	if is1v1 then
		local opColor = props.opponentGuessColor or Color3.new(0.5, 0.5, 0.5)
		local oH, oS, oV = opColor:ToHSV()
		local oppHSV = `H{math.floor(oH * 360)} S{math.floor(oS * 100)} B{math.floor(oV * 100)}`
		local myWon = props.score > (props.opponentScore or 0)
		local isTie = props.score == (props.opponentScore or 0)
		local localPlayer = Players.LocalPlayer

		local centerBarHeight = math.max(0, centerBarT * 560)
		local textAlpha = 1 - contentAlpha

		local winnerText = if isTie then "It's a tie!"
			elseif myWon then "You win this round!"
			else `{props.opponentName} wins!`

		return e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			-- Left bar: Your guess
			LeftBar = e(PlayerBar, {
				barColor = props.guessColor,
				barHeight = leftBarT,
				contentAlpha = contentAlpha,
				animatedScore = animatedScore,
				userId = props.myUserId or (localPlayer and localPlayer.UserId or 0),
				displayName = localPlayer and localPlayer.DisplayName or "You",
				roundOutcomes = props.myRoundOutcomes or {},
				maxRounds = 5,
				dotsRevealed = dotsRevealed,
				hsvText = guessHSV,
				isWinner = myWon and not isTie,
				winnerGlow = winnerGlow,
				checkmarkScale = checkmarkScale,
				xPosition = 0,
				layoutOrder = 1,
			}),

			-- Center bar: Target color
			CenterBar = e("Frame", {
				Size = UDim2.fromOffset(248, centerBarHeight),
				Position = UDim2.new(0, 256, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = props.targetColor,
				BorderSizePixel = 0,
				ClipsDescendants = true,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 14) }),

				Content = e("Frame", {
					Size = UDim2.new(1, 0, 0, 560),
					Position = UDim2.new(0, 0, 1, 0),
					AnchorPoint = Vector2.new(0, 1),
					BackgroundTransparency = 1,
				}, {
					Padding = e("UIPadding", {
						PaddingTop = UDim.new(0, 20),
						PaddingBottom = UDim.new(0, 20),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),

					TargetLabel = StrokedText({
						Size = UDim2.new(1, 0, 0, 32),
						Position = UDim2.fromOffset(0, 0),
						BackgroundTransparency = 1,
						Text = "Target",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						TextTransparency = math.max(textAlpha, 0.4),
						TextSize = 24,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Center,
					}),

					HSV = StrokedText({
						Size = UDim2.new(1, 0, 0, 22),
						Position = UDim2.fromOffset(0, 36),
						BackgroundTransparency = 1,
						Text = targetHSV,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						TextTransparency = math.max(textAlpha, 0.15),
						TextSize = 18,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Center,
					}),

					WinnerText = StrokedText({
						Size = UDim2.new(1, 0, 0, 36),
						Position = UDim2.new(0, 0, 1, -36),
						BackgroundTransparency = 1,
						Text = winnerText,
						TextColor3 = if isTie then Color3.fromRGB(255, 255, 150)
							elseif myWon then Color3.fromRGB(100, 255, 100)
							else Color3.fromRGB(255, 130, 130),
						TextTransparency = if dotsRevealed then 0 else 1,
						TextSize = 24,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Center,
					}),
				}),
			}),

			-- Right bar: Opponent's guess
			RightBar = e(PlayerBar, {
				barColor = opColor,
				barHeight = rightBarT,
				contentAlpha = contentAlpha,
				animatedScore = animatedOppScore,
				userId = props.opponentUserId or 0,
				displayName = props.opponentName or "Opponent",
				roundOutcomes = props.opponentRoundOutcomes or {},
				maxRounds = 5,
				dotsRevealed = dotsRevealed,
				hsvText = oppHSV,
				isWinner = not myWon and not isTie,
				winnerGlow = winnerGlow,
				checkmarkScale = checkmarkScale,
				xPosition = 512,
				layoutOrder = 3,
			}),
		})
	end

	local scoreText = string.format("%.2f", animatedScore)

	-- Solo mode: original two-panel layout
	local roundLabel = ""
	if props.roundNumber and props.totalRounds then
		roundLabel = `{props.roundNumber}/{props.totalRounds}`
	end

	local NEUTRAL = Color3.fromRGB(60, 60, 60)
	local animatedGuess = NEUTRAL:Lerp(props.guessColor, topPanelT)
	local animatedTarget = NEUTRAL:Lerp(props.targetColor, bottomPanelT)

	-- Top panel slides down from above (y scale = -0.5 → 0)
	local topY = -0.5 * (1 - topPanelT)
	-- Bottom panel slides up from below (y scale = 1.0 → 0.5)
	local bottomY = 0.5 + 0.5 * (1 - bottomPanelT)

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, {
		TopHalf = e("Frame", {
			Size = UDim2.new(1, 0, 0.5, -2),
			Position = UDim2.new(0, 0, topY, 0),
			BackgroundColor3 = animatedGuess,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 16) }),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),
			RoundLabel = roundLabel ~= "" and StrokedText({
				Size = UDim2.fromOffset(100, 28),
				BackgroundTransparency = 1,
				Text = roundLabel,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.4,
				TextSize = 22,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			ScoreLabel = StrokedText({
				Size = UDim2.new(0.6, 0, 0, 80),
				Position = UDim2.new(1, 0, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = scoreText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 72,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			FlairText = StrokedText({
				Size = UDim2.new(0.6, 0, 0, 64),
				Position = UDim2.new(1, 0, 0, 86),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = flairText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.15,
				TextSize = 22,
				Font = Enum.Font.FredokaOne,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			SelectionLabel = StrokedText({
				Size = UDim2.new(1, 0, 0, 32),
				Position = UDim2.new(0, 0, 1, -68),
				BackgroundTransparency = 1,
				Text = "Your selection",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.5,
				TextSize = 28,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			SelectionHSV = StrokedText({
				Size = UDim2.new(1, 0, 0, 36),
				Position = UDim2.new(0, 0, 1, -36),
				BackgroundTransparency = 1,
				Text = guessHSV,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.15,
				TextSize = 34,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),

		BottomHalf = e("Frame", {
			Size = UDim2.new(1, 0, 0.5, -2),
			Position = UDim2.new(0, 0, bottomY, 2),
			BackgroundColor3 = animatedTarget,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 16) }),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),
			OriginalLabel = StrokedText({
				Size = UDim2.new(1, 0, 0, 32),
				Position = UDim2.new(0, 0, 1, -68),
				BackgroundTransparency = 1,
				Text = "Original",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.5,
				TextSize = 28,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			OriginalHSV = StrokedText({
				Size = UDim2.new(1, 0, 0, 36),
				Position = UDim2.new(0, 0, 1, -36),
				BackgroundTransparency = 1,
				Text = targetHSV,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.15,
				TextSize = 34,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			NextButton = props.onNext and e("TextButton", {
				Size = UDim2.fromOffset(56, 56),
				Position = UDim2.new(1, 0, 1, 0),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
				Text = utf8.char(0x2192),
				TextColor3 = Color3.fromRGB(30, 30, 30),
				TextSize = 28,
				Font = Enum.Font.FredokaOne,
				ZIndex = 5,
				[React.Event.Activated] = props.onNext,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),
		}),
	})
end

return RevealScreen
