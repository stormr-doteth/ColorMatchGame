-- VipChatTag (client)
-- Adds a gold "[VIP]" prefix to chat messages from players with the VIP pass.
-- Reads the `HasVIP` attribute set by the server's VipChatTag module.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local VipChatTag = {}

local VIP_PREFIX = '<font color="#FFD700"><b>[VIP]</b></font> '

function VipChatTag.Start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")

		local source = message.TextSource
		if not source then return props end

		local player = Players:GetPlayerByUserId(source.UserId)
		if not player then return props end

		if player:GetAttribute("HasVIP") == true then
			local existingPrefix = message.PrefixText ~= "" and message.PrefixText or player.DisplayName .. ":"
			props.PrefixText = VIP_PREFIX .. existingPrefix
		end

		return props
	end
end

return VipChatTag
