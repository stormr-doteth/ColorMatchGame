local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local computeScore = require(Shared:WaitForChild("computeScore"))
local Constants = require(Shared:WaitForChild("Constants"))
local ProfileService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("data"):WaitForChild("ProfileService"))
local GamePassUtil = require(ServerScriptService:WaitForChild("Server"):WaitForChild("game"):WaitForChild("GamePassUtil"))
local WinsLeaderboard = require(ServerScriptService:WaitForChild("Server"):WaitForChild("game"):WaitForChild("WinsLeaderboard"))
local Analytics = require(ServerScriptService:WaitForChild("Server"):WaitForChild("game"):WaitForChild("Analytics"))

-- Lazy remote references (populated after RemoteSetup.Init)
local Remotes
local function getRemote(name: string): RemoteEvent
	if not Remotes then
		Remotes = ReplicatedStorage:WaitForChild("Remotes")
	end
	return Remotes:FindFirstChild(name)
end

local MatchController = {}
MatchController.__index = MatchController

function MatchController.new(player1: Player, player2: Player, onComplete: () -> (), tableModel: Model?, billboard: BillboardGui?)
	local self = setmetatable({}, MatchController)

	self.player1 = player1
	self.player2 = player2
	self.onComplete = onComplete
	self.tableModel = tableModel
	self.tableBillboard = billboard

	self.roundNumber = 0
	self.player1Wins = 0
	self.player2Wins = 0
	self.roundHistory = {} :: { any }

	self.targetH = 0
	self.targetS = 0
	self.targetV = 0

	self.player1Guess = nil :: { h: number, s: number, v: number }?
	self.player2Guess = nil :: { h: number, s: number, v: number }?

	self.phase = "idle"
	self.finished = false
	self.guessConnection = nil :: RBXScriptConnection?
	self.threads = {} :: { thread }
	self.resignConnections = {} :: { RBXScriptConnection }

	-- Table paper parts for spectators
	self.targetPaper = nil :: BasePart?
	self.player1Paper = nil :: BasePart?
	self.player2Paper = nil :: BasePart?
	self.previewConnection = nil :: RBXScriptConnection?

	-- Per-player score billboards above their heads
	self.p1Billboard = nil :: BillboardGui?
	self.p2Billboard = nil :: BillboardGui?
	self.p1WinsLabel = nil :: TextLabel?
	self.p2WinsLabel = nil :: TextLabel?
	self.p1Pips = {} :: { BasePart }
	self.p2Pips = {} :: { BasePart }
	self.pipDir1 = Vector3.zero
	self.pipDir2 = Vector3.zero
	self.pipTopY = 0
	self.pipBasePos1 = Vector3.zero
	self.pipBasePos2 = Vector3.zero

	return self
end

-- Create paper parts on the table surface so spectators can watch the match
function MatchController:CreatePapers()
	local model = self.tableModel
	if not model then return end

	local tablePart = model:FindFirstChild("Table")
	if not tablePart then return end

	local seat1 = model:FindFirstChild("Chair1") and model.Chair1:FindFirstChildWhichIsA("Seat", true)
	local seat2 = model:FindFirstChild("Chair2") and model.Chair2:FindFirstChildWhichIsA("Seat", true)
	if not seat1 or not seat2 then return end

	local tablePos = tablePart.Position
	local topY = tablePos.Y + tablePart.Size.Y / 2 + 0.02

	-- Direction from table center to each seat (horizontal only)
	local toSeat1 = (seat1.Position - tablePos) * Vector3.new(1, 0, 1)
	local toSeat2 = (seat2.Position - tablePos) * Vector3.new(1, 0, 1)
	local dir1 = toSeat1.Unit
	local dir2 = toSeat2.Unit

	local function makePaper(name: string, position: Vector3, size: Vector3): Part
		local paper = Instance.new("Part")
		paper.Name = name
		paper.Size = size
		paper.Position = position
		paper.Anchored = true
		paper.CanCollide = false
		paper.Color = Color3.fromRGB(255, 255, 255)
		paper.Material = Enum.Material.SmoothPlastic
		paper.TopSurface = Enum.SurfaceType.Smooth
		paper.BottomSurface = Enum.SurfaceType.Smooth
		paper.Parent = model
		return paper
	end

	-- Target paper in center
	self.targetPaper = makePaper(
		"TargetPaper",
		Vector3.new(tablePos.X, topY, tablePos.Z),
		Vector3.new(1.2, 0.05, 1.2)
	)

	-- Player papers offset toward their seats
	local offset = 1.2
	self.player1Paper = makePaper(
		"Player1Paper",
		Vector3.new(tablePos.X, topY, tablePos.Z) + dir1 * offset,
		Vector3.new(1.0, 0.05, 1.0)
	)
	self.player2Paper = makePaper(
		"Player2Paper",
		Vector3.new(tablePos.X, topY, tablePos.Z) + dir2 * offset,
		Vector3.new(1.0, 0.05, 1.0)
	)

	-- Tag the papers with the participant UserIds so the client can hide them
	-- locally for the two players in the match (anti-cheat: prevent peeking at
	-- the target color on the table surface). Spectators still see them.
	local p1Id = self.player1 and self.player1.UserId or 0
	local p2Id = self.player2 and self.player2.UserId or 0
	for _, paper in { self.targetPaper, self.player1Paper, self.player2Paper } do
		paper:SetAttribute("Participant1", p1Id)
		paper:SetAttribute("Participant2", p2Id)
	end

	-- Store directions and positions for pip placement
	self.pipDir1 = dir1
	self.pipDir2 = dir2
	self.pipTopY = topY
	self.pipBasePos1 = self.player1Paper.Position
	self.pipBasePos2 = self.player2Paper.Position

	-- Hide the table's default billboard during the match
	if self.tableBillboard then
		local playerCount = self.tableBillboard:FindFirstChild("PlayerCount")
		local reward = self.tableBillboard:FindFirstChild("Reward")
		if playerCount then playerCount.Visible = false end
		if reward then reward.Visible = false end
	end

	-- Per-player score billboards above their heads
	local function makePlayerBillboard(player: Player, winsCount: number)
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if not head then return nil, nil end

		local bb = Instance.new("BillboardGui")
		bb.Name = "MatchScoreBB"
		bb.Size = UDim2.new(4, 0, 1.2, 0)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop = false
		bb.LightInfluence = 0
		bb.MaxDistance = 50
		bb.Adornee = head
		bb.Parent = head

		local winsLabel = Instance.new("TextLabel")
		winsLabel.Name = "WinsLabel"
		winsLabel.Size = UDim2.fromScale(1, 1)
		winsLabel.BackgroundTransparency = 1
		winsLabel.Text = `{player.DisplayName}  ⭐ {winsCount}`
		winsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		winsLabel.TextScaled = true
		winsLabel.Font = Enum.Font.FredokaOne
		winsLabel.Parent = bb

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Parent = winsLabel

		return bb, winsLabel
	end

	self.p1Billboard, self.p1WinsLabel = makePlayerBillboard(self.player1, 0)
	self.p2Billboard, self.p2WinsLabel = makePlayerBillboard(self.player2, 0)

	-- Listen to GuessPreview remote for real-time paper color updates
	self.previewConnection = getRemote("GuessPreview").OnServerEvent:Connect(function(player, data)
		if typeof(data) ~= "table" then return end
		if self.finished or self.phase ~= "guessing" then return end
		local isPlayer1 = player == self.player1
		local isPlayer2 = player == self.player2
		if not isPlayer1 and not isPlayer2 then return end
		-- Once a player has submitted, their preview is locked in.
		if isPlayer1 and self.player1Guess ~= nil then return end
		if isPlayer2 and self.player2Guess ~= nil then return end

		local h = math.clamp(tonumber(data.h) or 0, 0, 1)
		local s = math.clamp(tonumber(data.s) or 0, 0, 1)
		local v = math.clamp(tonumber(data.v) or 0, 0, 1)
		local color = Color3.fromHSV(h, s, v)

		if isPlayer1 and self.player1Paper then
			self.player1Paper.Color = color
		elseif isPlayer2 and self.player2Paper then
			self.player2Paper.Color = color
		end
	end)
end

function MatchController:UpdateTargetPaper()
	if self.targetPaper then
		self.targetPaper.Color = Color3.fromHSV(self.targetH, self.targetS, self.targetV)
	end
end

function MatchController:UpdateScoreboard(roundWinner: number?)
	if self.p1WinsLabel then
		self.p1WinsLabel.Text = `{self.player1.DisplayName}  ⭐ {self.player1Wins}`
	end
	if self.p2WinsLabel then
		self.p2WinsLabel.Text = `{self.player2.DisplayName}  ⭐ {self.player2Wins}`
	end

	-- Add a win pip (small glowing circle) next to the winner's paper
	if roundWinner and roundWinner > 0 then
		local model = self.tableModel
		if not model then return end

		local pips = if roundWinner == 1 then self.p1Pips else self.p2Pips
		local basePos = if roundWinner == 1 then self.pipBasePos1 else self.pipBasePos2
		-- Cross direction: perpendicular to seat direction on the table surface
		local dir = if roundWinner == 1 then self.pipDir1 else self.pipDir2
		local cross = Vector3.new(dir.Z, 0, -dir.X) -- 90° rotation on horizontal plane

		-- Place pips in a row along the cross axis, offset from the paper
		local pipIndex = #pips
		local spacing = 0.35
		local totalWidth = (Constants.ROUNDS_TO_WIN - 1) * spacing
		local startOffset = -totalWidth / 2
		local pipPos = basePos + cross * (startOffset + pipIndex * spacing) + dir * 0.7

		local pip = Instance.new("Part")
		pip.Name = "WinPip"
		pip.Shape = Enum.PartType.Cylinder
		pip.Size = Vector3.new(0.05, 0.25, 0.25)
		-- Orient cylinder to face up (rotate 90° on Z)
		pip.CFrame = CFrame.new(pipPos) * CFrame.Angles(0, 0, math.rad(90))
		pip.Anchored = true
		pip.CanCollide = false
		pip.Color = Color3.fromRGB(255, 215, 0)
		pip.Material = Enum.Material.Neon
		pip.Parent = model
		table.insert(pips, pip)

		-- Flash the winning paper briefly
		local paper = if roundWinner == 1 then self.player1Paper else self.player2Paper
		if paper then
			task.spawn(function()
				local originalColor = paper.Color
				paper.Color = Color3.fromRGB(255, 215, 0)
				paper.Material = Enum.Material.Neon
				task.wait(0.5)
				paper.Color = originalColor
				paper.Material = Enum.Material.SmoothPlastic
			end)
		end
	end
end

function MatchController:ResetPapers()
	if self.player1Paper then
		self.player1Paper.Color = Color3.fromRGB(255, 255, 255)
	end
	if self.player2Paper then
		self.player2Paper.Color = Color3.fromRGB(255, 255, 255)
	end
end

function MatchController:DestroyPapers()
	if self.previewConnection then
		self.previewConnection:Disconnect()
		self.previewConnection = nil
	end

	if self.targetPaper then self.targetPaper:Destroy(); self.targetPaper = nil end
	if self.player1Paper then self.player1Paper:Destroy(); self.player1Paper = nil end
	if self.player2Paper then self.player2Paper:Destroy(); self.player2Paper = nil end

	-- Restore the table's default billboard
	if self.tableBillboard then
		local playerCount = self.tableBillboard:FindFirstChild("PlayerCount")
		local reward = self.tableBillboard:FindFirstChild("Reward")
		if playerCount then playerCount.Visible = true end
		if reward then reward.Visible = true end
	end

	-- Remove per-player score billboards
	if self.p1Billboard then self.p1Billboard:Destroy(); self.p1Billboard = nil end
	if self.p2Billboard then self.p2Billboard:Destroy(); self.p2Billboard = nil end
	self.p1WinsLabel = nil
	self.p2WinsLabel = nil

	-- Clean up win pips
	for _, pip in self.p1Pips do
		pip:Destroy()
	end
	for _, pip in self.p2Pips do
		pip:Destroy()
	end
	self.p1Pips = {}
	self.p2Pips = {}
end

-- Cancel all pending threads (timeouts, delays)
function MatchController:CancelThreads()
	for _, t in self.threads do
		pcall(task.cancel, t)
	end
	self.threads = {}
end

function MatchController:ScheduleDelay(seconds: number, callback: () -> ())
	local t = task.delay(seconds, function()
		if not self.finished then
			callback()
		end
	end)
	table.insert(self.threads, t)
end

function MatchController:Start()
	self:CreatePapers()

	getRemote("MatchStart"):FireClient(self.player1, {
		opponentName = self.player2.DisplayName,
		roundsToWin = Constants.ROUNDS_TO_WIN,
	})
	getRemote("MatchStart"):FireClient(self.player2, {
		opponentName = self.player1.DisplayName,
		roundsToWin = Constants.ROUNDS_TO_WIN,
	})

	Analytics.LogOnboarding(self.player1, 3, "MatchStarted")
	Analytics.LogOnboarding(self.player2, 3, "MatchStarted")
	Analytics.LogCustom(self.player1, "MatchStart", 1, { CustomField04 = self.player2.Name }, "1v1")
	Analytics.LogCustom(self.player2, "MatchStart", 1, { CustomField04 = self.player1.Name }, "1v1")

	self:ConnectResignHooks()

	-- Round 1 begins with a "Ready / Set / GO!" countdown on the clients.
	-- StartRound(true) sends the color immediately so the GO! frame can paint
	-- it as the background, then waits for both players to signal BeginRound
	-- before starting the show-duration timer.
	self:StartRound(true)
end

-- If a player dies or resets their character mid-match, treat it as a
-- resignation: the other player auto-wins and a notification is broadcast.
-- Disconnects (player leaving the server) are already handled by TableManager
-- via :PlayerDisconnected — we funnel both through :PlayerAbandoned.
function MatchController:ConnectResignHooks()
	local function hook(player: Player)
		local function watchCharacter(character: Model)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
				or character:WaitForChild("Humanoid", 5)
			if not humanoid then return end
			local conn
			conn = humanoid.Died:Connect(function()
				if conn then conn:Disconnect() end
				self:PlayerAbandoned(player)
			end)
			table.insert(self.resignConnections, conn)
		end

		-- Any new character during the match = reset = resignation.
		local charConn = player.CharacterAdded:Connect(function(character)
			self:PlayerAbandoned(player)
			watchCharacter(character)
		end)
		table.insert(self.resignConnections, charConn)

		if player.Character then
			watchCharacter(player.Character)
		end
	end

	hook(self.player1)
	hook(self.player2)
end

function MatchController:DisconnectResignHooks()
	for _, conn in self.resignConnections do
		conn:Disconnect()
	end
	self.resignConnections = {}
end

function MatchController:StartRound(waitForBegin: boolean?)
	if self.finished then
		return
	end

	-- Clean up any lingering state from previous round
	self:DisconnectGuess()
	self:CancelThreads()
	if self.beginConnection then
		self.beginConnection:Disconnect()
		self.beginConnection = nil
	end
	self.roundNumber += 1
	self.player1Guess = nil
	self.player2Guess = nil

	self.targetH = math.random()
	self.targetS = math.random()
	self.targetV = math.random()

	self:ResetPapers()
	self:UpdateTargetPaper()

	local colorData = {
		h = self.targetH,
		s = self.targetS,
		v = self.targetV,
		duration = Constants.SHOW_DURATION,
		roundNumber = self.roundNumber,
	}

	getRemote("RoundShowColor"):FireClient(self.player1, colorData)
	getRemote("RoundShowColor"):FireClient(self.player2, colorData)

	if waitForBegin then
		-- Wait until BOTH players' clients finish their countdown and fire
		-- BeginRound, then start the show timer. This keeps the two clients'
		-- timers in sync regardless of network jitter.
		self.phase = "showColorPending"
		local p1Ready = false
		local p2Ready = false
		self.beginConnection = getRemote("BeginRound").OnServerEvent:Connect(function(player)
			if self.phase ~= "showColorPending" then
				return
			end
			if player == self.player1 then
				p1Ready = true
			elseif player == self.player2 then
				p2Ready = true
			end
			if p1Ready and p2Ready then
				if self.beginConnection then
					self.beginConnection:Disconnect()
					self.beginConnection = nil
				end
				self.phase = "showing"
				self:ScheduleDelay(Constants.SHOW_DURATION, function()
					self:StartGuessing()
				end)
			end
		end)
		-- Safety fallback: if a client never signals (e.g. silently dropped
		-- the packet), still start the round after a generous delay so the
		-- match doesn't hang forever.
		self:ScheduleDelay(4, function()
			if self.phase == "showColorPending" then
				if self.beginConnection then
					self.beginConnection:Disconnect()
					self.beginConnection = nil
				end
				self.phase = "showing"
				self:ScheduleDelay(Constants.SHOW_DURATION, function()
					self:StartGuessing()
				end)
			end
		end)
	else
		self.phase = "showing"
		self:ScheduleDelay(Constants.SHOW_DURATION, function()
			self:StartGuessing()
		end)
	end
end

function MatchController:DisconnectGuess()
	if self.guessConnection then
		self.guessConnection:Disconnect()
		self.guessConnection = nil
	end
end

function MatchController:StartGuessing()
	if self.finished then
		return
	end

	self.phase = "guessing"
	self.player1Guess = nil
	self.player2Guess = nil

	getRemote("RoundGuessPhase"):FireClient(self.player1)
	getRemote("RoundGuessPhase"):FireClient(self.player2)

	-- Fresh connection for this round's guesses
	self:DisconnectGuess()
	self.guessConnection = getRemote("SubmitGuess").OnServerEvent:Connect(function(player, data)
		self:OnGuessReceived(player, data)
	end)

	-- Timeout: auto-submit score 0 for players who don't guess
	-- Server gives clients a small grace buffer beyond their visible timer
	-- so a late-arriving auto-submit still counts.
	self:ScheduleDelay(Constants.GUESS_TIMEOUT + 2, function()
		if self.phase == "guessing" then
			self:ProcessRoundResult()
		end
	end)
end

function MatchController:OnGuessReceived(player: Player, data: any)
	if self.finished or self.phase ~= "guessing" then
		return
	end

	local isPlayer1 = player == self.player1
	local isPlayer2 = player == self.player2
	if not isPlayer1 and not isPlayer2 then
		return
	end

	if isPlayer1 and self.player1Guess ~= nil then
		return
	end
	if isPlayer2 and self.player2Guess ~= nil then
		return
	end

	if typeof(data) ~= "table" then
		return
	end
	local guess = {
		h = math.clamp(tonumber(data.h) or 0, 0, 1),
		s = math.clamp(tonumber(data.s) or 0, 0, 1),
		v = math.clamp(tonumber(data.v) or 0, 0, 1),
	}

	if isPlayer1 then
		self.player1Guess = guess
	else
		self.player2Guess = guess
	end

	if self.player1Guess and self.player2Guess then
		self:ProcessRoundResult()
	end
end

function MatchController:ProcessRoundResult()
	if self.finished or self.phase ~= "guessing" then
		return
	end

	-- Immediately transition phase to prevent double-processing
	self.phase = "roundResult"

	-- Disconnect guess listener and cancel pending threads
	self:DisconnectGuess()
	self:CancelThreads()

	-- Compute scores
	local score1 = Constants.DEFAULT_GUESS_SCORE
	local score2 = Constants.DEFAULT_GUESS_SCORE

	if self.player1Guess then
		score1 = computeScore(
			self.targetH, self.targetS, self.targetV,
			self.player1Guess.h, self.player1Guess.s, self.player1Guess.v
		)
	end
	if self.player2Guess then
		score2 = computeScore(
			self.targetH, self.targetS, self.targetV,
			self.player2Guess.h, self.player2Guess.s, self.player2Guess.v
		)
	end

	local roundWinner = 0
	if score1 > score2 then
		self.player1Wins += 1
		roundWinner = 1
	elseif score2 > score1 then
		self.player2Wins += 1
		roundWinner = 2
	end

	self:UpdateScoreboard(roundWinner)

	-- Include opponent's guess color and both player IDs for the reveal screen
	local p1Guess = self.player1Guess or { h = 0, s = 0, v = 0 }
	local p2Guess = self.player2Guess or { h = 0, s = 0, v = 0 }

	-- Record this round in history (used for end-of-match recap)
	table.insert(self.roundHistory, {
		target = { h = self.targetH, s = self.targetS, v = self.targetV },
		p1Guess = self.player1Guess,
		p2Guess = self.player2Guess,
		p1Score = score1,
		p2Score = score2,
		winner = roundWinner,
	})

	getRemote("RoundResult"):FireClient(self.player1, {
		myScore = score1,
		opponentScore = score2,
		myTotalWins = self.player1Wins,
		opponentTotalWins = self.player2Wins,
		targetH = self.targetH,
		targetS = self.targetS,
		targetV = self.targetV,
		opponentGuessH = p2Guess.h,
		opponentGuessS = p2Guess.s,
		opponentGuessV = p2Guess.v,
		myUserId = self.player1.UserId,
		opponentUserId = self.player2.UserId,
	})
	getRemote("RoundResult"):FireClient(self.player2, {
		myScore = score2,
		opponentScore = score1,
		myTotalWins = self.player2Wins,
		opponentTotalWins = self.player1Wins,
		targetH = self.targetH,
		targetS = self.targetS,
		targetV = self.targetV,
		opponentGuessH = p1Guess.h,
		opponentGuessS = p1Guess.s,
		opponentGuessV = p1Guess.v,
		myUserId = self.player2.UserId,
		opponentUserId = self.player1.UserId,
	})

	-- After result display, check for winner or start next round
	self:ScheduleDelay(Constants.RESULT_DISPLAY_TIME, function()
		if self.player1Wins >= Constants.ROUNDS_TO_WIN then
			self:EndMatch(self.player1, self.player2)
		elseif self.player2Wins >= Constants.ROUNDS_TO_WIN then
			self:EndMatch(self.player2, self.player1)
		else
			self:StartRound()
		end
	end)
end

-- Build a per-player view of the round history (perspective = playerIndex 1 or 2)
function MatchController:BuildHistoryFor(playerIndex: number): { any }
	local view = {}
	for _, entry in self.roundHistory do
		local myGuess, oppGuess, myScore, oppScore
		if playerIndex == 1 then
			myGuess = entry.p1Guess
			oppGuess = entry.p2Guess
			myScore = entry.p1Score
			oppScore = entry.p2Score
		else
			myGuess = entry.p2Guess
			oppGuess = entry.p1Guess
			myScore = entry.p2Score
			oppScore = entry.p1Score
		end
		local outcome
		if entry.winner == 0 then
			outcome = "tie"
		elseif entry.winner == playerIndex then
			outcome = "win"
		else
			outcome = "loss"
		end
		table.insert(view, {
			target = entry.target,
			myGuess = myGuess,
			opponentGuess = oppGuess,
			myScore = myScore,
			opponentScore = oppScore,
			outcome = outcome,
		})
	end
	return view
end

function MatchController:EndMatch(winner: Player, loser: Player)
	if self.finished then
		return
	end
	self.finished = true
	self.phase = "finished"

	-- Calculate cash reward with game pass multipliers
	local cashReward = Constants.WIN_REWARD
	local cashMult = 1
	if GamePassUtil.HasPass(winner, "VIP") then
		cashMult *= 1.5
	end
	local doubledCash = GamePassUtil.HasPass(winner, "DOUBLE_CASH")
	if doubledCash then
		cashMult *= 2
	end
	cashReward = math.floor(cashReward * cashMult)
	ProfileService.AddCash(winner, cashReward)
	Analytics.LogEconomy(winner, "Source", "Cash", cashReward, "Gameplay", "match_win", "1v1")
	-- Fire floater when any cash boost is active. Pass the effective multiplier
	-- so the client can render "+N x3!" when VIP + 2x Cash stack.
	if cashMult > 1 then
		local r = getRemote("BoostAwarded")
		if r then r:FireClient(winner, "DOUBLE_CASH", cashReward, cashMult) end
	end

	-- Win count (doubled by 2x Wins pass). Use AddWins for the bonus so the
	-- streak only increments once — the DOUBLE_WINS pass is a win-count boost,
	-- not a streak boost. Streak stacking lives under DOUBLE_STREAK below.
	ProfileService.AddWin(winner)
	if GamePassUtil.HasPass(winner, "DOUBLE_WINS") then
		ProfileService.AddWins(winner, 1)
		local r = getRemote("BoostAwarded")
		if r then r:FireClient(winner, "DOUBLE_WINS", 1) end
	end

	-- Streak bonus from 2x Streak pass (AddWin already incremented by 1)
	if GamePassUtil.HasPass(winner, "DOUBLE_STREAK") then
		local data = ProfileService.GetData(winner)
		if data then
			data.WinStreak = (data.WinStreak or 0) + 1
		end
		local r = getRemote("BoostAwarded")
		if r then r:FireClient(winner, "DOUBLE_STREAK", 1) end
	end

	ProfileService.ResetStreak(loser)

	-- Sync to global leaderboards after all wins/streak mutations.
	local winnerDataForLB = ProfileService.GetData(winner)
	if winnerDataForLB then
		WinsLeaderboard.Record(winner, winnerDataForLB.Wins or 0)
		WinsLeaderboard.RecordStreak(winner, winnerDataForLB.WinStreak or 0)
	end
	WinsLeaderboard.RecordStreak(loser, 0)

	-- Streak milestone bonuses
	local winnerStreak = 0
	local wData = ProfileService.GetData(winner)
	if wData then winnerStreak = wData.WinStreak or 0 end

	local STREAK_MILESTONES = {
		[3]  = 25,
		[5]  = 50,
		[10] = 150,
		[15] = 250,
		[25] = 500,
		[50] = 1500,
	}

	local streakBonus = STREAK_MILESTONES[winnerStreak]
	if streakBonus then
		ProfileService.AddCash(winner, streakBonus)
		cashReward += streakBonus
		getRemote("ShowNotification"):FireClient(winner, `{winnerStreak} Win Streak! +${streakBonus} bonus!`)
	end

	local winnerData = ProfileService.GetData(winner)
	local loserData = ProfileService.GetData(loser)

	local winnerIsP1 = winner == self.player1
	local winsAwarded = if GamePassUtil.HasPass(winner, "DOUBLE_WINS") then 2 else 1
	getRemote("MatchEnd"):FireClient(winner, {
		won = true,
		cashEarned = cashReward,
		cashMultiplier = cashMult,
		winsAwarded = winsAwarded,
		totalWins = winnerData and winnerData.Wins or 0,
		roundHistory = self:BuildHistoryFor(if winnerIsP1 then 1 else 2),
	})
	getRemote("MatchEnd"):FireClient(loser, {
		won = false,
		cashEarned = 0,
		totalWins = loserData and loserData.Wins or 0,
		roundHistory = self:BuildHistoryFor(if winnerIsP1 then 2 else 1),
	})

	-- Analytics: per-match custom event for both players, plus onboarding
	-- "first match won" step for the winner.
	Analytics.LogCustom(winner, "MatchEnd", cashReward, {
		CustomField04 = "win",
		CustomField05 = tostring(self.roundNumber),
		CustomField06 = tostring(winnerData and winnerData.WinStreak or 0),
	}, "1v1")
	Analytics.LogCustom(loser, "MatchEnd", 0, {
		CustomField04 = "loss",
		CustomField05 = tostring(self.roundNumber),
	}, "1v1")
	Analytics.LogOnboarding(winner, 4, "FirstMatchWon")

	self:Cleanup()
end

-- Backwards-compat shim used by TableManager's LeaveTable / PlayerRemoving.
function MatchController:PlayerDisconnected(player: Player)
	self:PlayerAbandoned(player)
end

-- Unified abandonment: awards the remaining player the win and broadcasts a
-- "<name> abandoned the match!" notification. Idempotent — safe to fire from
-- multiple hooks (Humanoid.Died, CharacterAdded, PlayerRemoving, LeaveTable).
function MatchController:PlayerAbandoned(player: Player)
	if self.finished then
		return
	end

	local winner
	if player == self.player1 then
		winner = self.player2
	elseif player == self.player2 then
		winner = self.player1
	else
		return
	end

	self.finished = true
	self.phase = "finished"

	ProfileService.AddCash(winner, Constants.WIN_REWARD)
	ProfileService.AddWin(winner)
	ProfileService.ResetStreak(player)

	local abandonerName = player.DisplayName
	local notifyRemote = getRemote("ShowNotification")
	if notifyRemote and winner.Parent then
		notifyRemote:FireClient(winner, `{abandonerName} abandoned the match!`)
	end

	local winnerData = ProfileService.GetData(winner)

	if winnerData then
		WinsLeaderboard.Record(winner, winnerData.Wins or 0)
		WinsLeaderboard.RecordStreak(winner, winnerData.WinStreak or 0)
	end
	WinsLeaderboard.RecordStreak(player, 0)

	if winner.Parent then
		local winnerIsP1 = winner == self.player1
		getRemote("MatchEnd"):FireClient(winner, {
			won = true,
			cashEarned = Constants.WIN_REWARD,
			totalWins = winnerData and winnerData.Wins or 0,
			roundHistory = self:BuildHistoryFor(if winnerIsP1 then 1 else 2),
			abandoned = true,
			abandonerName = abandonerName,
		})
	end

	self:Cleanup()
end

function MatchController:Cleanup()
	self:DisconnectGuess()
	self:DisconnectResignHooks()
	self:CancelThreads()
	self:DestroyPapers()
	if self.beginConnection then
		self.beginConnection:Disconnect()
		self.beginConnection = nil
	end
	if self.onComplete then
		task.defer(self.onComplete)
	end
end

return MatchController
