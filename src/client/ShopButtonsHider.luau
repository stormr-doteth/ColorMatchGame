-- ShopButtonsHider
-- Tweens the left-edge ShopButtons column and right-edge IngameAds column
-- offscreen while the player is in a match, then back in when the match ends
-- OR when they leave early via the solo X button. MatchStart / MatchEnd are
-- handled automatically here; for LeaveTable-style exits the consumer should
-- call ShopButtonsHider.Show() after firing the remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ShopButtonsHider = {}

local TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OFFSCREEN_OFFSET = 260

type Tracked = {
	frame: GuiObject,
	originalPos: UDim2,
	hiddenPos: UDim2,
}

local tracked: { Tracked } = {}

local function findInAllScreenGuis(playerGui: PlayerGui, name: string): GuiObject?
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") then
			local f = gui:FindFirstChild(name)
			if f and f:IsA("GuiObject") then
				return f
			end
		end
	end
	return nil
end

local function track(frame: GuiObject, direction: number)
	local originalPos = frame.Position
	local hiddenPos = UDim2.new(
		originalPos.X.Scale,
		originalPos.X.Offset + OFFSCREEN_OFFSET * direction,
		originalPos.Y.Scale,
		originalPos.Y.Offset
	)
	table.insert(tracked, {
		frame = frame,
		originalPos = originalPos,
		hiddenPos = hiddenPos,
	})
end

function ShopButtonsHider.Hide()
	for _, t in tracked do
		TweenService:Create(t.frame, TWEEN, { Position = t.hiddenPos }):Play()
	end
end

function ShopButtonsHider.Show()
	for _, t in tracked do
		t.frame.Visible = true
		TweenService:Create(t.frame, TWEEN, { Position = t.originalPos }):Play()
	end
end

function ShopButtonsHider.Start()
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

		-- Wait for both frames (let init.client reparent them first).
		local shopButtons: GuiObject? = nil
		local ingameAds: GuiObject? = nil
		local deadline = os.clock() + 10
		while os.clock() < deadline do
			shopButtons = shopButtons or findInAllScreenGuis(playerGui, "ShopButtons")
			ingameAds = ingameAds or findInAllScreenGuis(playerGui, "IngameAds")
			if shopButtons and ingameAds then break end
			task.wait(0.25)
		end

		if shopButtons then track(shopButtons, -1) end -- slides left
		if ingameAds then track(ingameAds, 1) end       -- slides right

		if #tracked == 0 then return end

		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local matchStart = remotes:WaitForChild("MatchStart")
		local matchEnd = remotes:WaitForChild("MatchEnd");

		(matchStart :: RemoteEvent).OnClientEvent:Connect(ShopButtonsHider.Hide)
		;(matchEnd :: RemoteEvent).OnClientEvent:Connect(ShopButtonsHider.Show)
	end)
end

return ShopButtonsHider
