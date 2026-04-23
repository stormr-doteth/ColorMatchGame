local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local ColorDisplay = require(script.Parent.components.ColorDisplay)
local ColorPicker = require(script.Parent.components.ColorPicker)
local MatchScoreScreen = require(script.Parent.components.MatchScoreScreen)
local RevealScreen = require(script.Parent.components.RevealScreen)
local HistoryGrid = require(script.Parent.components.HistoryGrid)
local WaitingScreen = require(script.Parent.components.WaitingScreen)

local e = React.createElement

-- Helper: TextLabel with black UIStroke for readability on colored backgrounds
local function StrokedText(props, children)
	local merged = {}
	for k, v in props do
		merged[k] = v
	end
	-- Default font
	if not merged.Font then
		merged.Font = Enum.Font.FredokaOne
	end
	-- Default white text
	if not merged.TextColor3 then
		merged.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	-- Match stroke transparency to text transparency
	local strokeTransparency = math.max(merged.TextTransparency or 0, 0.3)

	local allChildren = {
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(0, 0, 0),
			Thickness = 2,
			Transparency = strokeTransparency,
		}),
	}
	if children then
		for k, v in children do
			allChildren[k] = v
		end
	end

	return e("TextLabel", merged, allChildren)
end

-- Reference resolution for UIScale (mobile-friendly: smaller ref = larger scale on phones)
-- Extra headroom in REF_HEIGHT leaves room for the Roblox top bar / phone safe insets.
local REF_WIDTH = 1280
local REF_HEIGHT = 900

-- Flair line shown above the round cards on the solo end screen, picked from
-- the tier matching the player's total score (out of totalRounds * 100).
local END_FLAIR = {
	{ min = 0.90, lines = {
		"Eagle eye! Are you a designer?",
		"Suspiciously photographic.",
		"You weren't supposed to do that well.",
	}},
	{ min = 0.75, lines = {
		"Sharp memory.",
		"Color theory degree?",
		"Your eyes are working overtime.",
	}},
	{ min = 0.60, lines = {
		"Solid run.",
		"Better than most.",
		"You held it together.",
	}},
	{ min = 0.40, lines = {
		"Decent eye.",
		"Middle of the pack.",
		"Not bad, not great.",
	}},
	{ min = 0.20, lines = {
		"Room to grow.",
		"Your memory wandered off.",
		"The colors got away from you.",
	}},
	{ min = 0.0, lines = {
		"...practice makes perfect.",
		"Have you considered glasses?",
		"Your monitor is fine. It's you.",
	}},
}

local function pickEndFlair(total: number, max: number): string
	local pct = if max > 0 then total / max else 0
	for _, tier in END_FLAIR do
		if pct >= tier.min then
			return tier.lines[math.random(1, #tier.lines)]
		end
	end
	return ""
end

-- Diamond-split round card. Top-left triangle = target, bottom-right = guess,
-- with the round score overlaid in the top-left corner. Reusable across the
-- solo end screen and both player rows of the 1v1 end screen. When `wonRound`
-- is true, the card gets a thick gold border so wins are obvious at a glance.
local function DiamondCard(props: {
	targetColor: Color3,
	guessColor: Color3,
	score: number,
	size: number?,
	wonRound: boolean?,
	layoutOrder: number,
})
	local size = props.size or 110
	local scoreSize = if size >= 100 then 26 else 22
	local strokeColor = if props.wonRound
		then Color3.fromRGB(255, 215, 0)
		else Color3.fromRGB(255, 255, 255)
	local strokeThickness = if props.wonRound then 3 else 1
	local strokeTransparency = if props.wonRound then 0 else 0.7

	return e("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 12) }),
		Stroke = e("UIStroke", {
			Color = strokeColor,
			Thickness = strokeThickness,
			Transparency = strokeTransparency,
		}),
		Gradient = e("UIGradient", {
			Rotation = 45,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, props.targetColor),
				ColorSequenceKeypoint.new(0.499, props.targetColor),
				ColorSequenceKeypoint.new(0.501, props.guessColor),
				ColorSequenceKeypoint.new(1, props.guessColor),
			}),
		}),
		Score = StrokedText({
			Size = UDim2.fromOffset(80, 30),
			Position = UDim2.fromOffset(10, 6),
			BackgroundTransparency = 1,
			Text = tostring(props.score or 0),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = scoreSize,
			Font = Enum.Font.FredokaOne,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
	})
end

-- Compact player info bar for persistent display during rounds (1v1 only)
-- Compact 5-slot dot row for the persistent header bar
local function HeaderDots(props: { roundOutcomes: { string }, LayoutOrder: number? })
	local maxRounds = 5
	local dots: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}
	for i = 1, maxRounds do
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
			children.X = e("ImageLabel", {
				Size = UDim2.fromScale(0.8, 0.8),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = "rbxassetid://106881959484548",
				ScaleType = Enum.ScaleType.Fit,
			})
		end
		dots["Dot" .. i] = e("Frame", {
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, children)
	end
	return e("Frame", {
		Size = UDim2.fromOffset(maxRounds * 26 + 4 * 6, 28),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, dots)
end

local function PlayerInfoBar(props: {
	myUserId: number,
	myName: string,
	myRoundOutcomes: { string },
	opponentUserId: number,
	opponentName: string,
	opponentRoundOutcomes: { string },
	slideProgress: number, -- 0 = hidden above, 1 = fully visible
})
	local yOffset = (1 - props.slideProgress) * -84

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 72),
		Position = UDim2.fromOffset(0, yOffset),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 12) }),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
		}),

		-- Left side: my info
		MyInfo = e("Frame", {
			Size = UDim2.new(0.45, 0, 1, 0),
			Position = UDim2.fromScale(0, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
			}),
			Avatar = e("ImageLabel", {
				Size = UDim2.fromOffset(48, 48),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 0,
				Image = if props.myUserId > 0
					then `rbxthumb://type=AvatarHeadShot&id={props.myUserId}&w=150&h=150`
					else "",
				LayoutOrder = 1,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(255, 255, 255),
					Thickness = 2,
					Transparency = 0.3,
				}),
			}),
			Name = StrokedText({
				Size = UDim2.fromOffset(120, 24),
				BackgroundTransparency = 1,
				Text = props.myName,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 22,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
			Dots = e(HeaderDots, {
				roundOutcomes = props.myRoundOutcomes,
				LayoutOrder = 3,
			}),
		}),

		-- "VS" center text
		VS = StrokedText({
			Size = UDim2.new(0.1, 0, 1, 0),
			Position = UDim2.fromScale(0.45, 0),
			BackgroundTransparency = 1,
			Text = "VS",
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextTransparency = 0.3,
			TextSize = 20,
			Font = Enum.Font.FredokaOne,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),

		-- Right side: opponent info (right-aligned)
		OppInfo = e("Frame", {
			Size = UDim2.new(0.45, 0, 1, 0),
			Position = UDim2.fromScale(0.55, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 10),
			}),
			Dots = e(HeaderDots, {
				roundOutcomes = props.opponentRoundOutcomes,
				LayoutOrder = 1,
			}),
			Name = StrokedText({
				Size = UDim2.fromOffset(120, 24),
				BackgroundTransparency = 1,
				Text = props.opponentName,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 22,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
			Avatar = e("ImageLabel", {
				Size = UDim2.fromOffset(48, 48),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 0,
				Image = if props.opponentUserId > 0
					then `rbxthumb://type=AvatarHeadShot&id={props.opponentUserId}&w=150&h=150`
					else "",
				LayoutOrder = 3,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(255, 255, 255),
					Thickness = 2,
					Transparency = 0.3,
				}),
			}),
		}),
	})
end

local function GameController()
	-- UI scale
	local uiScale, setUIScale = React.useState(1)
	local dismissScale, setDismissScale = React.useState(1)
	local closing, setClosing = React.useState(false)

	-- Match state
	local phase, setPhase = React.useState("idle") -- idle|seated|waiting|showing|guessing|submitted|roundResult|matchEnd
	-- Track whether the last input was a gamepad so we can conditionally show
	-- controller-only hint pills (e.g., "Ⓑ Leave" next to LEAVE TABLE).
	local isGamepad, setIsGamepad = React.useState(
		UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	)
	React.useEffect(function()
		local conn = UserInputService.LastInputTypeChanged:Connect(function(t)
			setIsGamepad(t == Enum.UserInputType.Gamepad1)
		end)
		return function() conn:Disconnect() end
	end, {})
	local opponentName, setOpponentName = React.useState("")
	local roundsToWin, setRoundsToWin = React.useState(3)
	local seatedPlayerCount, setSeatedPlayerCount = React.useState(0)
	local isSolo, setIsSolo = React.useState(false)
	local soloRoundNumber, setSoloRoundNumber = React.useState(0)
	local soloTotalRounds, setSoloTotalRounds = React.useState(5)
	local soloAverage, setSoloAverage = React.useState(0)
	local soloBest, setSoloBest = React.useState(0)

	-- Round state
	local targetH, setTargetH = React.useState(0)
	local targetS, setTargetS = React.useState(0)
	local targetV, setTargetV = React.useState(0)
	local guessH, setGuessH = React.useState(0.5)
	local guessS, setGuessS = React.useState(0.5)
	local guessV, setGuessV = React.useState(0.5)
	local timeLeft, setTimeLeft = React.useState(5)

	-- Result state
	local myScore, setMyScore = React.useState(0)
	local opponentScore, setOpponentScore = React.useState(0)
	local myWins, setMyWins = React.useState(0)
	local opponentWins, setOpponentWins = React.useState(0)
	local opponentGuessColor, setOpponentGuessColor = React.useState(Color3.new(0.5, 0.5, 0.5))
	local myUserId, setMyUserId = React.useState(0)
	local opponentUserId, setOpponentUserId = React.useState(0)

	-- Match end state
	local matchWon, setMatchWon = React.useState(false)
	local matchAbandoned, setMatchAbandoned = React.useState(false)
	local cashEarned, setCashEarned = React.useState(0)
	local cashMultiplier, setCashMultiplier = React.useState(1)
	local winsAwarded, setWinsAwarded = React.useState(1)
	local roundHistory, setRoundHistory = React.useState({})
	local myRoundOutcomes, setMyRoundOutcomes = React.useState({})
	-- Flair line on the solo end screen, picked once per match (in the MatchEnd handler)
	local endFlairText, setEndFlairText = React.useState("")

	-- Countdown state ("Ready", "Set", "GO!")
	local countdownText, setCountdownText = React.useState("")
	local countdownFade, setCountdownFade = React.useState(0) -- 0=visible, 1=transparent

	-- Store guess color at submit time for the result screen
	local submittedColor, setSubmittedColor = React.useState(Color3.new(0.5, 0.5, 0.5))

	-- Hint developer product state
	local hintActive, setHintActive = React.useState(false)
	local hintPopScale, setHintPopScale = React.useState(0) -- 0=hidden, 1=settled

	-- Player info bar slide animation (1v1 only)
	local infoBarSlide, setInfoBarSlide = React.useState(0)
	local prevPhaseRef = React.useRef("idle")

	-- Pop-close animation: scale up slightly then shrink to 0
	local handleClose = React.useCallback(function()
		if closing then return end
		setClosing(true)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			local leave = remotes:FindFirstChild("LeaveTable")
			if leave then
				leave:FireServer()
			end
		end
		local ok, ShopButtonsHider = pcall(function()
			return require(Players.LocalPlayer.PlayerScripts:WaitForChild("Client"):WaitForChild("ShopButtonsHider"))
		end)
		if ok and ShopButtonsHider then
			ShopButtonsHider.Show()
		end
		local okBlur, MatchBlur = pcall(function()
			return require(Players.LocalPlayer.PlayerScripts:WaitForChild("Client"):WaitForChild("MatchBlur"))
		end)
		if okBlur and MatchBlur then
			MatchBlur.Clear()
		end
	end, { closing })

	React.useEffect(function()
		if not closing then return end
		local cancelled = false
		task.spawn(function()
			-- Pop out: scale up slightly
			local popDuration = 0.1
			local shrinkDuration = 0.2
			local startTime = os.clock()
			while not cancelled do
				local elapsed = os.clock() - startTime
				if elapsed < popDuration then
					-- Ease out to 1.08
					local t = elapsed / popDuration
					setDismissScale(1 + 0.08 * t)
				elseif elapsed < popDuration + shrinkDuration then
					-- Shrink from 1.08 to 0 with ease-in
					local t = (elapsed - popDuration) / shrinkDuration
					local eased = t * t -- ease-in (accelerate)
					setDismissScale(1.08 * (1 - eased))
				else
					break
				end
				task.wait()
			end
			if not cancelled then
				setDismissScale(1)
				setClosing(false)
				setPhase("idle")
			end
		end)
		return function()
			cancelled = true
			setDismissScale(1)
			setClosing(false)
		end
	end, { closing })

	-- Viewport scale tracking
	React.useEffect(function()
		local camera = workspace.CurrentCamera
		local function updateScale()
			local viewport = camera.ViewportSize
			local scaleX = viewport.X / REF_WIDTH
			local scaleY = viewport.Y / REF_HEIGHT
			setUIScale(math.clamp(math.min(scaleX, scaleY) * 1.2, 0.5, 1.5))
		end
		updateScale()
		local conn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		return function()
			conn:Disconnect()
		end
	end, {})

	-- Hint attribute listener (bridge from imperative HintShop to React)
	React.useEffect(function()
		local player = Players.LocalPlayer
		local function sync()
			setHintActive(player:GetAttribute("HintActive") == true)
		end
		sync()
		local conn = player:GetAttributeChangedSignal("HintActive"):Connect(sync)
		return function()
			conn:Disconnect()
		end
	end, {})

	-- Match Color: snap sliders to target color when activated
	React.useEffect(function()
		local player = Players.LocalPlayer
		local conn = player:GetAttributeChangedSignal("MatchColorActive"):Connect(function()
			if player:GetAttribute("MatchColorActive") == true then
				setGuessH(targetH)
				setGuessS(targetS)
				setGuessV(targetV)
			end
		end)
		return function()
			conn:Disconnect()
		end
	end, { targetH, targetS, targetV })

	-- Auto-focus the hue slider when entering guessing phase so controller
	-- users don't have to hunt for the picker with D-pad up + right.
	React.useEffect(function()
		if phase ~= "guessing" then return end
		local player = Players.LocalPlayer
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if not pg then return end
		local cancelled = false
		-- Defer one frame so the picker is parented before we search.
		task.delay(0.05, function()
			if cancelled then return end
			local hue = pg:FindFirstChild("HueStrip", true)
			if hue and hue:IsA("GuiObject") then
				GuiService.SelectedObject = hue
			end
		end)
		return function() cancelled = true end
	end, { phase })

	-- ButtonB leaves the table during any in-match phase. Falls through when
	-- idle so the global UIManager bind (which closes open panels) still works.
	React.useEffect(function()
		local inMatch = phase == "seated" or phase == "waiting" or phase == "countdown"
			or phase == "soloIntro" or phase == "showing" or phase == "guessing"
			or phase == "submitted" or phase == "roundResult" or phase == "matchEnd"
		if not inMatch then return end
		ContextActionService:BindAction("GameController_LeaveTable", function(_, state)
			if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
			handleClose()
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB)
		return function()
			ContextActionService:UnbindAction("GameController_LeaveTable")
		end
	end, { phase, handleClose })

	-- Send guess preview to server so table papers update in real time
	React.useEffect(function()
		if phase == "guessing" or phase == "submitted" then
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				local preview = remotes:FindFirstChild("GuessPreview")
				if preview then
					preview:FireServer({ h = guessH, s = guessS, v = guessV })
				end
			end
		end
	end, { guessH, guessS, guessV, phase })

	-- Hint pop-in animation: overshoot then settle
	React.useEffect(function()
		if not hintActive then
			setHintPopScale(0)
			return
		end
		-- Animate: 0 → 1.2 → 1.0 over 0.35s
		local running = true
		setHintPopScale(0)
		task.spawn(function()
			local start = tick()
			local duration = 0.35
			while running do
				local t = math.clamp((tick() - start) / duration, 0, 1)
				-- Elastic overshoot: rises to ~1.2 then settles to 1.0
				local scale
				if t < 0.6 then
					-- Ease out to overshoot (0 → 1.2)
					local p = t / 0.6
					scale = 1.2 * (1 - (1 - p) * (1 - p))
				else
					-- Settle back (1.2 → 1.0)
					local p = (t - 0.6) / 0.4
					scale = 1.2 - 0.2 * p
				end
				setHintPopScale(scale)
				if t >= 1 then break end
				task.wait()
			end
			if running then
				setHintPopScale(1)
			end
		end)
		return function()
			running = false
		end
	end, { hintActive })

	-- Connect to server RemoteEvents
	React.useEffect(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local connections = {}

		table.insert(connections, remotes:WaitForChild("PlayerSeated").OnClientEvent:Connect(function(data)
			setSeatedPlayerCount(data.playerCount)
			setIsSolo(data.solo or false)
			setPhase("seated")
		end))

		table.insert(connections, remotes:WaitForChild("MatchStart").OnClientEvent:Connect(function(data)
			setOpponentName(data.opponentName or "")
			setRoundsToWin(data.roundsToWin)
			setIsSolo(data.solo or false)
			setSoloTotalRounds(data.totalRounds or data.roundsToWin)
			setMyWins(0)
			setOpponentWins(0)
			setMyRoundOutcomes({})
			setRoundHistory({})
			setMatchAbandoned(false)
			if data.solo then
				-- Solo: show the intro screen; player clicks "Play Now" to begin
				setPhase("soloIntro")
			else
				-- 1v1: play the same Ready/Set/GO countdown solo uses, then
				-- transition into the first round.
				setPhase("countdown")
			end
		end))

		table.insert(connections, remotes:WaitForChild("RoundShowColor").OnClientEvent:Connect(function(data)
			setTargetH(data.h)
			setTargetS(data.s)
			setTargetV(data.v)
			setTimeLeft(data.duration)
			setGuessH(math.random())
			setGuessS(math.random())
			setGuessV(math.random())
			setSoloRoundNumber(data.roundNumber or 0)
			-- If we're mid-countdown (solo), the color was sent early so the
			-- "GO!" overlay can render over it. Stay in countdown until the
			-- countdown effect finishes and signals BeginRound.
			setPhase(function(currentPhase)
				if currentPhase == "countdown" then
					return currentPhase
				end
				return "showing"
			end)
		end))

		table.insert(connections, remotes:WaitForChild("RoundGuessPhase").OnClientEvent:Connect(function()
			setPhase("guessing")
		end))

		table.insert(connections, remotes:WaitForChild("RoundResult").OnClientEvent:Connect(function(data)
			setMyScore(data.myScore)
			setOpponentScore(data.opponentScore or 0)
			setMyWins(data.myTotalWins)
			setOpponentWins(data.opponentTotalWins or 0)
			setTargetH(data.targetH)
			setTargetS(data.targetS)
			setTargetV(data.targetV)
			if data.opponentGuessH then
				setOpponentGuessColor(Color3.fromHSV(data.opponentGuessH, data.opponentGuessS, data.opponentGuessV))
			end
			if data.myUserId then
				setMyUserId(data.myUserId)
				setOpponentUserId(data.opponentUserId)
			end
			if data.solo then
				setSoloRoundNumber(data.roundNumber or 0)
				setSoloTotalRounds(data.totalRounds or 5)
			end
			-- Append per-round outcome (1v1 only — solo rounds aren't win/loss)
			if not data.solo then
				local outcome
				if data.myScore > (data.opponentScore or 0) then
					outcome = "win"
				elseif (data.opponentScore or 0) > data.myScore then
					outcome = "loss"
				else
					outcome = "tie"
				end
				setMyRoundOutcomes(function(prev)
					local next = table.clone(prev)
					table.insert(next, outcome)
					return next
				end)
			end
			setPhase("roundResult")
		end))

		table.insert(connections, remotes:WaitForChild("MatchEnd").OnClientEvent:Connect(function(data)
			setMatchWon(data.won)
			setMatchAbandoned(data.abandoned == true)
			setCashEarned(data.cashEarned or 0)
			setCashMultiplier(data.cashMultiplier or 1)
			setWinsAwarded(data.winsAwarded or 1)
			-- Solo: dismissed by Done/Play Again buttons. 1v1: also no auto-dismiss.
			if data.solo then
				setSoloAverage(data.averageScore or 0)
				setSoloBest(data.bestScore or 0)
				-- Pick the end-screen flair line once, here, so it stays stable while
				-- the matchEnd screen is open.
				local history = data.roundHistory or {}
				local total = 0
				for _, entry in history do
					total += (entry.myScore or 0)
				end
				local maxScore = #history * 100
				if maxScore <= 0 then
					maxScore = (data.totalRounds or 5) * 100
				end
				setEndFlairText(pickEndFlair(total, maxScore))
			end
			setRoundHistory(data.roundHistory or {})
			setPhase("matchEnd")
		end))

		return function()
			for _, conn in connections do
				conn:Disconnect()
			end
		end
	end, {})

	-- Smooth countdown timer during showing phase (updates every frame)
	local smoothTime, setSmoothTime = React.useState(5.0)
	-- Odometer: track previous seconds value and slide animation
	local prevSecondsRef = React.useRef(-1)
	local secondsSlide, setSecondsSlide = React.useState(1) -- 0=animating, 1=settled
	local prevSecondsText, setPrevSecondsText = React.useState("")
	-- Transition progress: 0 = timer visible, 1 = picker fully slid in
	local transitionProgress, setTransitionProgress = React.useState(0)
	-- Text fade: 0 = fully visible, 1 = fully transparent
	local textFade, setTextFade = React.useState(0)
	-- Picker slide-away after solo submit: 0 = picker in place, 1 = fully off-screen left
	local submittedAnim, setSubmittedAnim = React.useState(0)

	-- Guess phase countdown (seconds remaining to submit)
	local guessTimeLeft, setGuessTimeLeft = React.useState(Constants.GUESS_TIMEOUT)
	local guessStartTimeRef = React.useRef(0)
	local onSubmitRef = React.useRef(nil :: any)

	-- Odometer animation: trigger when whole seconds changes
	local currentWholeSeconds = math.floor(smoothTime)
	React.useEffect(function()
		if prevSecondsRef.current == -1 then
			-- First render, no animation
			prevSecondsRef.current = currentWholeSeconds
			setSecondsSlide(1)
			return
		end
		if currentWholeSeconds == prevSecondsRef.current then
			return
		end
		-- Seconds changed — animate
		setPrevSecondsText(tostring(prevSecondsRef.current))
		prevSecondsRef.current = currentWholeSeconds
		setSecondsSlide(0)
		local running = true
		task.spawn(function()
			local start = tick()
			while running do
				local t = math.clamp((tick() - start) / 0.25, 0, 1)
				-- Ease out quad
				local eased = 1 - (1 - t) * (1 - t)
				setSecondsSlide(eased)
				if t >= 1 then break end
				task.wait()
			end
		end)
		return function()
			running = false
		end
	end, { currentWholeSeconds })

	React.useEffect(function()
		if phase ~= "showing" and phase ~= "guessing" then
			-- During the solo post-submit slide-out we keep the picker visually
			-- in place (transitionProgress=1, textFade=1) so submittedAnim alone
			-- drives the leftward exit.
			if isSolo and (phase == "submitted" or phase == "roundResult") then
				setTransitionProgress(1)
				setTextFade(1)
				return
			end
			setTransitionProgress(0)
			setTextFade(0)
			return
		end

		if phase == "showing" then
			setTransitionProgress(0)
			setTextFade(0)
			local running = true
			local startTime = tick()
			local duration = timeLeft
			setSmoothTime(duration)
			task.spawn(function()
				while running do
					local elapsed = tick() - startTime
					local remaining = math.max(0, duration - elapsed)
					setSmoothTime(remaining)
					if remaining <= 0 then
						break
					end
					task.wait()
				end
			end)
			return function()
				running = false
			end
		end

		if phase == "guessing" then
			-- Animate: fade out timer text, then slide in picker
			local running = true
			guessStartTimeRef.current = tick()
			setGuessTimeLeft(Constants.GUESS_TIMEOUT)
			task.spawn(function()
				-- Phase 1: Fade out text (0.3s)
				local fadeStart = tick()
				while running do
					local t = math.clamp((tick() - fadeStart) / 0.3, 0, 1)
					setTextFade(t)
					if t >= 1 then break end
					task.wait()
				end
				if not running then return end
				-- Phase 2: Slide in picker (0.4s)
				local slideStart = tick()
				while running do
					local t = math.clamp((tick() - slideStart) / 0.4, 0, 1)
					-- Ease out quad
					local eased = 1 - (1 - t) * (1 - t)
					setTransitionProgress(eased)
					if t >= 1 then break end
					task.wait()
				end
			end)
			return function()
				running = false
			end
		end

		return nil
	end, { phase })

	-- Solo post-submit picker slide-away animation. When the player submits,
	-- the color picker glides off-screen left before the reveal panels appear.
	-- We don't return a cleanup so the animation always plays through, even
	-- after the server fires roundResult and phase changes.
	React.useEffect(function()
		if not isSolo then
			return
		end
		if phase == "showing" or phase == "guessing" then
			setSubmittedAnim(0)
			return
		end
		if phase == "submitted" then
			task.spawn(function()
				local start = tick()
				while true do
					local t = math.clamp((tick() - start) / 0.45, 0, 1)
					local eased = 1 - (1 - t) * (1 - t)
					setSubmittedAnim(eased)
					if t >= 1 then break end
					task.wait()
				end
			end)
		end
		return nil
	end, { phase, isSolo })

	-- Guess countdown — runs through both guessing and submitted phases so the
	-- player can still see the deadline while waiting on their opponent.
	-- Auto-submits if the player hasn't submitted yet when it hits 0.
	React.useEffect(function()
		if phase ~= "guessing" and phase ~= "submitted" then
			return
		end
		local running = true
		task.spawn(function()
			local duration = Constants.GUESS_TIMEOUT
			while running do
				local remaining = math.max(0, duration - (tick() - guessStartTimeRef.current))
				setGuessTimeLeft(remaining)
				if remaining <= 0 then
					if phase == "guessing" and onSubmitRef.current then
						onSubmitRef.current()
					end
					break
				end
				task.wait()
			end
		end)
		return function()
			running = false
		end
	end, { phase })

	-- Use refs for guess values so onSubmit always reads the latest
	local guessHRef = React.useRef(guessH)
	local guessSRef = React.useRef(guessS)
	local guessVRef = React.useRef(guessV)
	guessHRef.current = guessH
	guessSRef.current = guessS
	guessVRef.current = guessV

	local function onSubmit()
		if phase ~= "guessing" then
			return
		end
		local h, s, v = guessHRef.current, guessSRef.current, guessVRef.current
		setSubmittedColor(Color3.fromHSV(h, s, v))
		setPhase("submitted")
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			remotes.SubmitGuess:FireServer({ h = h, s = s, v = v })
		end
	end
	onSubmitRef.current = onSubmit

	local function onNextRound()
		-- Last round in solo mode: skip the "Ready/Set/Go" ceremony — there's
		-- no next color to show, the server will reply with MatchEnd. Fire
		-- NextRound directly so the player goes straight to the results screen.
		if isSolo and soloRoundNumber >= soloTotalRounds then
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				remotes.NextRound:FireServer()
			end
			return
		end
		-- Otherwise: play the countdown — server gets notified at the end
		setPhase("countdown")
	end

	-- Countdown "Ready, Set, GO!" animation. Used in two places:
	--  • Solo: between rounds. We fire NextRound at the START so the server's
	--    RoundShowColor arrives during Ready/Set; the GO! frame renders the
	--    actual color. After GO! we fire BeginRound and switch to showing.
	--  • 1v1: at the very start of the match (after MatchStart). The server
	--    has already fired RoundShowColor for round 1 and is waiting for
	--    BeginRound from BOTH players, so we don't fire NextRound here —
	--    just play the animation, then fire BeginRound and switch to showing.
	React.useEffect(function()
		if phase ~= "countdown" then
			return
		end
		local running = true
		setCountdownFade(0)
		setCountdownText("")

		-- Solo only: ask the server to start preparing the next round.
		-- 1v1 already has RoundShowColor on the way (server fired it at match start).
		if isSolo then
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				remotes.NextRound:FireServer()
			end
		end

		task.spawn(function()
			-- Fade in
			local fadeStart = tick()
			while running do
				local t = math.clamp((tick() - fadeStart) / 0.4, 0, 1)
				setCountdownFade(t)
				if t >= 1 then break end
				task.wait()
			end
			if not running then return end

			-- "Ready"
			setCountdownText("Ready")
			task.wait(0.7)
			if not running then return end

			-- "Set"
			setCountdownText("Set")
			task.wait(0.7)
			if not running then return end

			-- "GO!"
			setCountdownText("GO!")
			task.wait(0.35)
			if not running then return end

			-- Tell the server to start the show-duration timer and switch
			-- locally into the showing phase. The color is already on screen.
			local r = ReplicatedStorage:FindFirstChild("Remotes")
			if r then
				local begin = r:FindFirstChild("BeginRound")
				if begin then
					begin:FireServer()
				end
			end
			setCountdownText("")
			setPhase("showing")
		end)
		return function()
			running = false
		end
	end, { phase })

	-- Player info bar slide-in animation for 1v1 gameplay phases
	-- Only animate when entering gameplay from a non-gameplay phase (e.g. roundResult → showing)
	local GAMEPLAY_PHASES = { showing = true, guessing = true, submitted = true }
	React.useEffect(function()
		local isGameplay = not isSolo and GAMEPLAY_PHASES[phase]
		local wasGameplay = GAMEPLAY_PHASES[prevPhaseRef.current]
		prevPhaseRef.current = phase

		if not isGameplay then
			setInfoBarSlide(0)
			return
		end

		-- Already in a gameplay phase → keep bar visible, no re-animation
		if wasGameplay then
			setInfoBarSlide(1)
			return
		end

		-- Entering gameplay from non-gameplay → slide in
		local running = true
		task.spawn(function()
			local start = tick()
			while running do
				local t = math.clamp((tick() - start) / 0.4, 0, 1)
				local eased = 1 - (1 - t) * (1 - t)
				setInfoBarSlide(eased)
				if t >= 1 then break end
				task.wait()
			end
		end)
		return function()
			running = false
		end
	end, { phase, isSolo })

	-- Hide the Studio-made SubmitButton — replaced by an in-frame React button below.
	React.useEffect(function()
		local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local screenGui = playerGui and playerGui:FindFirstChild("ScreenGui")
		local btn = screenGui and screenGui:FindFirstChild("SubmitButton")
		if btn then
			btn.Visible = false
		end
	end, {})

	local targetColor = Color3.fromHSV(targetH, targetS, targetV)
	local guessColor = Color3.fromHSV(guessH, guessS, guessV)

	-- Render phase content
	local content

	if phase == "idle" then
		-- Nothing visible — player should walk to a table
		return nil
	elseif phase == "countdown" then
		-- "Ready / Set" overlay sits on the dark game frame. When "GO!" hits,
		-- the target color (already received from the server) becomes the
		-- background so it matches the showing-phase backdrop the player will
		-- be memorizing.
		local goLive = countdownText == "GO!"
		content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = targetColor,
			BackgroundTransparency = if goLive then 0 else 1,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),

			Text = countdownText ~= "" and StrokedText({
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = countdownText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.15,
				TextSize = if countdownText == "GO!" then 80 else 60,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
			}),
		})
	elseif phase == "seated" then
		-- Minimal top-anchored UI so the player can still see the world (and
		-- their chair) while waiting for an opponent. No dark backdrop — this
		-- phase short-circuits the wrapper below.
		if isSolo then
			content = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 16),
				}),
				Title = StrokedText({
					Size = UDim2.fromOffset(500, 56),
					BackgroundTransparency = 1,
					Text = "Solo Practice",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 44,
					Font = Enum.Font.FredokaOne,
					LayoutOrder = 1,
				}),
				Sub = StrokedText({
					Size = UDim2.fromOffset(500, 36),
					BackgroundTransparency = 1,
					Text = "Starting...",
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextSize = 24,
					Font = Enum.Font.FredokaOne,
					LayoutOrder = 2,
				}),
			})
		else
			content = e("Frame", {
				Size = UDim2.fromOffset(520, 140),
				Position = UDim2.new(0.5, 0, 0, 24),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 14) }),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(255, 255, 255),
					Thickness = 1.5,
					Transparency = 0.7,
				}),
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, 14),
					PaddingBottom = UDim.new(0, 14),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					Padding = UDim.new(0, 10),
				}),

				Waiting = StrokedText({
					Size = UDim2.fromOffset(600, 50),
					BackgroundTransparency = 1,
					Text = "Waiting for opponent...",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 36,
					Font = Enum.Font.FredokaOne,
					LayoutOrder = 1,
				}),

				Buttons = e("Frame", {
					Size = UDim2.fromOffset(440, 48),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					Row = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 12),
					}),

					InviteFriends = e("TextButton", {
						Size = UDim2.fromOffset(210, 46),
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 0.05,
						BorderSizePixel = 0,
						AutoButtonColor = true,
						Text = "",
						LayoutOrder = 1,
						[React.Event.Activated] = function()
							local localPlayer = Players.LocalPlayer
							if not localPlayer then return end
							pcall(function()
								SocialService:PromptGameInvite(localPlayer)
							end)
						end,
					}, {
						Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
						Stroke = e("UIStroke", {
							Color = Color3.fromRGB(0, 0, 0),
							Thickness = 2,
							Transparency = 0.4,
						}),
						Label = e("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = "INVITE FRIENDS",
							TextColor3 = Color3.fromRGB(30, 30, 30),
							TextSize = 20,
							Font = Enum.Font.FredokaOne,
							TextXAlignment = Enum.TextXAlignment.Center,
							TextYAlignment = Enum.TextYAlignment.Center,
						}),
					}),

					LeaveTable = e("TextButton", {
						Size = UDim2.fromOffset(180, 46),
						BackgroundColor3 = Color3.fromRGB(28, 28, 28),
						BackgroundTransparency = 0.2,
						BorderSizePixel = 0,
						AutoButtonColor = true,
						Text = "",
						LayoutOrder = 2,
						[React.Event.Activated] = handleClose,
					}, {
						Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
						Stroke = e("UIStroke", {
							Color = Color3.fromRGB(255, 255, 255),
							Thickness = 2,
							Transparency = 0.5,
						}),
						Hint = isGamepad and e("TextLabel", {
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.new(1, 10, 0.5, 0),
							Size = UDim2.fromOffset(130, 30),
							BackgroundTransparency = 1,
							Text = "Ⓑ Leave",
							TextColor3 = Color3.fromRGB(255, 255, 255),
							Font = Enum.Font.FredokaOne,
							TextScaled = true,
							TextXAlignment = Enum.TextXAlignment.Left,
						}) or nil,
						Label = e("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = "LEAVE TABLE",
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextSize = 18,
							Font = Enum.Font.FredokaOne,
							TextXAlignment = Enum.TextXAlignment.Center,
							TextYAlignment = Enum.TextYAlignment.Center,
						}),
					}),
				}),
			})
		end
	elseif phase == "soloIntro" then
		content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 60),
				PaddingBottom = UDim.new(0, 60),
				PaddingLeft = UDim.new(0, 64),
				PaddingRight = UDim.new(0, 64),
			}),

			Title = StrokedText({
				Size = UDim2.new(1, 0, 0, 88),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = "Remember the Color.",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 64,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

			Subtitle = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 200),
				Position = UDim2.fromOffset(0, 110),
				BackgroundTransparency = 1,
				Text = "It's nearly impossible to recall an exact color. This is a simple test to see how good you are at it.\n\nWe'll show you 5 colors, one at a time. Then you'll try to recreate them.",
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextSize = 24,
				Font = Enum.Font.FredokaOne,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

			PlayButton = e("TextButton", {
				Size = UDim2.fromOffset(260, 76),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = true,
				[React.Event.Activated] = function()
					if phase ~= "soloIntro" then
						return
					end
					setPhase("countdown")
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 16) }),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(0, 0, 0),
					Thickness = 2,
					Transparency = 0.4,
				}),
				Label = e("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "Play Now",
					TextColor3 = Color3.fromRGB(30, 30, 30),
					TextSize = 36,
					Font = Enum.Font.FredokaOne,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),
			}),
		})
	elseif phase == "waiting" then
		content = e(WaitingScreen, {
			opponentName = opponentName,
		})
	elseif phase == "showing" or phase == "guessing"
		or (isSolo and phase == "submitted")
		or (isSolo and phase == "roundResult" and submittedAnim < 1) then
		-- Unified showing → guessing → solo-slide-out view
		-- During showing: full color frame with timer countdown
		-- During guessing: timer fades out, picker slides in from left, preview is the guess color
		-- During solo submitted / early roundResult: picker slides out to the left

		local wholeSeconds = math.floor(smoothTime)
		local millis = math.floor((smoothTime - wholeSeconds) * 100)
		local secondsText = tostring(wholeSeconds)
		local millisText = string.format("%02d", millis)

		local roundLabel = ""
		if isSolo and soloRoundNumber > 0 then
			roundLabel = `{soloRoundNumber}/{soloTotalRounds}`
		end

		-- Background color: target during showing, transitions to guess color as picker appears
		local bgColor = if phase == "showing" then targetColor else guessColor

		-- Picker slides in from off-screen left during guessing entry, then
		-- slides back out to the left when the player submits (submittedAnim).
		-- SAFETY: once we're actually in the guessing phase the picker MUST be
		-- on-screen, even if the slide-in animation never completed (we've seen
		-- mobile clients where transitionProgress got stuck at 0 and the sliders
		-- rendered invisible off the left edge for the whole round). Clamp the
		-- negative slide-in contribution to 0 during guessing/submitted so the
		-- picker at worst pops in instead of never appearing.
		local slideInOffset = (1 - transitionProgress) * -220
		if phase == "guessing" or phase == "submitted" then
			slideInOffset = 0
		end
		local pickerOffset = slideInOffset - submittedAnim * 220

		-- Timer text transparency increases during fade
		local timerTextAlpha = if phase == "showing" then 0.1 else math.min(0.1 + textFade * 0.9, 1)
		local timerMillisAlpha = if phase == "showing" then 0.55 else math.min(0.55 + textFade * 0.45, 1)
		local timerSubAlpha = if phase == "showing" then 0.4 else math.min(0.4 + textFade * 0.6, 1)

		content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),

			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 20),
				PaddingLeft = UDim.new(0, 24),
				PaddingRight = UDim.new(0, 24),
			}),

			-- Round counter top-left (stays visible through transition)
			RoundLabel = roundLabel ~= "" and StrokedText({
				Size = UDim2.fromOffset(100, 28),
				Position = UDim2.new(0, if transitionProgress > 0 then 224 else 0, 0, 0),
				BackgroundTransparency = 1,
				Text = roundLabel,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.5,
				TextSize = 24,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			}),

			-- Timer: centered frame, UIListLayout handles alignment
			TimerArea = e("Frame", {
				Size = UDim2.fromOffset(260, 130),
				Position = UDim2.fromScale(0.5, 0.4),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, {
				-- Row for seconds + millis. Split into two labels so the seconds
				-- can slide in/out independently. Roblox TextYAlignment aligns
				-- text bounding boxes (not glyph baselines), so the Millis needs
				-- a manual Y offset to compensate for the descent-padding delta
				-- between 72pt and 32pt FredokaOne. Tune MILLIS_BASELINE_OFFSET
				-- by ±1–2 pixels in Studio until the digit bottoms are flush.
				Row = e("Frame", {
					Size = UDim2.new(1, 0, 0, 80),
					BackgroundTransparency = 1,
				}, (function()
					local MILLIS_BASELINE_OFFSET = -8 -- tune me (more negative = millis moves up)
					return {
						SecondsClip = e("Frame", {
							Size = UDim2.fromOffset(55, 80),
							AnchorPoint = Vector2.new(1, 1),
							Position = UDim2.new(0.5, -2, 1, 0),
							BackgroundTransparency = 1,
							ClipsDescendants = true,
						}, {
							Outgoing = (secondsSlide < 1 and prevSecondsText ~= "") and StrokedText({
								Size = UDim2.fromScale(1, 1),
								Position = UDim2.new(0, 0, secondsSlide, 0),
								BackgroundTransparency = 1,
								Text = prevSecondsText,
								TextColor3 = Color3.fromRGB(255, 255, 255),
								TextTransparency = timerTextAlpha + secondsSlide * (1 - timerTextAlpha),
								TextSize = 72,
								Font = Enum.Font.FredokaOne,
								TextYAlignment = Enum.TextYAlignment.Bottom,
							}),

							Incoming = StrokedText({
								Size = UDim2.fromScale(1, 1),
								Position = UDim2.new(0, 0, (1 - secondsSlide) * -1, 0),
								BackgroundTransparency = 1,
								Text = secondsText,
								TextColor3 = Color3.fromRGB(255, 255, 255),
								TextTransparency = timerTextAlpha,
								TextSize = 72,
								Font = Enum.Font.FredokaOne,
								TextYAlignment = Enum.TextYAlignment.Bottom,
							}),
						}),

						Millis = StrokedText({
							Size = UDim2.fromOffset(45, 40),
							AnchorPoint = Vector2.new(0, 1),
							Position = UDim2.new(0.5, 4, 1, MILLIS_BASELINE_OFFSET),
							BackgroundTransparency = 1,
							Text = millisText,
							TextColor3 = Color3.fromRGB(255, 255, 255),
							TextTransparency = timerMillisAlpha,
							TextSize = 32,
							Font = Enum.Font.FredokaOne,
							TextXAlignment = Enum.TextXAlignment.Left,
							TextYAlignment = Enum.TextYAlignment.Bottom,
						}),
					}
				end)()),

				-- Subtitle below the row
				Subtitle = StrokedText({
					Size = UDim2.new(1, 0, 0, 34),
					Position = UDim2.fromOffset(0, 88),
					BackgroundTransparency = 1,
					Text = "Seconds to remember",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextTransparency = timerSubAlpha,
					TextSize = 26,
					Font = Enum.Font.FredokaOne,
				}),
			}),

			-- Guess countdown timer (top-right corner, lowkey)
			GuessTimer = (phase == "guessing") and (function()
				local seconds = math.ceil(guessTimeLeft)
				local urgent = guessTimeLeft <= 5
				local bgColor = if urgent
					then Color3.fromRGB(200, 50, 50)
					else Color3.fromRGB(20, 20, 20)
				return e("Frame", {
					Size = UDim2.fromOffset(88, 46),
					Position = UDim2.new(1, -16, 0, 16),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundColor3 = bgColor,
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
						Text = `{seconds}s`,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						TextSize = 30,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
					}),
				})
			end)() or nil,

			-- Submit button (bottom-right of color frame, only visible during guessing)
			SubmitButton = (phase == "guessing") and e("TextButton", {
				Size = UDim2.fromOffset(220, 84),
				Position = UDim2.new(1, -20, 1, -20),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = true,
				ZIndex = 9,
				[React.Event.Activated] = onSubmit,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 16) }),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(0, 0, 0),
					Thickness = 2,
					Transparency = 0.4,
				}),
				Label = e("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "Submit",
					TextColor3 = Color3.fromRGB(30, 30, 30),
					TextSize = 38,
					Font = Enum.Font.FredokaOne,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),
			}) or nil,

			-- Color picker strips (slide in from left, then slide out left on solo submit)
			PickerWrapper = (phase ~= "showing") and e("Frame", {
				Size = UDim2.new(0, 200, 1, 0),
				Position = UDim2.new(0, pickerOffset, 0, 0),
				BackgroundTransparency = 1,
				ZIndex = 5,
			}, {
				Picker = e(ColorPicker, {
					guessH = guessH,
					guessS = guessS,
					guessV = guessV,
					onChangeH = setGuessH,
					onChangeS = setGuessS,
					onChangeV = setGuessV,
				}),
			}),

			-- Hint swatch: mini target color reference (1v1 only, after purchase)
			HintSwatch = (phase == "guessing" and hintActive and not isSolo and hintPopScale > 0) and e("Frame", {
				Size = UDim2.fromOffset(96, 96),
				Position = UDim2.new(0, 220, 1, -20),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = targetColor,
				BorderSizePixel = 0,
				ZIndex = 10,
			}, {
				Scale = e("UIScale", { Scale = hintPopScale }),
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 14) }),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(255, 255, 255),
					Thickness = 2,
					Transparency = 0.3,
				}),
				Label = StrokedText({
					Size = UDim2.new(1, 0, 0, 18),
					Position = UDim2.new(0.5, 0, 0, -20),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundTransparency = 1,
					Text = "HINT",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 14,
					Font = Enum.Font.FredokaOne,
				}),
			}) or nil,
		})
	elseif phase == "submitted" then
		content = e(WaitingScreen, {
			opponentName = if isSolo then nil else opponentName,
			secondsLeft = if isSolo then nil else guessTimeLeft,
		})
	elseif phase == "roundResult" then
		content = e(RevealScreen, {
			targetColor = targetColor,
			guessColor = submittedColor,
			score = myScore,
			roundNumber = if isSolo then soloRoundNumber else myWins + opponentWins,
			totalRounds = if isSolo then soloTotalRounds else roundsToWin * 2 - 1,
			onNext = if isSolo then onNextRound else nil,
			solo = isSolo,
			opponentScore = if isSolo then nil else opponentScore,
			opponentName = if isSolo then nil else opponentName,
			opponentGuessColor = if isSolo then nil else opponentGuessColor,
			myWins = if isSolo then nil else myWins,
			opponentWins = if isSolo then nil else opponentWins,
			myUserId = if isSolo then nil else myUserId,
			opponentUserId = if isSolo then nil else opponentUserId,
			roundsToWin = if isSolo then nil else roundsToWin,
			myRoundOutcomes = if isSolo then nil else myRoundOutcomes,
			opponentRoundOutcomes = if isSolo then nil else (function()
				local flipped = {}
				for _, o in myRoundOutcomes do
					if o == "win" then
						table.insert(flipped, "loss")
					elseif o == "loss" then
						table.insert(flipped, "win")
					else
						table.insert(flipped, "tie")
					end
				end
				return flipped
			end)(),
		})
	elseif phase == "matchEnd" then
		if isSolo then
			-- Compute total score across all rounds (max = roundCount * 100)
			local totalScore = 0
			for _, entry in roundHistory do
				totalScore += (entry.myScore or 0)
			end
			local maxScore = #roundHistory * 100
			if maxScore <= 0 then
				maxScore = soloTotalRounds * 100
			end

			local totalColor
			local pct = if maxScore > 0 then totalScore / maxScore else 0
			if pct >= 0.75 then
				totalColor = Color3.fromRGB(120, 255, 140)
			elseif pct >= 0.50 then
				totalColor = Color3.fromRGB(255, 230, 120)
			elseif pct >= 0.25 then
				totalColor = Color3.fromRGB(255, 170, 110)
			else
				totalColor = Color3.fromRGB(255, 120, 120)
			end

			local cardChildren: { [string]: any } = {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 14),
				}),
			}
			for i, entry in roundHistory do
				local target = entry.target or { h = 0, s = 0, v = 0 }
				local guess = entry.myGuess or { h = 0, s = 0, v = 0 }
				cardChildren["Card" .. i] = e(DiamondCard, {
					targetColor = Color3.fromHSV(target.h or 0, target.s or 0, target.v or 0),
					guessColor = Color3.fromHSV(guess.h or 0, guess.s or 0, guess.v or 0),
					score = entry.myScore or 0,
					layoutOrder = i,
				})
			end

			content = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, 40),
					PaddingBottom = UDim.new(0, 32),
					PaddingLeft = UDim.new(0, 48),
					PaddingRight = UDim.new(0, 48),
				}),

				Title = StrokedText({
					Size = UDim2.new(0.55, 0, 0, 56),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					Text = "Practice Complete",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 42,
					Font = Enum.Font.FredokaOne,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),

				Total = StrokedText({
					Size = UDim2.new(0.45, 0, 0, 64),
					Position = UDim2.new(1, 0, 0, 0),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundTransparency = 1,
					Text = `{totalScore} / {maxScore}`,
					TextColor3 = totalColor,
					TextSize = 56,
					Font = Enum.Font.FredokaOne,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),

				Flair = StrokedText({
					Size = UDim2.new(1, 0, 0, 28),
					Position = UDim2.fromOffset(0, 60),
					BackgroundTransparency = 1,
					Text = endFlairText,
					TextColor3 = Color3.fromRGB(220, 220, 220),
					TextTransparency = 0.1,
					TextSize = 22,
					Font = Enum.Font.FredokaOne,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),

				Cards = e("Frame", {
					Size = UDim2.new(1, 0, 0, 130),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
				}, cardChildren),

				DoneButton = e("TextButton", {
					Size = UDim2.fromOffset(160, 64),
					Position = UDim2.new(0, 0, 1, 0),
					AnchorPoint = Vector2.new(0, 1),
					BackgroundColor3 = Color3.fromRGB(20, 20, 20),
					BackgroundTransparency = 0.2,
					BorderSizePixel = 0,
					AutoButtonColor = true,
					Text = "",
					[React.Event.Activated] = function()
						handleClose()
					end,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(255, 255, 255),
						Thickness = 2,
						Transparency = 0.3,
					}),
					Label = e("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "Done",
						TextColor3 = Color3.fromRGB(230, 230, 230),
						TextSize = 26,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
					}),
				}),

				PlayAgainButton = e("TextButton", {
					Size = UDim2.fromOffset(280, 76),
					Position = UDim2.new(1, 0, 1, 0),
					AnchorPoint = Vector2.new(1, 1),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BorderSizePixel = 0,
					AutoButtonColor = true,
					Text = "",
					[React.Event.Activated] = function()
						local remotes = ReplicatedStorage:FindFirstChild("Remotes")
						if remotes then
							local restart = remotes:FindFirstChild("RestartSolo")
							if restart then
								restart:FireServer()
							end
						end
					end,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(0, 0, 0),
						Thickness = 2,
						Transparency = 0.4,
					}),
					Label = e("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "Play Again",
						TextColor3 = Color3.fromRGB(30, 30, 30),
						TextSize = 32,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
					}),
				}),
			})
		else
			-- 1v1 end screen — diamond cards in two stacked rows. The winning
			-- player is rendered larger, with a crown above their avatar and
			-- a gold name. Per-round wins are highlighted with a gold stroke
			-- on the diamond cards.
			local myWinsCount = 0
			local oppWinsCount = 0
			local myPerceptualSum = 0
			local oppPerceptualSum = 0
			for _, entry in roundHistory do
				if entry.outcome == "win" then
					myWinsCount += 1
				elseif entry.outcome == "loss" then
					oppWinsCount += 1
				end
				myPerceptualSum += (entry.myScore or 0)
				oppPerceptualSum += (entry.opponentScore or 0)
			end

			local localPlayer = Players.LocalPlayer
			local myName = (localPlayer and localPlayer.DisplayName) or "You"

			-- Abandonment always resolves to a decisive outcome for the
			-- remaining player (server granted the win); never render Draw.
			local isTie = (not matchAbandoned) and (myWinsCount == oppWinsCount)
			local iWon = (not isTie) and matchWon
			local oppWonMatch = (not isTie) and (not matchWon)

			local titleText
			local titleColor
			if isTie then
				titleText = "Draw"
				titleColor = Color3.fromRGB(255, 230, 120)
			elseif iWon then
				titleText = "Victory!"
				titleColor = Color3.fromRGB(255, 215, 0) -- gold
			else
				titleText = "Defeat"
				titleColor = Color3.fromRGB(220, 90, 90)
			end

			-- Build the per-row diamond children for one player. `forSelf`
			-- selects which guess/score to render; `cardSize` and `wonRound`
			-- control the per-card visuals.
			local function buildRowCards(forSelf: boolean, cardSize: number)
				local children: { [string]: any } = {
					Layout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					}),
				}
				for i, entry in roundHistory do
					local target = entry.target or { h = 0, s = 0, v = 0 }
					local guess = if forSelf
						then (entry.myGuess or { h = 0, s = 0, v = 0 })
						else (entry.opponentGuess or { h = 0, s = 0, v = 0 })
					local score = if forSelf then (entry.myScore or 0) else (entry.opponentScore or 0)
					-- "win" means I won this round; flip for the opponent row.
					local wonRound = if forSelf
						then entry.outcome == "win"
						else entry.outcome == "loss"
					children["Card" .. i] = e(DiamondCard, {
						targetColor = Color3.fromHSV(target.h or 0, target.s or 0, target.v or 0),
						guessColor = Color3.fromHSV(guess.h or 0, guess.s or 0, guess.v or 0),
						score = score,
						size = cardSize,
						wonRound = wonRound,
						layoutOrder = i,
					})
				end
				return children
			end

			local function buildPlayerRow(args: {
				userId: number,
				name: string,
				wins: number,
				perceptualSum: number,
				forSelf: boolean,
				isWinner: boolean,
				positionY: number,
			})
				local thumbUrl = if args.userId and args.userId > 0
					then `rbxthumb://type=AvatarHeadShot&id={args.userId}&w=150&h=150`
					else ""
				local rowHeight = if args.isWinner then 120 else 92
				local avatarSize = if args.isWinner then 88 else 60
				local baseCardSize = if args.isWinner then 86 else 70
				-- Shrink cards when many rounds so they don't overflow into the name area.
				local maxCardsWidth = 414
				local numRounds = #roundHistory
				local cardSize = if numRounds > 0
					then math.min(baseCardSize, math.floor((maxCardsWidth - (numRounds - 1) * 8) / numRounds))
					else baseCardSize
				local nameSize = if args.isWinner then 26 else 20
				local nameColor = if args.isWinner
					then Color3.fromRGB(255, 215, 0)
					else Color3.fromRGB(230, 230, 230)
				local statColor = if args.isWinner
					then Color3.fromRGB(255, 235, 150)
					else Color3.fromRGB(180, 180, 180)
				local textLeftOffset = if args.isWinner then (avatarSize + 18) else (avatarSize + 14)

				local children: { [string]: any } = {
					AvatarBg = e("Frame", {
						Size = UDim2.fromOffset(avatarSize, avatarSize),
						Position = UDim2.new(0, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundTransparency = 1,
					}, {
						Avatar = e("ImageLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.fromRGB(40, 40, 40),
							BorderSizePixel = 0,
							Image = thumbUrl,
						}, {
							Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
							Stroke = e("UIStroke", {
								Color = if args.isWinner
									then Color3.fromRGB(255, 215, 0)
									else Color3.fromRGB(255, 255, 255),
								Thickness = if args.isWinner then 3 else 2,
								Transparency = if args.isWinner then 0 else 0.4,
							}),
						}),
						-- Crown sits above the avatar for the winning player
						Crown = args.isWinner and e("ImageLabel", {
							Size = UDim2.fromOffset(48, 48),
							Position = UDim2.new(0.5, 0, 0, -8),
							AnchorPoint = Vector2.new(0.5, 1),
							BackgroundTransparency = 1,
							Image = "rbxassetid://128383063987894",
							ScaleType = Enum.ScaleType.Fit,
							ZIndex = 3,
						}) or nil,
					}),
					NameLabel = StrokedText({
						Size = UDim2.fromOffset(140, nameSize + 6),
						Position = UDim2.new(0, textLeftOffset, 0.5, -(nameSize / 2 + 4)),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundTransparency = 1,
						Text = args.name,
						TextColor3 = nameColor,
						TextSize = nameSize,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}),
					StatLabel = StrokedText({
						Size = UDim2.fromOffset(140, 22),
						Position = UDim2.new(0, textLeftOffset, 0.5, nameSize / 2 - 2),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundTransparency = 1,
						Text = `{args.wins} wins  ·  {args.perceptualSum} pts`,
						TextColor3 = statColor,
						TextTransparency = 0.05,
						TextSize = 18,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}),
					Cards = e("Frame", {
						Size = UDim2.new(1, -250, 1, 0),
						Position = UDim2.new(1, 0, 0, 0),
						AnchorPoint = Vector2.new(1, 0),
						BackgroundTransparency = 1,
					}, buildRowCards(args.forSelf, cardSize)),
				}

				return e("Frame", {
					Size = UDim2.new(1, 0, 0, rowHeight),
					Position = UDim2.fromOffset(0, args.positionY),
					BackgroundTransparency = 1,
				}, children)
			end

			-- Winner goes on top with the larger row. Tie = both same size,
			-- self on top by convention. The top row is pushed down to leave
			-- enough room for the crown (which floats above the avatar) to
			-- clear the pill row above.
			local myIsWinner = iWon
			local oppIsWinner = oppWonMatch
			local myRowY, oppRowY
			if oppWonMatch then
				-- Opponent is the winner — render them on top
				oppRowY = 170
				myRowY = 310
			else
				myRowY = 170
				oppRowY = 310
			end

			-- Pill helper for the +cash / +win badges shown under the title.
			-- Each pill is a dark rounded rectangle with an icon on the left
			-- and text to its right. The icon spec is either an asset id or
			-- "$" for an inline gold coin glyph (no asset required).
			local function buildPill(args: {
				icon: string,
				iconKind: string, -- "asset" | "dollar"
				label: string,
				accent: Color3,
				layoutOrder: number,
			})
				local iconSize = 32
				local iconChild
				if args.iconKind == "asset" then
					iconChild = e("ImageLabel", {
						Size = UDim2.fromOffset(iconSize, iconSize),
						Position = UDim2.new(0, 8, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundTransparency = 1,
						Image = args.icon,
						ScaleType = Enum.ScaleType.Fit,
					})
				else
					-- Inline gold "$" coin built from primitives so it works
					-- without uploading a currency asset.
					iconChild = e("Frame", {
						Size = UDim2.fromOffset(iconSize, iconSize),
						Position = UDim2.new(0, 8, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = Color3.fromRGB(255, 215, 0),
						BorderSizePixel = 0,
					}, {
						Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
						Stroke = e("UIStroke", {
							Color = Color3.fromRGB(180, 130, 0),
							Thickness = 2,
							Transparency = 0.1,
						}),
						Glyph = e("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = "$",
							TextColor3 = Color3.fromRGB(80, 50, 0),
							TextSize = 22,
							Font = Enum.Font.FredokaOne,
							TextXAlignment = Enum.TextXAlignment.Center,
							TextYAlignment = Enum.TextYAlignment.Center,
						}),
					})
				end
				return e("Frame", {
					Size = UDim2.fromOffset(160, 48),
					BackgroundColor3 = Color3.fromRGB(28, 28, 28),
					BackgroundTransparency = 0.15,
					BorderSizePixel = 0,
					LayoutOrder = args.layoutOrder,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Stroke = e("UIStroke", {
						Color = args.accent,
						Thickness = 2,
						Transparency = 0.1,
					}),
					Icon = iconChild,
					Label = StrokedText({
						Size = UDim2.new(1, -52, 1, 0),
						Position = UDim2.fromOffset(48, 0),
						BackgroundTransparency = 1,
						Text = args.label,
						TextColor3 = args.accent,
						TextSize = 22,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Center,
					}),
				})
			end

			local pillChildren: { [string]: any } = {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 14),
				}),
			}
			local hasPills = false
			if cashEarned and cashEarned > 0 then
				hasPills = true
				pillChildren.CashPill = buildPill({
					icon = "rbxassetid://83945987909294",
					iconKind = "asset",
					label = `+{cashEarned}`,
					accent = Color3.fromRGB(255, 220, 110),
					layoutOrder = 1,
				})
			end
			if iWon then
				hasPills = true
				local winLabel = if winsAwarded and winsAwarded > 1 then `+{winsAwarded} WINS` else "+1 WIN"
				pillChildren.WinPill = buildPill({
					icon = "rbxassetid://128383063987894",
					iconKind = "asset",
					label = winLabel,
					accent = Color3.fromRGB(255, 215, 0),
					layoutOrder = 2,
				})
			end
			if cashMultiplier and cashMultiplier > 1 then
				hasPills = true
				local multText = if cashMultiplier == math.floor(cashMultiplier)
					then string.format("CASH x%d!", cashMultiplier)
					else string.format("CASH x%.1f!", cashMultiplier)
				pillChildren.MultPill = buildPill({
					icon = "rbxassetid://83945987909294",
					iconKind = "asset",
					label = multText,
					accent = Color3.fromRGB(120, 255, 160),
					layoutOrder = 3,
				})
			end

			content = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, 28),
					PaddingBottom = UDim.new(0, 28),
					PaddingLeft = UDim.new(0, 48),
					PaddingRight = UDim.new(0, 48),
				}),

				Title = StrokedText({
					Size = UDim2.new(1, 0, 0, 60),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					Text = titleText,
					TextColor3 = titleColor,
					TextSize = 52,
					Font = Enum.Font.FredokaOne,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),

				PillRow = hasPills and e("Frame", {
					Size = UDim2.new(1, 0, 0, 48),
					Position = UDim2.fromOffset(0, 68),
					BackgroundTransparency = 1,
				}, pillChildren) or nil,

				MyRow = buildPlayerRow({
					userId = myUserId,
					name = myName,
					wins = myWinsCount,
					perceptualSum = myPerceptualSum,
					forSelf = true,
					isWinner = myIsWinner,
					positionY = myRowY,
				}),

				OppRow = buildPlayerRow({
					userId = opponentUserId,
					name = if opponentName ~= "" then opponentName else "Opponent",
					wins = oppWinsCount,
					perceptualSum = oppPerceptualSum,
					forSelf = false,
					isWinner = oppIsWinner,
					positionY = oppRowY,
				}),

				DoneButton = e("TextButton", {
					Size = UDim2.fromOffset(220, 64),
					Position = UDim2.new(1, 0, 1, 0),
					AnchorPoint = Vector2.new(1, 1),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BorderSizePixel = 0,
					AutoButtonColor = true,
					Text = "",
					[React.Event.Activated] = handleClose,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(0, 0, 0),
						Thickness = 2,
						Transparency = 0.4,
					}),
					Label = e("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "Done",
						TextColor3 = Color3.fromRGB(30, 30, 30),
						TextSize = 30,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
					}),
				}),
			})
		end
	end

	if not content then
		return nil
	end

	-- Seated (1v1) phase: no dark backdrop, no UIScale wrapper — the player
	-- should see themselves at the table. Render the minimal top UI directly.
	if phase == "seated" and not isSolo then
		return e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Inner = content,
		})
	end

	-- Show persistent player info bar during 1v1 gameplay phases
	local show1v1Bar = not isSolo and infoBarSlide > 0
		and (phase == "showing" or phase == "guessing" or phase == "submitted")
	local localPlayer = Players.LocalPlayer
	local infoBarHeight = if show1v1Bar then 72 else 0
	local contentTopOffset = if show1v1Bar then 82 else 0 -- bar + 10px gap

	-- Root wrapper with UIScale
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Inner = e("Frame", {
			Size = UDim2.fromOffset(800, 600),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(20, 20, 20),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			-- Sink touch input within the frame so dragging sliders doesn't pan the camera
			Active = true,
		}, {
			Scale = e("UIScale", {
				Scale = uiScale * dismissScale,
			}),

			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 20),
			}),

			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 20),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),

			-- Persistent player info bar (1v1, during gameplay phases)
			InfoBar = show1v1Bar and e(PlayerInfoBar, {
				myUserId = myUserId,
				myName = localPlayer and localPlayer.DisplayName or "You",
				myRoundOutcomes = myRoundOutcomes,
				opponentUserId = opponentUserId,
				opponentName = opponentName,
				opponentRoundOutcomes = (function()
					local flipped = {}
					for _, o in myRoundOutcomes do
						if o == "win" then
							table.insert(flipped, "loss")
						elseif o == "loss" then
							table.insert(flipped, "win")
						else
							table.insert(flipped, "tie")
						end
					end
					return flipped
				end)(),
				slideProgress = infoBarSlide,
			}),

			-- Content area (shifted down when info bar is visible)
			Content = e("Frame", {
				Size = UDim2.new(1, 0, 1, -contentTopOffset),
				Position = UDim2.fromOffset(0, contentTopOffset),
				BackgroundTransparency = 1,
			}, {
				Inner = content,
			}),

			-- Persistent exit button — floats in the top-right corner above
			-- all phase content. Position offsets push past the Inner UIPadding
			-- (20px) so the button sits flush against the rounded corner.
			-- HIDDEN during active 1v1 gameplay so a player can't bail mid-match
			-- on their opponent, on the matchEnd screen (Done button handles it),
			-- and on the seated/waiting screen (LEAVE TABLE button handles it).
			ExitButton = (function()
				local hideForActive1v1 = (not isSolo) and (
					phase == "countdown"
					or phase == "showing"
					or phase == "guessing"
					or phase == "submitted"
					or phase == "roundResult"
					or phase == "seated"
				)
				if hideForActive1v1 or phase == "matchEnd" then
					return nil
				end
				return e("ImageButton", {
					Size = UDim2.fromOffset(54, 54),
					Position = UDim2.new(1, 14, 0, -14),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundTransparency = 1,
					Image = "rbxassetid://118846091715989",
					ImageTransparency = 0.1,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 100,
					AutoButtonColor = true,
					[React.Event.Activated] = handleClose,
				})
			end)(),
		}),
	})
end

return GameController
