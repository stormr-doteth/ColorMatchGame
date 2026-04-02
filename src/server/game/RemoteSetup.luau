local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_NAMES = {
	"MatchStart",
	"RoundShowColor",
	"RoundGuessPhase",
	"SubmitGuess",
	"RoundResult",
	"MatchEnd",
	"LeaveTable",
	"PlayerSeated",
}

local RemoteSetup = {}

function RemoteSetup.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage

	for _, name in REMOTE_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
end

function RemoteSetup.Get(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
end

return RemoteSetup
