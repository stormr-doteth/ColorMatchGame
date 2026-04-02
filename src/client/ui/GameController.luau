local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local ColorDisplay = require(script.Parent.components.ColorDisplay)
local ColorPicker = require(script.Parent.components.ColorPicker)
local MatchScoreScreen = require(script.Parent.components.MatchScoreScreen)
local WaitingScreen = require(script.Parent.components.WaitingScreen)

local e = React.createElement

-- Reference resolution for UIScale
local REF_WIDTH = 1920
local REF_HEIGHT = 1080

local function GameController()
	-- UI scale
	local uiScale, setUIScale = React.useState(1)

	-- Match state
	local phase, setPhase = React.useState("idle") -- idle|seated|waiting|showing|guessing|submitted|roundResult|matchEnd
	local opponentName, setOpponentName = React.useState("")
	local roundsToWin, setRoundsToWin = React.useState(3)
	local seatedPlayerCount, setSeatedPlayerCount = React.useState(0)

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

	-- Match end state
	local matchWon, setMatchWon = React.useState(false)
	local cashEarned, setCashEarned = React.useState(0)

	-- Store guess color at submit time for the result screen
	local submittedColor, setSubmittedColor = React.useState(Color3.new(0.5, 0.5, 0.5))

	-- Viewport scale tracking
	React.useEffect(function()
		local camera = workspace.CurrentCamera
		local function updateScale()
			local viewport = camera.ViewportSize
			local scaleX = viewport.X / REF_WIDTH
			local scaleY = viewport.Y / REF_HEIGHT
			setUIScale(math.min(scaleX, scaleY))
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
			setPhase("seated")
		end))

		table.insert(connections, remotes:WaitForChild("MatchStart").OnClientEvent:Connect(function(data)
			setOpponentName(data.opponentName)
			setRoundsToWin(data.roundsToWin)
			setMyWins(0)
			setOpponentWins(0)
			setPhase("waiting")
		end))

		table.insert(connections, remotes:WaitForChild("RoundShowColor").OnClientEvent:Connect(function(data)
			setTargetH(data.h)
			setTargetS(data.s)
			setTargetV(data.v)
			setTimeLeft(data.duration)
			setGuessH(0.5)
			setGuessS(0.5)
			setGuessV(0.5)
			setPhase("showing")
		end))

		table.insert(connections, remotes:WaitForChild("RoundGuessPhase").OnClientEvent:Connect(function()
			setPhase("guessing")
		end))

		table.insert(connections, remotes:WaitForChild("RoundResult").OnClientEvent:Connect(function(data)
			setMyScore(data.myScore)
			setOpponentScore(data.opponentScore)
			setMyWins(data.myTotalWins)
			setOpponentWins(data.opponentTotalWins)
			setTargetH(data.targetH)
			setTargetS(data.targetS)
			setTargetV(data.targetV)
			setPhase("roundResult")
		end))

		table.insert(connections, remotes:WaitForChild("MatchEnd").OnClientEvent:Connect(function(data)
			setMatchWon(data.won)
			setCashEarned(data.cashEarned)
			setPhase("matchEnd")

			-- Return to idle after delay
			task.delay(5, function()
				setPhase("idle")
			end)
		end))

		return function()
			for _, conn in connections do
				conn:Disconnect()
			end
		end
	end, {})

	-- Local countdown timer during showing phase
	React.useEffect(function()
		if phase ~= "showing" then
			return
		end
		local running = true
		task.spawn(function()
			for i = timeLeft - 1, 0, -1 do
				task.wait(1)
				if not running then
					return
				end
				setTimeLeft(i)
			end
		end)
		return function()
			running = false
		end
	end, { phase })

	local function onSubmit()
		if phase ~= "guessing" then
			return
		end
		-- Save guess color for display on result screen
		setSubmittedColor(Color3.fromHSV(guessH, guessS, guessV))
		setPhase("submitted")
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			remotes.SubmitGuess:FireServer({ h = guessH, s = guessS, v = guessV })
		end
	end

	local targetColor = Color3.fromHSV(targetH, targetS, targetV)
	local guessColor = Color3.fromHSV(guessH, guessS, guessV)

	-- Render phase content
	local content

	if phase == "idle" then
		-- Nothing visible — player should walk to a table
		return nil
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

			PlayerCount = e("TextLabel", {
				Size = UDim2.fromOffset(500, 56),
				BackgroundTransparency = 1,
				Text = `{seatedPlayerCount}/2 Players`,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 44,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 1,
			}),

			Waiting = e("TextLabel", {
				Size = UDim2.fromOffset(500, 36),
				BackgroundTransparency = 1,
				Text = "Waiting for opponent...",
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextSize = 24,
				Font = Enum.Font.GothamMedium,
				LayoutOrder = 2,
			}),
		})
	elseif phase == "waiting" then
		content = e(WaitingScreen, {
			opponentName = opponentName,
		})
	elseif phase == "showing" then
		content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 24),
			}),

			Title = e("TextLabel", {
				Size = UDim2.fromOffset(500, 48),
				BackgroundTransparency = 1,
				Text = "Memorize this color!",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 36,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 1,
			}),

			Color = e(ColorDisplay, {
				color = targetColor,
				Size = UDim2.fromOffset(300, 300),
				LayoutOrder = 2,
			}),

			Timer = e("TextLabel", {
				Size = UDim2.fromOffset(100, 60),
				BackgroundTransparency = 1,
				Text = tostring(timeLeft),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 52,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 3,
			}),
		})
	elseif phase == "guessing" then
		content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 20),
			}),

			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 20),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),

			Picker = e(ColorPicker, {
				guessH = guessH,
				guessS = guessS,
				guessV = guessV,
				onChangeH = setGuessH,
				onChangeS = setGuessS,
				onChangeV = setGuessV,
			}),

			Preview = e("Frame", {
				Size = UDim2.new(1, -200, 1, 0),
				Position = UDim2.new(0, 192, 0, 0),
				BackgroundColor3 = guessColor,
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 16),
				}),

				Submit = e("TextButton", {
					Size = UDim2.fromOffset(64, 64),
					Position = UDim2.new(1, -20, 1, -20),
					AnchorPoint = Vector2.new(1, 1),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BorderSizePixel = 0,
					Text = "Go",
					TextColor3 = Color3.fromRGB(30, 30, 30),
					TextSize = 22,
					Font = Enum.Font.GothamBold,
					ZIndex = 2,
					[React.Event.Activated] = onSubmit,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
				}),
			}),
		})
	elseif phase == "submitted" then
		content = e(WaitingScreen, {
			opponentName = nil,
		})
	elseif phase == "roundResult" then
		content = e(MatchScoreScreen, {
			targetColor = targetColor,
			myColor = submittedColor,
			myScore = myScore,
			opponentScore = opponentScore,
			myWins = myWins,
			opponentWins = opponentWins,
			opponentName = opponentName,
			roundsToWin = roundsToWin,
		})
	elseif phase == "matchEnd" then
		content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 20),
			}),

			Result = e("TextLabel", {
				Size = UDim2.fromOffset(600, 60),
				BackgroundTransparency = 1,
				Text = if matchWon then "You Win!" else "You Lose",
				TextColor3 = if matchWon
					then Color3.fromRGB(100, 255, 100)
					else Color3.fromRGB(255, 100, 100),
				TextSize = 52,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 1,
			}),

			Cash = matchWon and e("TextLabel", {
				Size = UDim2.fromOffset(400, 40),
				BackgroundTransparency = 1,
				Text = `+${cashEarned}`,
				TextColor3 = Color3.fromRGB(50, 255, 50),
				TextSize = 36,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 2,
			}),
		})
	end

	if not content then
		return nil
	end

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

			Content = content,
		}),
	})
end

return GameController
