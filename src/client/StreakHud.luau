-- StreakHud
-- Renders a BillboardGui above each player's head displaying their current
-- 1v1 win streak as a fire emoji + count. Streak data is replicated via the
-- "WinStreak" Player attribute, which the server keeps in sync with the
-- profile in ProfileService.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local StreakHud = {}

-- Distance-based scaling: BillboardGui's offset Size is constant screen pixels
-- by default, which makes the billboard look enormous when the camera is far
-- from the character. We adjust Size every render frame so that the billboard
-- shrinks with distance, like the character itself does.
local REFERENCE_DISTANCE = 18 -- studs — billboard renders at base size at this distance
local BASE_SIZE_X = 140
local BASE_SIZE_Y = 56
local MIN_SCALE = 0.25
local MAX_SCALE = 1.4

-- One entry per player whose streak we're currently rendering
type Entry = {
	billboard: BillboardGui,
	label: TextLabel,
	headConn: RBXScriptConnection?,
	renderConn: RBXScriptConnection?,
	head: BasePart,
}

local active: { [Player]: Entry } = {}

local function destroy(player: Player)
	local entry = active[player]
	if not entry then
		return
	end
	if entry.headConn then
		entry.headConn:Disconnect()
		entry.headConn = nil
	end
	if entry.renderConn then
		entry.renderConn:Disconnect()
		entry.renderConn = nil
	end
	if entry.billboard then
		entry.billboard:Destroy()
	end
	active[player] = nil
end

local function buildBillboard(head: BasePart, streak: number): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WinStreakHud"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(BASE_SIZE_X, BASE_SIZE_Y)
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
	-- If we already have a live billboard on the right head, just update text.
	if entry and entry.billboard.Parent and entry.billboard.Adornee == head then
		entry.label.Text = `🔥 {streak}`
		return
	end

	-- Otherwise (re)create. Old billboard is destroyed first if it existed.
	destroy(player)
	local bb, label = buildBillboard(head, streak)
	local entryRef: Entry
	entryRef = {
		billboard = bb,
		label = label,
		head = head,
		headConn = head.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				destroy(player)
			end
		end),
		renderConn = RunService.RenderStepped:Connect(function()
			if not bb.Parent then
				return
			end
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local distance = (camera.CFrame.Position - head.Position).Magnitude
			-- Larger billboard when far away would normally fight the point of
			-- "distance falloff", so we cap with REFERENCE_DISTANCE / distance:
			-- at the reference distance the scale is 1, getting closer makes it
			-- larger (capped) and farther makes it smaller (also capped).
			local scale = math.clamp(REFERENCE_DISTANCE / math.max(distance, 0.01), MIN_SCALE, MAX_SCALE)
			bb.Size = UDim2.fromOffset(BASE_SIZE_X * scale, BASE_SIZE_Y * scale)
		end),
	}
	active[player] = entryRef
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal("WinStreak"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function()
		-- Wait a frame for the Head to land before measuring.
		task.defer(function()
			refresh(player)
		end)
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
