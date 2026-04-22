-- MatchPaperHider
-- Anti-cheat: the server spawns TargetPaper / Player1Paper / Player2Paper on
-- table surfaces during a 1v1 match. The parts are meant to show spectators
-- what's happening, but if either participant tilts their camera down they
-- can read the target color off the table and bypass the memory game.
--
-- This client module watches for those paper parts, reads the Participant1 /
-- Participant2 attributes, and makes them locally invisible for the two
-- players in the match. Everyone else still sees them normally.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MatchPaperHider = {}

local PAPER_NAMES = {
	TargetPaper = true,
	Player1Paper = true,
	Player2Paper = true,
}

local localPlayer = Players.LocalPlayer

local function applyVisibility(part: BasePart)
	local p1 = part:GetAttribute("Participant1")
	local p2 = part:GetAttribute("Participant2")
	local hide = (p1 == localPlayer.UserId) or (p2 == localPlayer.UserId)
	part.LocalTransparencyModifier = if hide then 1 else 0
end

local function hook(part: BasePart)
	applyVisibility(part)
	part:GetAttributeChangedSignal("Participant1"):Connect(function()
		applyVisibility(part)
	end)
	part:GetAttributeChangedSignal("Participant2"):Connect(function()
		applyVisibility(part)
	end)
end

function MatchPaperHider.Start()
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("BasePart") and PAPER_NAMES[inst.Name] then
			hook(inst)
		end
	end
	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") and PAPER_NAMES[inst.Name] then
			hook(inst)
		end
	end)
end

return MatchPaperHider
