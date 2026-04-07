local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local computeScore = require(Shared:WaitForChild("computeScore"))
local Constants = require(Shared:WaitForChild("Constants"))

-- Lazy remote references
local Remotes
local function getRemote(name: string): RemoteEvent
	if not Remotes then
		Remotes = ReplicatedStorage:WaitForChild("Remotes")
	end
	return Remotes:FindFirstChild(name)
end

local SoloMatchController = {}
SoloMatchController.__index = SoloMatchController

function SoloMatchController.new(player: Player, onComplete: () -> ())
	local self = setmetatable({}, SoloMatchController)

	self.player = player
	self.onComplete = onComplete

	self.roundNumber = 0
	self.totalRounds = Constants.SOLO_ROUNDS
	self.scores = {} -- array of scores per round
	self.roundHistory = {} :: { any }

	self.targetH = 0
	self.targetS = 0
	self.targetV = 0

	self.guess = nil :: { h: number, s: number, v: number }?

	self.phase = "idle"
	self.finished = false
	self.guessConnection = nil :: RBXScriptConnection?
	self.threads = {} :: { thread }

	return self
end

function SoloMatchController:CancelThreads()
	for _, t in self.threads do
		pcall(task.cancel, t)
	end
	self.threads = {}
end

function SoloMatchController:ScheduleDelay(seconds: number, callback: () -> ())
	local t = task.delay(seconds, function()
		if not self.finished then
			callback()
		end
	end)
	table.insert(self.threads, t)
end

function SoloMatchController:DisconnectGuess()
	if self.guessConnection then
		self.guessConnection:Disconnect()
		self.guessConnection = nil
	end
end

function SoloMatchController:Start()
	-- Tell client a solo match is starting
	getRemote("MatchStart"):FireClient(self.player, {
		opponentName = "",
		roundsToWin = self.totalRounds,
		solo = true,
		totalRounds = self.totalRounds,
	})

	task.wait(0.5)
	self:StartRound()
end

function SoloMatchController:StartRound()
	if self.finished then
		return
	end

	self:DisconnectGuess()
	self:CancelThreads()

	self.roundNumber += 1
	self.guess = nil

	self.targetH = math.random()
	self.targetS = math.random()
	self.targetV = math.random()

	self.phase = "showing"

	getRemote("RoundShowColor"):FireClient(self.player, {
		h = self.targetH,
		s = self.targetS,
		v = self.targetV,
		duration = Constants.SHOW_DURATION,
		roundNumber = self.roundNumber,
	})

	self:ScheduleDelay(Constants.SHOW_DURATION, function()
		self:StartGuessing()
	end)
end

function SoloMatchController:StartGuessing()
	if self.finished then
		return
	end

	self.phase = "guessing"
	self.guess = nil

	getRemote("RoundGuessPhase"):FireClient(self.player)

	self:DisconnectGuess()
	self.guessConnection = getRemote("SubmitGuess").OnServerEvent:Connect(function(player, data)
		if player == self.player then
			self:OnGuessReceived(data)
		end
	end)

	-- Server gives clients a small grace buffer beyond their visible timer
	-- so a late-arriving auto-submit still counts.
	self:ScheduleDelay(Constants.GUESS_TIMEOUT + 2, function()
		if self.phase == "guessing" then
			self:ProcessRoundResult()
		end
	end)
end

function SoloMatchController:OnGuessReceived(data: any)
	if self.finished or self.phase ~= "guessing" then
		return
	end

	if self.guess ~= nil then
		return
	end

	if typeof(data) ~= "table" then
		return
	end

	self.guess = {
		h = math.clamp(tonumber(data.h) or 0, 0, 1),
		s = math.clamp(tonumber(data.s) or 0, 0, 1),
		v = math.clamp(tonumber(data.v) or 0, 0, 1),
	}

	self:ProcessRoundResult()
end

function SoloMatchController:ProcessRoundResult()
	if self.finished or self.phase ~= "guessing" then
		return
	end

	self.phase = "roundResult"
	self:DisconnectGuess()
	self:CancelThreads()

	local score = Constants.DEFAULT_GUESS_SCORE
	if self.guess then
		score = computeScore(
			self.targetH, self.targetS, self.targetV,
			self.guess.h, self.guess.s, self.guess.v
		)
	end

	table.insert(self.scores, score)
	table.insert(self.roundHistory, {
		target = { h = self.targetH, s = self.targetS, v = self.targetV },
		myGuess = self.guess,
		myScore = score,
		outcome = "solo",
	})

	-- Send result — solo uses myScore only, opponentScore = 0
	getRemote("RoundResult"):FireClient(self.player, {
		myScore = score,
		opponentScore = 0,
		myTotalWins = self.roundNumber,
		opponentTotalWins = self.totalRounds,
		targetH = self.targetH,
		targetS = self.targetS,
		targetV = self.targetV,
		solo = true,
		roundNumber = self.roundNumber,
		totalRounds = self.totalRounds,
	})

	-- Check if this was the last round
	if self.roundNumber >= self.totalRounds then
		self:ScheduleDelay(2, function()
			self:EndMatch()
		end)
		return
	end

	-- Wait for player to click Next
	self.phase = "waitingNext"
	self.nextConnection = getRemote("NextRound").OnServerEvent:Connect(function(player)
		if player == self.player and self.phase == "waitingNext" then
			if self.nextConnection then
				self.nextConnection:Disconnect()
				self.nextConnection = nil
			end
			self:StartRound()
		end
	end)

	-- Auto-advance fallback after 30 seconds
	self:ScheduleDelay(30, function()
		if self.phase == "waitingNext" then
			if self.nextConnection then
				self.nextConnection:Disconnect()
				self.nextConnection = nil
			end
			self:StartRound()
		end
	end)
end

function SoloMatchController:EndMatch()
	if self.finished then
		return
	end
	self.finished = true
	self.phase = "finished"

	-- Compute average accuracy
	local total = 0
	for _, s in self.scores do
		total += s
	end
	local average = math.floor(total / #self.scores + 0.5)

	-- Find best round
	local best = 0
	for _, s in self.scores do
		if s > best then
			best = s
		end
	end

	getRemote("MatchEnd"):FireClient(self.player, {
		won = true,
		cashEarned = 0,
		solo = true,
		averageScore = average,
		bestScore = best,
		scores = self.scores,
		totalRounds = self.totalRounds,
		roundHistory = self.roundHistory,
	})

	self:Cleanup()
end

function SoloMatchController:PlayerDisconnected()
	if self.finished then
		return
	end
	self.finished = true
	self.phase = "finished"
	self:Cleanup()
end

function SoloMatchController:Cleanup()
	self:DisconnectGuess()
	self:CancelThreads()
	if self.nextConnection then
		self.nextConnection:Disconnect()
		self.nextConnection = nil
	end

	if self.onComplete then
		task.defer(self.onComplete)
	end
end

return SoloMatchController
