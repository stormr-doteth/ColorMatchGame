-- CosmeticAnimations
-- Client-side Heartbeat loop that animates orbiting parts on cosmetic
-- thrones and lucky block display models. These parts are Anchored
-- visual-only decorations; running this on the client avoids server
-- replication cost that a server-side animator would incur.
--
-- Registered animations are keyed by model name. Each rig describes
-- the parts to move and the motion parameters. Missing models are
-- silently skipped — they may be streamed out or not yet loaded.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Rig = {
	modelName: string,
	center: Vector3, -- world-space center for orbits
	build: (model: Instance) -> () -> (),
}

local function orbitRig(opts: {
	modelName: string,
	centerOffset: Vector3, -- from model pivot
	partPrefix: string,
	count: number,
	radius: number,
	radiusJitter: number?,
	bobAmp: number,
	bobSpeed: number,
	rotSpeed: number,
	spinSpeed: number?,
	extraSpin: boolean?,
	extras: ((model: Instance, t: number) -> ())?,
})
	return {
		modelName = opts.modelName,
		build = function(model)
			local pivot = model:GetPivot()
			local center = pivot.Position + opts.centerOffset
			local parts = {}
			for i = 1, opts.count do
				local p = model:FindFirstChild(opts.partPrefix .. i)
				if p then
					table.insert(parts, { part = p, phase = (i - 1) * (math.pi * 2 / opts.count) })
				end
			end
			return function(t)
				for _, o in parts do
					local a = o.phase + t * opts.rotSpeed
					local r = opts.radius
					if opts.radiusJitter then
						r = r + math.sin(t * opts.bobSpeed + o.phase) * opts.radiusJitter
					end
					local y = center.Y + math.sin(t * opts.bobSpeed + o.phase) * opts.bobAmp
					local pos = Vector3.new(center.X + math.cos(a) * r, y, center.Z + math.sin(a) * r)
					local cf = CFrame.new(pos)
					if opts.spinSpeed then
						cf = cf * CFrame.Angles(t * opts.spinSpeed, -a, 0)
					end
					o.part.CFrame = cf
				end
				if opts.extras then
					opts.extras(model, t)
				end
			end
		end,
	}
end

local rigs = {
	-- Prismatic thrones + block
	{
		modelName = "PrismLordThrone",
		build = function(model)
			local core = model:FindFirstChild("PrismGem")
			local corePos = core and core.Position
			local center = corePos or (model:GetPivot().Position + Vector3.new(0, 3.2, 0.6))
			local gems = {}
			for i = 1, 8 do
				local g = model:FindFirstChild("OrbitGem" .. i)
				if g then
					table.insert(gems, { part = g, phase = (i - 1) * (math.pi * 2 / 8) })
				end
			end
			return function(t)
				for _, o in gems do
					local a = o.phase + t * 0.6
					local y = center.Y + math.sin(t * 1.5 + o.phase) * 0.35
					local pos = Vector3.new(center.X + math.cos(a) * 2.8, y, center.Z + math.sin(a) * 2.8)
					o.part.CFrame = CFrame.new(pos)
						* CFrame.Angles(0, -a, math.rad(45))
						* CFrame.Angles(t * 2, 0, 0)
				end
				if core and corePos then
					local y = corePos.Y + math.sin(t * 0.8) * 0.2
					core.CFrame = CFrame.new(corePos.X, y, corePos.Z) * CFrame.Angles(0, t * 0.4, math.rad(45))
				end
			end
		end,
	},
	{
		modelName = "PrismaticLuckyBlock",
		build = function(model)
			local cube = model:FindFirstChild("Cube")
			local cubePos = cube and cube.Position
			local center = cubePos or model:GetPivot().Position
			local orbs = {}
			for i = 1, 8 do
				local o = model:FindFirstChild("Orb" .. i)
				if o then
					table.insert(orbs, { part = o, phase = (i - 1) * (math.pi * 2 / 8) })
				end
			end
			return function(t)
				for _, o in orbs do
					local a = o.phase + t * 0.5
					local y = center.Y + math.sin(t * 1.8 + o.phase) * 0.6
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 3.4, y, center.Z + math.sin(a) * 3.4)
				end
				if cube and cubePos then
					cube.CFrame = CFrame.new(cubePos) * CFrame.Angles(t * 0.3, t * 0.5, 0)
				end
			end
		end,
	},
	{
		modelName = "CrystalCoreThrone",
		build = function(model)
			local core = model:FindFirstChild("Core")
			local corePos = core and core.Position
			local center = corePos or model:GetPivot().Position
			local shards = {}
			for i = 1, 4 do
				local s = model:FindFirstChild("Shard" .. i)
				if s then
					table.insert(shards, { part = s, phase = (i - 1) * (math.pi / 2) })
				end
			end
			return function(t)
				for _, o in shards do
					local a = o.phase + t * 0.8
					local y = center.Y + math.sin(t * 1.5 + o.phase) * 0.25
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 1.3, y, center.Z + math.sin(a) * 1.3)
						* CFrame.Angles(math.rad(30), -a, 0)
				end
				if core and corePos then
					local y = corePos.Y + math.sin(t * 1.2) * 0.15
					core.CFrame = CFrame.new(corePos.X, y, corePos.Z) * CFrame.Angles(t * 0.5, t * 0.7, math.rad(45))
				end
			end
		end,
	},

	-- Cosmic thrones + block
	{
		modelName = "EventHorizonThrone",
		build = function(model)
			local disk = model:FindFirstChild("WarpDisk")
			local acc = model:FindFirstChild("Accretion")
			local diskPos = disk and disk.Position
			local center = diskPos or model:GetPivot().Position
			local debris = {}
			for i = 1, 6 do
				local d = model:FindFirstChild("Debris" .. i)
				if d then
					table.insert(debris, { part = d, phase = (i - 1) * (math.pi * 2 / 6) })
				end
			end
			return function(t)
				for _, o in debris do
					local loopT = ((t * 0.25) + o.phase / (math.pi * 2)) % 1
					local r = (1 - loopT) * 2.5 + 0.3
					local a = o.phase + t * 1.2
					o.part.CFrame = CFrame.new(
						center.X + math.cos(a) * r,
						center.Y + math.sin(a * 2) * 0.2,
						center.Z + math.sin(a) * r
					) * CFrame.Angles(t * 2, t * 1.5, 0)
				end
				if disk and diskPos then
					disk.CFrame = CFrame.new(diskPos)
						* CFrame.Angles(0, t * 0.8, 0)
						* CFrame.Angles(0, 0, math.rad(90))
				end
				if acc and diskPos then
					acc.CFrame = CFrame.new(diskPos)
						* CFrame.Angles(math.rad(20), t * 1.5, 0)
						* CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end,
	},
	{
		modelName = "StarbornThrone",
		build = function(model)
			local center = model:GetPivot().Position + Vector3.new(0, 5.8, -0.5)
			local stars = {}
			for i = 1, 6 do
				local s = model:FindFirstChild("OrbitStar" .. i)
				if s then
					table.insert(stars, { part = s, phase = (i - 1) * (math.pi * 2 / 6) })
				end
			end
			return function(t)
				for _, o in stars do
					local a = o.phase + t * 0.4
					local y = center.Y + math.sin(t * 1.1 + o.phase) * 0.35
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 2, y, center.Z + math.sin(a) * 2)
				end
			end
		end,
	},
	{
		modelName = "BlackHoleKingThrone",
		build = function(model)
			local sing = model:FindFirstChild("Singularity")
			local acc = model:FindFirstChild("Accretion")
			local singPos = sing and sing.Position
			local center = singPos or model:GetPivot().Position
			local chunks = {}
			for i = 1, 8 do
				local c = model:FindFirstChild("Chunk" .. i)
				if c then
					table.insert(chunks, { part = c, phase = (i - 1) * (math.pi * 2 / 8) })
				end
			end
			return function(t)
				for _, o in chunks do
					local a = o.phase + t * 1.5
					local r = 2.3 + math.sin(t * 0.8 + o.phase) * 0.4
					o.part.CFrame = CFrame.new(
						center.X + math.cos(a) * r,
						center.Y + math.sin(a * 2) * 0.4,
						center.Z + math.sin(a) * r
					) * CFrame.Angles(t * 3, t * 2, 0)
				end
				if sing and singPos then
					sing.CFrame = CFrame.new(singPos) * CFrame.Angles(0, t * 0.5, 0)
				end
				if acc and singPos then
					acc.CFrame = CFrame.new(singPos)
						* CFrame.Angles(math.rad(20), t * 2.5, 0)
						* CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end,
	},
	{
		modelName = "CosmicLuckyBlock",
		build = function(model)
			local cube = model:FindFirstChild("Cube")
			local cubePos = cube and cube.Position
			local center = cubePos or model:GetPivot().Position
			local planets = {}
			for i = 1, 6 do
				local p = model:FindFirstChild("Planet" .. i)
				if p then
					table.insert(planets, { part = p, phase = (i - 1) * (math.pi * 2 / 6) })
				end
			end
			return function(t)
				for _, o in planets do
					local a = o.phase + t * 0.8
					local y = center.Y + math.sin(t * 1.2 + o.phase) * 0.8
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 3.6, y, center.Z + math.sin(a) * 3.6)
				end
				if cube and cubePos then
					cube.CFrame = CFrame.new(cubePos) * CFrame.Angles(t * 0.3, t * 0.5, 0)
				end
			end
		end,
	},

	-- Stormbringer: particle-only VFX, no Part animations needed.
	-- Keep only the block (cube spin + orbiting bolts) which still uses decorative Parts.
	--[[ DISABLED Stormbringer throne rigs (particle VFX handles animation)
	{
		modelName = "ThunderThrone",
		build = function(model)
			local pivot = model:GetPivot()
			local ring = model:FindFirstChild("RuneRingAnchor")
			local inner = model:FindFirstChild("InnerRuneRing")
			local pulse = model:FindFirstChild("RuneRingAnchor_Pulse")
			local pulsePos = pulse and pulse.Position
			local ringPos = ring and ring.Position
			local innerPos = inner and inner.Position
			return function(t)
				if ring and ringPos then
					ring.CFrame = CFrame.new(ringPos) * CFrame.Angles(0, t * 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if inner and innerPos then
					inner.CFrame = CFrame.new(innerPos) * CFrame.Angles(0, -t * 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if pulse and pulsePos then
					local phase = (t * 0.8) % 1
					local scale = 1 + phase * 3
					pulse.Size = Vector3.new(8 * scale, 0.05, 8 * scale)
					pulse.Transparency = 0.4 + phase * 0.6
					pulse.CFrame = CFrame.new(pulsePos) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end,
	},
	{
		modelName = "TempestThrone",
		build = function(model)
			local pivot = model:GetPivot()
			local center = pivot.Position + Vector3.new(0, 1.5, 0)
			local debris, inner = {}, {}
			for i = 1, 8 do
				local d = model:FindFirstChild("Debris" .. i)
				if d then table.insert(debris, { part = d, phase = (i - 1) * (math.pi * 2 / 8) }) end
			end
			for i = 1, 6 do
				local d = model:FindFirstChild("InnerDebris" .. i)
				if d then table.insert(inner, { part = d, phase = (i - 1) * (math.pi * 2 / 6) }) end
			end
			local column = model:FindFirstChild("VortexColumn")
			local columnPos = column and column.Position
			local ring = model:FindFirstChild("RuneRingAnchor")
			local ringPos = ring and ring.Position
			local pulse = model:FindFirstChild("RuneRingAnchor_Pulse")
			local pulsePos = pulse and pulse.Position
			return function(t)
				for _, o in debris do
					local a = o.phase + t * 2
					local y = center.Y + math.sin(t * 2 + o.phase) * 0.6
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 2.2, y, center.Z + math.sin(a) * 2.2)
						* CFrame.Angles(t * 3, t * 2, 0)
				end
				for _, o in inner do
					local a = o.phase + t * 4
					local y = (columnPos and columnPos.Y or center.Y + 2.5) + math.sin(t * 3 + o.phase) * 2
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 0.8, y, center.Z + math.sin(a) * 0.8)
				end
				if column and columnPos then
					column.CFrame = CFrame.new(columnPos) * CFrame.Angles(0, t * 3, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if ring and ringPos then
					ring.CFrame = CFrame.new(ringPos) * CFrame.Angles(0, t * 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if pulse and pulsePos then
					local phase = (t * 0.7) % 1
					pulse.Size = Vector3.new(8 * (1 + phase * 3), 0.05, 8 * (1 + phase * 3))
					pulse.Transparency = 0.4 + phase * 0.6
					pulse.CFrame = CFrame.new(pulsePos) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end,
	},
	{
		modelName = "MonsoonThrone",
		build = function(model)
			local ring = model:FindFirstChild("RuneRingAnchor")
			local ringPos = ring and ring.Position
			local pulse = model:FindFirstChild("RuneRingAnchor_Pulse")
			local pulsePos = pulse and pulse.Position
			local flash = model:FindFirstChild("LightningFlash")
			local flashLight = flash and flash:FindFirstChild("FlashLight")
			local nextFlash = 3 + math.random() * 4
			return function(t)
				if ring and ringPos then
					ring.CFrame = CFrame.new(ringPos) * CFrame.Angles(0, t * 0.4, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if pulse and pulsePos then
					local phase = (t * 0.5) % 1
					pulse.Size = Vector3.new(9 * (1 + phase * 3), 0.05, 9 * (1 + phase * 3))
					pulse.Transparency = 0.4 + phase * 0.6
					pulse.CFrame = CFrame.new(pulsePos) * CFrame.Angles(0, 0, math.rad(90))
				end
				-- Lightning strobe: bright flash every few seconds
				if t >= nextFlash then
					nextFlash = t + 2 + math.random() * 4
				end
				local sinceFlash = t - (nextFlash - (2 + math.random() * 0)) -- approximate
				local flashIntensity = math.max(0, 1 - (t % 5) * 8) -- short bursts every 5s
				if flash and flashLight then
					flash.Transparency = 1 - flashIntensity * 0.5
					flashLight.Brightness = flashIntensity * 6
				end
			end
		end,
	},
	{
		modelName = "ZeusThrone",
		build = function(model)
			local halo = model:FindFirstChild("Halo")
			local haloPos = halo and halo.Position
			local innerHalo = model:FindFirstChild("InnerHalo")
			local innerPos = innerHalo and innerHalo.Position
			local center = haloPos or model:GetPivot().Position
			local bolts, tablets = {}, {}
			for i = 1, 6 do
				local b = model:FindFirstChild("OrbitBolt" .. i)
				if b then table.insert(bolts, { part = b, phase = (i - 1) * (math.pi * 2 / 6) }) end
			end
			for i = 1, 3 do
				local tb = model:FindFirstChild("Tablet" .. i)
				if tb then table.insert(tablets, { part = tb, phase = (i - 1) * (math.pi * 2 / 3) }) end
			end
			local ring = model:FindFirstChild("RuneRingAnchor")
			local ringPos = ring and ring.Position
			local pulse = model:FindFirstChild("RuneRingAnchor_Pulse")
			local pulsePos = pulse and pulse.Position
			local pivot = model:GetPivot()
			return function(t)
				for _, o in bolts do
					local a = o.phase + t * 1.2
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 3, center.Y, center.Z + math.sin(a) * 3)
						* CFrame.Angles(0, -a, 0)
				end
				for _, o in tablets do
					local a = o.phase + t * 0.5
					local y = pivot.Position.Y + 8 + math.sin(t * 0.8 + o.phase) * 0.4
					o.part.CFrame = CFrame.new(pivot.Position.X + math.cos(a) * 3.5, y, pivot.Position.Z + math.sin(a) * 3.5)
						* CFrame.Angles(0, -a, 0)
				end
				if halo and haloPos then
					halo.CFrame = CFrame.new(haloPos) * CFrame.Angles(0, t * 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if innerHalo and innerPos then
					innerHalo.CFrame = CFrame.new(innerPos) * CFrame.Angles(0, -t * 1.6, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if ring and ringPos then
					ring.CFrame = CFrame.new(ringPos) * CFrame.Angles(0, t * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if pulse and pulsePos then
					local phase = (t * 0.6) % 1
					pulse.Size = Vector3.new(10 * (1 + phase * 3), 0.05, 10 * (1 + phase * 3))
					pulse.Transparency = 0.4 + phase * 0.6
					pulse.CFrame = CFrame.new(pulsePos) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end,
	},
	{
		modelName = "StormGodThrone",
		build = function(model)
			local core = model:FindFirstChild("Core")
			local corePos = core and core.Position
			local pivot = model:GetPivot()
			local center = (corePos or pivot.Position) + Vector3.new(0, 0, 0)
			local stones, tips, tablets = {}, {}, {}
			for i = 1, 8 do
				local s = model:FindFirstChild("StormStone" .. i)
				if s then table.insert(stones, { part = s, phase = (i - 1) * (math.pi * 2 / 8) }) end
			end
			for i = 1, 4 do
				local tp = model:FindFirstChild("TipAnchor" .. i)
				if tp then table.insert(tips, { part = tp, phase = (i - 1) * (math.pi / 2) }) end
			end
			for i = 1, 4 do
				local tb = model:FindFirstChild("RuneTablet" .. i)
				if tb then table.insert(tablets, { part = tb, phase = (i - 1) * (math.pi / 2) }) end
			end
			local ring = model:FindFirstChild("RuneRingAnchor")
			local ringPos = ring and ring.Position
			local pulse = model:FindFirstChild("RuneRingAnchor_Pulse")
			local pulsePos = pulse and pulse.Position
			local shock = model:FindFirstChild("Shockwave")
			local shockPos = shock and shock.Position
			local shock2 = model:FindFirstChild("Shockwave2")
			local shock2Pos = shock2 and shock2.Position
			local tornado = model:FindFirstChild("TornadoLower")
			local tornadoPos = tornado and tornado.Position
			return function(t)
				for _, o in stones do
					local a = o.phase + t * 1.5
					local r = 3.2 + math.sin(t * 1.2 + o.phase) * 0.4
					local y = center.Y + math.sin(t * 0.9 + o.phase) * 0.6
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * r, y, center.Z + math.sin(a) * r)
						* CFrame.Angles(t * 2, -a, 0)
				end
				for _, o in tips do
					local a = o.phase + t * 0.7
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 3, center.Y + 2.5, center.Z + math.sin(a) * 3)
				end
				for _, o in tablets do
					local a = o.phase - t * 0.6 -- counter-rotate vs stones
					local y = pivot.Position.Y + 6 + math.sin(t * 1.1 + o.phase) * 0.5
					o.part.CFrame = CFrame.new(pivot.Position.X + math.cos(a) * 4.2, y, pivot.Position.Z + math.sin(a) * 4.2)
						* CFrame.Angles(0, -a, 0)
				end
				if core and corePos then
					core.CFrame = CFrame.new(corePos) * CFrame.Angles(t * 0.6, t * 0.8, 0)
				end
				if ring and ringPos then
					ring.CFrame = CFrame.new(ringPos) * CFrame.Angles(0, t * 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				if pulse and pulsePos then
					local phase = (t * 0.9) % 1
					pulse.Size = Vector3.new(12 * (1 + phase * 3), 0.05, 12 * (1 + phase * 3))
					pulse.Transparency = 0.3 + phase * 0.7
					pulse.CFrame = CFrame.new(pulsePos) * CFrame.Angles(0, 0, math.rad(90))
				end
				if shock and shockPos then
					local phase = (t * 1.1) % 1
					local s = 1 + phase * 12
					shock.Size = Vector3.new(s, 0.1, s)
					shock.Transparency = 0.2 + phase * 0.8
					shock.CFrame = CFrame.new(shockPos) * CFrame.Angles(0, 0, math.rad(90))
				end
				if shock2 and shock2Pos then
					local phase = ((t * 1.1) + 0.5) % 1
					local s = 1 + phase * 12
					shock2.Size = Vector3.new(s, 0.1, s)
					shock2.Transparency = 0.4 + phase * 0.6
					shock2.CFrame = CFrame.new(shock2Pos) * CFrame.Angles(0, 0, math.rad(90))
				end
				if tornado and tornadoPos then
					tornado.CFrame = CFrame.new(tornadoPos) * CFrame.Angles(0, t * 4, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end,
	},
	--]]
	{
		modelName = "StormbringerLuckyBlock",
		build = function(model)
			local cube = model:FindFirstChild("Cube")
			local cubePos = cube and cube.Position
			local center = cubePos or model:GetPivot().Position
			local bolts = {}
			for i = 1, 6 do
				local b = model:FindFirstChild("Bolt" .. i)
				if b then
					table.insert(bolts, { part = b, phase = (i - 1) * (math.pi * 2 / 6) })
				end
			end
			return function(t)
				for _, o in bolts do
					local a = o.phase + t * 1
					local y = center.Y + math.sin(t * 1.5 + o.phase) * 0.5
					o.part.CFrame = CFrame.new(center.X + math.cos(a) * 2.8, y, center.Z + math.sin(a) * 2.8)
						* CFrame.Angles(0, -a, math.rad(20))
				end
				if cube and cubePos then
					cube.CFrame = CFrame.new(cubePos) * CFrame.Angles(t * 0.4, t * 0.6, 0)
				end
			end
		end,
	},
}

local active: { (t: number) -> () } = {}

local function bindRig(rig)
	local model = Workspace:FindFirstChild(rig.modelName)
	if not model then
		-- Try waiting briefly if streaming hasn't loaded it
		task.spawn(function()
			local tries = 0
			while tries < 30 and not Workspace:FindFirstChild(rig.modelName) do
				task.wait(1)
				tries += 1
			end
			local found = Workspace:FindFirstChild(rig.modelName)
			if found then
				local tick = rig.build(found)
				table.insert(active, tick)
			end
		end)
		return
	end
	local tick = rig.build(model)
	table.insert(active, tick)
end

for _, rig in rigs do
	bindRig(rig)
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for i = 1, #active do
		active[i](t)
	end
end)
