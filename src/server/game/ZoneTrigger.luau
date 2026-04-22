-- ZoneTrigger
-- Server-authoritative walk-up zone detection. The client cannot observe
-- workspace geometry reliably under StreamingEnabled, so we check each
-- player's HumanoidRootPart position against cached ring centers on the
-- server and fire RemoteEvents to open/close the matching UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ZoneTrigger = {}

local CHECK_INTERVAL = 0 -- every Heartbeat (~60 Hz). Cost is trivial for
-- a handful of zones + players; this removes ~50ms of perceptual latency.

type Zone = {
	id: string,
	centerX: number,
	centerZ: number,
	radiusSq: number,
	openRemote: RemoteEvent,
	closeRemote: RemoteEvent,
}

local zones: { Zone } = {}
-- wasInside[player][zoneId] = boolean
local wasInside: { [Player]: { [string]: boolean } } = {}

local function getRemote(name: string): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	return remotes:WaitForChild(name, 10) :: RemoteEvent
end

local function computeCenterRadius(inst: Instance): (number?, number?, number?)
	if inst:IsA("Model") then
		local cf, size = (inst :: Model):GetBoundingBox()
		local r = math.max(size.X, size.Z) * 0.5
		return cf.Position.X, cf.Position.Z, r * r
	elseif inst:IsA("BasePart") then
		local p = inst :: BasePart
		local r = math.max(p.Size.X, p.Size.Z) * 0.5
		return p.Position.X, p.Position.Z, r * r
	end
	return nil, nil, nil
end

local function registerZone(id: string, inst: Instance, openRemote: RemoteEvent, closeRemote: RemoteEvent)
	local cx, cz, rSq = computeCenterRadius(inst)
	if not cx or not cz or not rSq then
		warn(`[ZoneTrigger] Could not compute center/radius for {id}`)
		return
	end
	table.insert(zones, {
		id = id,
		centerX = cx,
		centerZ = cz,
		radiusSq = rSq,
		openRemote = openRemote,
		closeRemote = closeRemote,
	})
end

-- Match predicates for each zone. Returned true for the first matching
-- instance found during workspace scan or DescendantAdded.
local function isCosmeticRing(inst: Instance): boolean
	return inst.Name == "CosmeticRing" and (inst:IsA("Model") or inst:IsA("BasePart"))
end

local function isTreasureRing(inst: Instance): boolean
	if inst.Name ~= "TreasureRing" then return false end
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
	local parent = inst.Parent
	return parent ~= nil and (parent.Name == "groupChest" or parent.Name == "GroupChest")
end

local function resolveZone(id: string, predicate: (Instance) -> boolean, openRemote: RemoteEvent, closeRemote: RemoteEvent)
	for _, d in Workspace:GetDescendants() do
		if predicate(d) then
			registerZone(id, d, openRemote, closeRemote)
			return
		end
	end
	-- Not found yet — listen for it
	local conn
	conn = Workspace.DescendantAdded:Connect(function(inst)
		if predicate(inst) then
			conn:Disconnect()
			registerZone(id, inst, openRemote, closeRemote)
		end
	end)
end

local function checkPlayer(player: Player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local state = wasInside[player]
	if not state then return end

	if not hrp then
		-- Character gone (respawn/death): fire close for anything we had
		-- marked inside, and clear state so the next character spawn
		-- re-evaluates cleanly.
		for _, zone in zones do
			if state[zone.id] then
				zone.closeRemote:FireClient(player)
				state[zone.id] = false
			end
		end
		return
	end

	local px = (hrp :: BasePart).Position.X
	local pz = (hrp :: BasePart).Position.Z
	for _, zone in zones do
		local dx = px - zone.centerX
		local dz = pz - zone.centerZ
		local inside = (dx * dx + dz * dz) <= zone.radiusSq
		local prev = state[zone.id] == true
		if inside and not prev then
			zone.openRemote:FireClient(player)
			state[zone.id] = true
		elseif not inside and prev then
			zone.closeRemote:FireClient(player)
			state[zone.id] = false
		end
	end
end

function ZoneTrigger.Init()
	local openCos = getRemote("OpenCosmeticsShop")
	local closeCos = getRemote("CloseCosmeticsShop")
	local openRew = getRemote("OpenRewards")
	local closeRew = getRemote("CloseRewards")

	resolveZone("cosmetics", isCosmeticRing, openCos, closeCos)
	resolveZone("rewards", isTreasureRing, openRew, closeRew)

	local function onPlayer(player: Player)
		wasInside[player] = {}
		player.CharacterRemoving:Connect(function()
			-- Fire close events for any zone currently marked inside, then
			-- clear so the fresh character gets a clean false→true transition.
			local state = wasInside[player]
			if not state then return end
			for _, zone in zones do
				if state[zone.id] then
					zone.closeRemote:FireClient(player)
					state[zone.id] = false
				end
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end

	Players.PlayerRemoving:Connect(function(player)
		wasInside[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < CHECK_INTERVAL then return end
		accumulator = 0
		if #zones == 0 then return end
		for _, player in Players:GetPlayers() do
			checkPlayer(player)
		end
	end)
end

return ZoneTrigger
