local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local computeScore = require(Shared:WaitForChild("computeScore"))
local Constants = require(Shared:WaitForChild("Constants"))
local ProfileService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("data"):WaitForChild("ProfileService"))

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

function MatchController.new(player1: Player, player2: Player, onComplete: () -> ())
	local self = setmetatable({}, MatchController)

	self.player1 = player1
	self.player2 = player2
	self.onComplete = onComplete

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

	return self
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
	getRemote("MatchStart"):FireClient(self.player1, {
		opponentName = self.player2.DisplayName,
		roundsToWin = Constants.ROUNDS_TO_WIN,
	})
	getRemote("MatchStart"):FireClient(self.player2, {
		opponentName = self.player1.DisplayName,
		roundsToWin = Constants.ROUNDS_TO_WIN,
	})

	-- Round 1 begins with a "Ready / Set / GO!" countdown on the clients.
	-- StartRound(true) sends the color immediately so the GO! frame can paint
	-- it as the background, then waits for both players to signal BeginRound
	-- before starting the show-duration timer.
	self:StartRound(true)
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

	ProfileService.AddCash(winner, Constants.WIN_REWARD)
	ProfileService.AddWin(winner)
	ProfileService.ResetStreak(loser)

	local winnerData = ProfileService.GetData(winner)
	local loserData = ProfileService.GetData(loser)

	local winnerIsP1 = winner == self.player1
	getRemote("MatchEnd"):FireClient(winner, {
		won = true,
		cashEarned = Constants.WIN_REWARD,
		totalWins = winnerData and winnerData.Wins or 0,
		roundHistory = self:BuildHistoryFor(if winnerIsP1 then 1 else 2),
	})
	getRemote("MatchEnd"):FireClient(loser, {
		won = false,
		cashEarned = 0,
		totalWins = loserData and loserData.Wins or 0,
		roundHistory = self:BuildHistoryFor(if winnerIsP1 then 2 else 1),
	})

	self:Cleanup()
end

function MatchController:PlayerDisconnected(player: Player)
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
	-- The disconnecting player's streak ends here, even though they're gone.
	ProfileService.ResetStreak(player)

	local winnerData = ProfileService.GetData(winner)

	if winner.Parent then
		local winnerIsP1 = winner == self.player1
		getRemote("MatchEnd"):FireClient(winner, {
			won = true,
			cashEarned = Constants.WIN_REWARD,
			totalWins = winnerData and winnerData.Wins or 0,
			roundHistory = self:BuildHistoryFor(if winnerIsP1 then 1 else 2),
		})
	end

	self:Cleanup()
end

function MatchController:Cleanup()
	self:DisconnectGuess()
	self:CancelThreads()
	if self.beginConnection then
		self.beginConnection:Disconnect()
		self.beginConnection = nil
	end
	if self.onComplete then
		task.defer(self.onComplete)
	end
end

return MatchController
