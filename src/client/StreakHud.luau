-- StreakHud
-- Renders a BillboardGui above each player's head displaying their current
-- 1v1 win streak as a fire emoji + count. Streak data is replicated via the
-- "WinStreak" Player attribute, which the server keeps in sync with the
-- profile in ProfileService.

local Players = game:GetService("Players")

local StreakHud = {}

-- Studs-based size so the HUD scales with world distance like every other
-- billboard in the game (see MatchController:makePlayerBillboard). Pixel
-- sizing rendered proportionally huge on mobile because the same pixel
-- count covers a much smaller perceived world.
local SIZE_STUDS_X = 4
local SIZE_STUDS_Y = 1.6

type Entry = {
	billboard: BillboardGui,
	label: TextLabel,
	headConn: RBXScriptConnection?,
	head: BasePart,
}

local active: { [Player]: Entry } = {}

local function destroy(player: Player)
	local entry = active[player]
	if not entry then return end
	if entry.headConn then entry.headConn:Disconnect() end
	if entry.billboard then entry.billboard:Destroy() end
	active[player] = nil
end

local function buildBillboard(head: BasePart, streak: number): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WinStreakHud"
	bb.Adornee = head
	bb.Size = UDim2.new(SIZE_STUDS_X, 0, SIZE_STUDS_Y, 0)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = `🔥 {streak}`
	label.TextColor3 = Color3.fromRGB(255, 200, 80)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Transparency = 0
	stroke.Parent = label

	return bb, label
end

local function refresh(player: Player)
	local streak = tonumber(player:GetAttribute("WinStreak")) or 0
	local character = player.Character
	if streak <= 0 or not character then
		destroy(player)
		return
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		destroy(player)
		return
	end

	local entry = active[player]
	if entry and entry.billboard.Parent and entry.billboard.Adornee == head then
		entry.label.Text = `🔥 {streak}`
		return
	end

	destroy(player)
	local bb, label = buildBillboard(head, streak)
	local entryRef: Entry
	entryRef = {
		billboard = bb,
		label = label,
		head = head,
		headConn = head.AncestryChanged:Connect(function(_, parent)
			if parent == nil then destroy(player) end
		end),
	}
	active[player] = entryRef
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal("WinStreak"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(function() refresh(player) end)
	end)
	if player.Character then
		refresh(player)
	end
end

function StreakHud.Start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		destroy(player)
	end)
end

return StreakHud
