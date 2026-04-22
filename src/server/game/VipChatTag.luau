-- VipChatTag
-- Marks each player with a `HasVIP` attribute that the client chat handler
-- reads to add a "[VIP]" prefix to their chat messages.

local Players = game:GetService("Players")

local GamePassUtil = require(script.Parent:WaitForChild("GamePassUtil"))

local VipChatTag = {}

local function refresh(player: Player)
	local ok, owns = pcall(function()
		return GamePassUtil.HasPass(player, "VIP")
	end)
	player:SetAttribute("HasVIP", ok and owns or false)
end

function VipChatTag.Init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(refresh, player)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(refresh, p)
	end
end

function VipChatTag.Refresh(player: Player)
	task.spawn(refresh, player)
end

return VipChatTag
