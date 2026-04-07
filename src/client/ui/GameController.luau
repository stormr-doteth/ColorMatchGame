local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
			children.X = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "✕",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 22,
				Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
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

	-- Match state
	local phase, setPhase = React.useState("idle") -- idle|seated|waiting|showing|guessing|submitted|roundResult|matchEnd
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
	local cashEarned, setCashEarned = React.useState(0)
	local roundHistory, setRoundHistory = React.useState({})
	local myRoundOutcomes, setMyRoundOutcomes = React.useState({})

	-- Countdown state ("Ready", "Set", "GO!")
	local countdownText, setCountdownText = React.useState("")
	local countdownFade, setCountdownFade = React.useState(0) -- 0=visible, 1=transparent

	-- Store guess color at submit time for the result screen
	local submittedColor, setSubmittedColor = React.useState(Color3.new(0.5, 0.5, 0.5))

	-- Player info bar slide animation (1v1 only)
	local infoBarSlide, setInfoBarSlide = React.useState(0)
	local prevPhaseRef = React.useRef("idle")

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
			if data.solo then
				-- Solo skips waiting, goes straight to first round
				setPhase("showing")
			else
				setPhase("waiting")
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
			setPhase("showing")
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
			setCashEarned(data.cashEarned or 0)
			if data.solo then
				setSoloAverage(data.averageScore or 0)
				setSoloBest(data.bestScore or 0)
			end
			setRoundHistory(data.roundHistory or {})
			setPhase("matchEnd")

			task.delay(12, function()
				setPhase("idle")
			end)
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
		-- Just start the countdown — server gets notified at the end
		setPhase("countdown")
	end

	-- Countdown "Ready, Set, GO!" animation — fires NextRound at the end
	React.useEffect(function()
		if phase ~= "countdown" then
			return
		end
		local running = true
		setCountdownFade(0)
		setCountdownText("")
		task.spawn(function()
			-- Fade to black
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
			task.wait(0.3)
			if not running then return end

			-- NOW tell the server to start the next round
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				remotes.NextRound:FireServer()
			end
			-- Server will fire RoundShowColor which sets phase to "showing"
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
		-- Fades to target color, then shows "Ready, Set, GO!"
		content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = targetColor,
			BackgroundTransparency = 1 - countdownFade,
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

			PlayerCount = StrokedText({
				Size = UDim2.fromOffset(500, 56),
				BackgroundTransparency = 1,
				Text = if isSolo then "Solo Practice" else `{seatedPlayerCount}/2 Players`,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 44,
				Font = Enum.Font.FredokaOne,
				LayoutOrder = 1,
			}),

			Waiting = StrokedText({
				Size = UDim2.fromOffset(500, 36),
				BackgroundTransparency = 1,
				Text = if isSolo then "Starting..." else "Waiting for opponent...",
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextSize = 24,
				Font = Enum.Font.FredokaOne,
				LayoutOrder = 2,
			}),
		})
	elseif phase == "waiting" then
		content = e(WaitingScreen, {
			opponentName = opponentName,
		})
	elseif phase == "showing" or phase == "guessing" then
		-- Unified showing → guessing view
		-- During showing: full color frame with timer countdown
		-- During guessing: timer fades out, picker slides in from left, preview is the guess color

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

		-- Picker slides in from off-screen left. At progress=0, offset is -220 (hidden). At 1, offset is 0.
		local pickerOffset = (1 - transitionProgress) * -220

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
				Position = UDim2.new(0, if transitionProgress > 0 then 200 else 0, 0, 0),
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
				Size = UDim2.fromOffset(200, 110),
				Position = UDim2.fromScale(0.5, 0.4),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, {
				-- Row for seconds + millis, bottom-aligned horizontally
				Row = e("Frame", {
					Size = UDim2.new(1, 0, 0, 80),
					BackgroundTransparency = 1,
				}, {
					RowLayout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Bottom,
					}),

					SecondsClip = e("Frame", {
						Size = UDim2.fromOffset(55, 80),
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						LayoutOrder = 1,
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
						}),
					}),

					Millis = StrokedText({
						Size = UDim2.fromOffset(45, 40),
						BackgroundTransparency = 1,
						Text = millisText,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						TextTransparency = timerMillisAlpha,
						TextSize = 32,
						Font = Enum.Font.FredokaOne,
						TextXAlignment = Enum.TextXAlignment.Left,
						LayoutOrder = 2,
					}),
				}),

				-- Subtitle below the row
				Subtitle = StrokedText({
					Size = UDim2.new(1, 0, 0, 22),
					Position = UDim2.fromOffset(0, 84),
					BackgroundTransparency = 1,
					Text = "Seconds to remember",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextTransparency = timerSubAlpha,
					TextSize = 16,
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

			-- Color picker strips (slide in from left)
			PickerWrapper = (phase == "guessing") and e("Frame", {
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
			content = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 12),
				}),

				Title = StrokedText({
					Size = UDim2.fromOffset(500, 44),
					BackgroundTransparency = 1,
					Text = "Practice Complete!",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 36,
					Font = Enum.Font.FredokaOne,
					LayoutOrder = 1,
				}),

				Average = StrokedText({
					Size = UDim2.fromOffset(500, 36),
					BackgroundTransparency = 1,
					Text = `Average: {soloAverage}%   Best: {soloBest}%`,
					TextColor3 = if soloAverage >= 70 then Color3.fromRGB(100, 255, 100)
						elseif soloAverage >= 40 then Color3.fromRGB(255, 255, 100)
						else Color3.fromRGB(255, 100, 100),
					TextSize = 28,
					Font = Enum.Font.FredokaOne,
					LayoutOrder = 2,
				}),

				History = e(HistoryGrid, {
					history = roundHistory,
					isSolo = true,
					LayoutOrder = 3,
				}),
			})
		else
			content = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 12),
				}),

				Result = StrokedText({
					Size = UDim2.fromOffset(600, 56),
					BackgroundTransparency = 1,
					Text = if matchWon then "You Win!" else "You Lose",
					TextColor3 = if matchWon
						then Color3.fromRGB(100, 255, 100)
						else Color3.fromRGB(255, 100, 100),
					TextSize = 48,
					Font = Enum.Font.FredokaOne,
					LayoutOrder = 1,
				}),

				Cash = matchWon and StrokedText({
					Size = UDim2.fromOffset(400, 32),
					BackgroundTransparency = 1,
					Text = `+${cashEarned}`,
					TextColor3 = Color3.fromRGB(50, 255, 50),
					TextSize = 28,
					Font = Enum.Font.FredokaOne,
					LayoutOrder = 2,
				}),

				History = e(HistoryGrid, {
					history = roundHistory,
					isSolo = false,
					LayoutOrder = 3,
				}),
			})
		end
	end

	if not content then
		return nil
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
				Scale = uiScale,
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
		}),
	})
end

return GameController
