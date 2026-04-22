-- LuckyBlockClient
-- Handles tool activation for lucky blocks and plays the 3D reveal animation.
--
-- Flow:
--   1. Monitor Backpack for Tools named "LuckyBlock_*"
--   2. On Tool.Activated → fire OpenLuckyBlock remote with drop position
--   3. On LuckyBlockResult remote → play the full reveal sequence:
--      Drop block → shrink away → cycle chairs → land on winner → display
--   4. Show notification AFTER the reveal animation finishes

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))
local NotificationHud = require(script.Parent:WaitForChild("NotificationHud"))

local LuckyBlockClient = {}

local localPlayer = Players.LocalPlayer
local activeOpenings: { [string]: boolean } = {} -- per-player debounce

-- Timing constants
local DROP_TIME = Constants.LUCKY_BLOCK_DROP_TIME
local SHRINK_TIME = Constants.LUCKY_BLOCK_SHRINK_TIME
local CYCLE_TIME = Constants.LUCKY_BLOCK_CYCLE_TIME
local CYCLE_START = Constants.LUCKY_BLOCK_CYCLE_START_INTERVAL
local CYCLE_END = Constants.LUCKY_BLOCK_CYCLE_END_INTERVAL
local CHAIR_HEIGHT = Constants.LUCKY_BLOCK_CHAIR_HEIGHT
local DISPLAY_TIME = Constants.LUCKY_BLOCK_DISPLAY_TIME

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Raycast downward to find the ground position
local function getGroundPosition(origin: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = localPlayer.Character
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local result = Workspace:Raycast(origin, Vector3.new(0, -50, 0), params)
	if result then
		return result.Position
	end
	return origin + Vector3.new(0, -3, 0)
end

-- Set transparency on all BaseParts in a model, respecting each part's
-- original transparency (so Seats and other hidden parts stay invisible).
local function setModelTransparency(model: Model, transparency: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local orig = part:GetAttribute("OrigTransparency") or 0
			if transparency <= 0 then
				part.Transparency = orig
			elseif transparency >= 1 then
				part.Transparency = 1
			else
				part.Transparency = orig + (1 - orig) * transparency
			end
		end
	end
end

-- Toggle all particle-like effects on a chair. When disabling, also clear any
-- existing particles so they don't linger in place after the chair swaps. When
-- enabling, burst-emit a small amount so particles are visible even when the
-- chair is only on-screen for a few frames during the rapid cycle.
local function setChairEffectsEnabled(model: Model, enabled: boolean, burstDuration: number?)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = enabled
			if enabled then
				-- Emit Rate * burstDuration particles immediately so the swap is visible
				local count = math.clamp(math.floor(d.Rate * (burstDuration or 0.2)), 1, 60)
				d:Emit(count)
			else
				d:Clear()
			end
		elseif d:IsA("Trail") or d:IsA("Beam") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
			d.Enabled = enabled
		end
	end
end

-- Prepare a chair clone: store original transparency, anchor, disable collision
local function prepareChairClone(clone: Model)
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("OrigTransparency", part.Transparency)
			part.Anchored = true
			part.CanCollide = false
		end
	end
end

---------------------------------------------------------------------------
-- Sound effects
---------------------------------------------------------------------------

-- Create an anchored invisible Part that holds all sounds for one reveal.
-- Spatial audio: nearby players hear it too.
local function createSoundAnchor(position: Vector3): Part
	local anchor = Instance.new("Part")
	anchor.Name = "LuckySoundAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	return anchor
end

local function makeSound(parent: Instance, id: string, volume: number?, looped: boolean?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 1
	sound.Looped = looped or false
	sound.RollOffMaxDistance = 80
	sound.Parent = parent
	return sound
end

-- Play tick with cutoff (the asset has dead audio at the end)
local function playTick(anchor: Part, pitch: number)
	local tick = makeSound(anchor, Constants.SFX_TICK, 0.6)
	tick.PlaybackSpeed = pitch
	tick:Play()
	task.delay(Constants.SFX_TICK_DURATION / pitch, function()
		tick:Stop()
		tick:Destroy()
	end)
end

-- Preload all SFX so there's no delay on first play
local function preloadSounds()
	local ids = {
		Constants.SFX_TICK,
		Constants.SFX_THUD,
		Constants.SFX_SHIMMER,
		Constants.SFX_FANFARE,
		Constants.SFX_WHOOSH,
	}
	local assets = {}
	for _, id in ids do
		local s = Instance.new("Sound")
		s.SoundId = id
		table.insert(assets, s)
	end
	ContentProvider:PreloadAsync(assets)
	for _, s in assets do
		s:Destroy()
	end
end

---------------------------------------------------------------------------
-- Particle effects
---------------------------------------------------------------------------

-- Invisible anchored Part used as a particle host
local function makeEmitterPart(position: Vector3, name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(1, 1, 1)
	p.Position = position
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 1
	p.Parent = Workspace
	return p
end

-- Phase 2: block vanish — fast gold starburst + smoke puff
local function createBurstParticles(position: Vector3): Part
	local host = makeEmitterPart(position, "LuckyBurst")

	-- Gold starburst (fast, sharp)
	local stars = Instance.new("ParticleEmitter")
	stars.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 0)),
	})
	stars.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.3, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	stars.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	stars.Lifetime = NumberRange.new(0.3, 0.7)
	stars.Speed = NumberRange.new(12, 22)
	stars.SpreadAngle = Vector2.new(180, 180)
	stars.RotSpeed = NumberRange.new(-300, 300)
	stars.Rotation = NumberRange.new(0, 360)
	stars.LightEmission = 1
	stars.Rate = 0
	stars.Parent = host
	stars:Emit(35)

	-- Soft white smoke puff
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(220, 220, 230))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 2.5),
		NumberSequenceKeypoint.new(1, 3),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.5, 1.0)
	smoke.Speed = NumberRange.new(2, 6)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.LightEmission = 0.3
	smoke.Rate = 0
	smoke.Parent = host
	smoke:Emit(15)

	task.delay(1.5, function()
		host:Destroy()
	end)
	return host
end

-- Phase 5+6: multi-layered reveal effect
-- Returns a table of Parts so caller can clean them all up.
local function createRevealParticles(position: Vector3): Part
	local host = makeEmitterPart(position, "RevealFX")

	-- Layer 1: Rising golden sparkles (slow, floaty)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 100)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 0)),
	})
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 0.5),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.Lifetime = NumberRange.new(1.0, 2.0)
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(40, 40)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.RotSpeed = NumberRange.new(-200, 200)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.LightEmission = 1
	sparkles.Rate = 30
	sparkles.Parent = host

	-- Layer 2: Big initial starburst (one-shot)
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "Burst"
	burst.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 220)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 50)),
	})
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.2, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Lifetime = NumberRange.new(0.5, 1.0)
	burst.Speed = NumberRange.new(10, 20)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.RotSpeed = NumberRange.new(-400, 400)
	burst.Rotation = NumberRange.new(0, 360)
	burst.LightEmission = 1
	burst.Rate = 0
	burst.Parent = host
	burst:Emit(40)

	-- Layer 3: Confetti (colorful, slower, drifting)
	local confetti = Instance.new("ParticleEmitter")
	confetti.Name = "Confetti"
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(80, 200, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 255, 100)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 80, 255)),
	})
	confetti.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	confetti.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	confetti.Lifetime = NumberRange.new(1.5, 3.0)
	confetti.Speed = NumberRange.new(8, 16)
	confetti.SpreadAngle = Vector2.new(60, 180)
	confetti.EmissionDirection = Enum.NormalId.Top
	confetti.RotSpeed = NumberRange.new(-500, 500)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.Acceleration = Vector3.new(0, -8, 0) -- gravity drift
	confetti.LightEmission = 0.5
	confetti.Rate = 0
	confetti.Parent = host
	confetti:Emit(50)

	-- Layer 4: Soft glow halo (large, slow, faint)
	local glow = Instance.new("ParticleEmitter")
	glow.Name = "Glow"
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150))
	glow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(0.5, 5),
		NumberSequenceKeypoint.new(1, 6),
	})
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.5, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	glow.Lifetime = NumberRange.new(1.0, 1.5)
	glow.Speed = NumberRange.new(0.5, 1.5)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.Rate = 8
	glow.Parent = host

	return host
end

-- Expanding neon rings (two staggered pulses for extra punch)
local function createLightRing(position: Vector3)
	for i = 0, 1 do
		task.delay(i * 0.15, function()
			local ring = Instance.new("Part")
			ring.Name = "LightRing"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.3, 1, 1)
			ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
			ring.Anchored = true
			ring.CanCollide = false
			ring.Material = Enum.Material.Neon
			ring.Color = if i == 0
				then Color3.fromRGB(255, 215, 0)
				else Color3.fromRGB(255, 255, 180)
			ring.Transparency = if i == 0 then 0.2 else 0.4
			ring.Parent = Workspace

			local targetSize = if i == 0
				then Vector3.new(0.3, 24, 24)
				else Vector3.new(0.2, 16, 16)
			local duration = if i == 0 then 0.6 else 0.5

			TweenService:Create(ring,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = targetSize, Transparency = 1 }
			):Play()

			task.delay(duration + 0.1, function()
				ring:Destroy()
			end)
		end)
	end
end

---------------------------------------------------------------------------
-- 3D Reveal Animation
---------------------------------------------------------------------------

local function playRevealAnimation(data)
	local blockId = data.blockId
	local playerName: string = data.playerName or ""
	local winnerChairId = data.winnerChairId
	local lootChairIds = data.lootChairIds
	local dropPosition: Vector3 = data.dropPosition
	local notificationMsg: string? = data.notificationMsg
	local isLocalPlayer = (playerName == localPlayer.Name)

	local entry = LuckyBlockCatalog.Get(blockId)
	if not entry then
		if isLocalPlayer then
			activeOpenings[playerName] = nil
		end
		return
	end

	local groundPos = getGroundPosition(dropPosition + Vector3.new(0, 3, 0))
	local chairPos = groundPos + Vector3.new(0, CHAIR_HEIGHT, 0)

	-- Sound anchor — all SFX attach here for spatial audio
	local soundAnchor = createSoundAnchor(groundPos)

	-- Get chair templates for cycling
	local chairTemplates = ReplicatedStorage:FindFirstChild("ChairTemplates")
	if not chairTemplates then
		isOpening = false
		return
	end

	-- Also find the block model to clone a mini version for the drop
	-- Check ReplicatedStorage template folder first, then Workspace root
	local luckyFolder = ReplicatedStorage:FindFirstChild("LuckyBlocks")
	local animFolder = ReplicatedStorage:FindFirstChild("Animated Lucky Blocks")
	local blockModel = (luckyFolder and luckyFolder:FindFirstChild(entry.modelName))
		or (animFolder and animFolder:FindFirstChild(entry.modelName))
		or Workspace:FindFirstChild(entry.modelName)

	-----------------------------------------------------------------------
	-- Phase 1: Block Drop (0.5s)
	-----------------------------------------------------------------------
	local dropClone: (Model | BasePart)? = nil
	if blockModel then
		if blockModel:IsA("Model") then
			local mdl = blockModel:Clone() :: Model
			dropClone = mdl
			local baseScale = mdl:GetScale()
			local _, bbSize = mdl:GetBoundingBox()
			local maxDim = math.max(bbSize.X, bbSize.Y, bbSize.Z)
			local targetSize = 2
			if maxDim > 0 then
				mdl:ScaleTo(baseScale * (targetSize / maxDim))
			end
			prepareChairClone(mdl)
			mdl:PivotTo(CFrame.new(dropPosition + Vector3.new(0, 3, 0)))
			mdl.Parent = Workspace
		elseif blockModel:IsA("BasePart") then
			local part = blockModel:Clone() :: BasePart
			dropClone = part
			part.Anchored = true
			part.CanCollide = false
			local sz = part.Size
			local maxDim = math.max(sz.X, sz.Y, sz.Z)
			if maxDim > 2 then
				part.Size = sz * (2 / maxDim)
			end
			part.Position = dropPosition + Vector3.new(0, 3, 0)
			part.Parent = Workspace
		end
	end

	-- Tween the drop clone down to ground
	if dropClone then
		if dropClone:IsA("Model") then
			local mdl = dropClone :: Model
			local startCF = mdl:GetPivot()
			local endCF = CFrame.new(groundPos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(360), 0)
			local dropStart = os.clock()
			local dropConn: RBXScriptConnection?
			local dropDone = false
			dropConn = RunService.RenderStepped:Connect(function()
				local t = math.min(1, (os.clock() - dropStart) / DROP_TIME)
				local bt: number
				if t < 1 / 2.75 then
					bt = 7.5625 * t * t
				elseif t < 2 / 2.75 then
					local t2 = t - 1.5 / 2.75
					bt = 7.5625 * t2 * t2 + 0.75
				elseif t < 2.5 / 2.75 then
					local t2 = t - 2.25 / 2.75
					bt = 7.5625 * t2 * t2 + 0.9375
				else
					local t2 = t - 2.625 / 2.75
					bt = 7.5625 * t2 * t2 + 0.984375
				end
				mdl:PivotTo(startCF:Lerp(endCF, bt))
				if t >= 1 then
					dropDone = true
					if dropConn then dropConn:Disconnect() end
				end
			end)
			while not dropDone do task.wait() end
			makeSound(soundAnchor, Constants.SFX_THUD, 0.8):Play()
		elseif dropClone:IsA("BasePart") then
			local part = dropClone :: BasePart
			local dropTween = TweenService:Create(part,
				TweenInfo.new(DROP_TIME, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
				{ CFrame = CFrame.new(groundPos + Vector3.new(0, part.Size.Y / 2, 0)) * CFrame.Angles(0, math.rad(360), 0) }
			)
			dropTween:Play()
			dropTween.Completed:Wait()
			makeSound(soundAnchor, Constants.SFX_THUD, 0.8):Play()
		end
	end

	-----------------------------------------------------------------------
	-- Phase 2: Block Shrink (0.4s)
	-----------------------------------------------------------------------
	if dropClone then
		makeSound(soundAnchor, Constants.SFX_WHOOSH, 0.7):Play()
		local shrinkPos: Vector3
		if dropClone:IsA("Model") then
			shrinkPos = (dropClone :: Model):GetPivot().Position
		else
			shrinkPos = (dropClone :: BasePart).Position
		end
		createBurstParticles(shrinkPos)

		if dropClone:IsA("Model") then
			local mdl = dropClone :: Model
			local startScale = mdl:GetScale()
			local shrinkStart = os.clock()
			local shrinkDone = false
			local shrinkConn: RBXScriptConnection?
			shrinkConn = RunService.RenderStepped:Connect(function()
				local t = math.min(1, (os.clock() - shrinkStart) / SHRINK_TIME)
				local s = lerp(startScale, 0.01, t)
				mdl:ScaleTo(math.max(0.01, s))
				setModelTransparency(mdl, t)
				if t >= 1 then
					shrinkDone = true
					if shrinkConn then shrinkConn:Disconnect() end
				end
			end)
			while not shrinkDone do task.wait() end
		elseif dropClone:IsA("BasePart") then
			local part = dropClone :: BasePart
			local shrinkTween = TweenService:Create(part,
				TweenInfo.new(SHRINK_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Size = Vector3.new(0.01, 0.01, 0.01), Transparency = 1 }
			)
			shrinkTween:Play()
			shrinkTween.Completed:Wait()
		end
		dropClone:Destroy()
		dropClone = nil
	end

	-----------------------------------------------------------------------
	-- Phase 3: Chair Cycling (~4s)
	-----------------------------------------------------------------------

	-- Preload chair clones (one per unique chair id)
	local chairClones: { [string]: Model } = {}
	local chairBaseScales: { [string]: number } = {}
	for _, chairId in lootChairIds do
		if chairClones[chairId] then
			continue
		end
		local catalogEntry = ChairCatalog.Get(chairId)
		if not catalogEntry then
			continue
		end
		local template = chairTemplates:FindFirstChild(catalogEntry.modelName)
		if template and template:IsA("Model") then
			local clone = template:Clone()
			prepareChairClone(clone)
			clone:PivotTo(CFrame.new(chairPos))
			clone.Parent = Workspace
			setModelTransparency(clone, 1) -- start invisible
			setChairEffectsEnabled(clone, false) -- start with effects off
			chairClones[chairId] = clone
			chairBaseScales[chairId] = clone:GetScale()
		end
	end

	-- Spin + bob connection
	local currentVisible: Model? = nil
	local spinAngle = 0
	local spinConnection: RBXScriptConnection? = nil
	spinConnection = RunService.RenderStepped:Connect(function(dt)
		if currentVisible then
			spinAngle += math.rad(60) * dt
			local bobY = math.sin(os.clock() * 3) * 0.3
			local basePos = Vector3.new(chairPos.X, chairPos.Y + bobY, chairPos.Z)
			currentVisible:PivotTo(CFrame.new(basePos) * CFrame.Angles(0, spinAngle, 0))
		end
	end)

	-- Swap function: hide current, show next
	local function showChair(chairId: string)
		-- Hide previous + kill its lingering particles
		if currentVisible then
			setModelTransparency(currentVisible, 1)
			setChairEffectsEnabled(currentVisible, false)
		end

		local model = chairClones[chairId]
		if not model then
			return
		end
		currentVisible = model

		-- Reset scale to base and show
		local baseScale = chairBaseScales[chairId] or 1
		model:ScaleTo(baseScale)
		model:PivotTo(CFrame.new(chairPos) * CFrame.Angles(0, spinAngle, 0))
		setModelTransparency(model, 0)
		setChairEffectsEnabled(model, true)
	end

	-- Cycling loop with exponential slowdown
	local elapsed = 0
	local currentIndex = math.random(1, #lootChairIds)
	local landedOnWinner = false

	while elapsed < CYCLE_TIME do
		local progress = elapsed / CYCLE_TIME
		local interval = lerp(CYCLE_START, CYCLE_END, progress * progress)

		showChair(lootChairIds[currentIndex])
		-- Tick sound with rising pitch as it slows down
		local tickPitch = lerp(0.8, 1.4, progress)
		playTick(soundAnchor, tickPitch)

		task.wait(interval)
		elapsed += interval

		-- When nearing the end, rig it to land on the winner
		if progress > 0.85 and not landedOnWinner then
			local winnerIdx = 1
			for i, id in lootChairIds do
				if id == winnerChairId then
					winnerIdx = i
					break
				end
			end
			currentIndex = winnerIdx
			landedOnWinner = true
		else
			currentIndex = (currentIndex % #lootChairIds) + 1
		end
	end

	-- Make sure the winner is showing
	showChair(winnerChairId)

	-----------------------------------------------------------------------
	-- Phase 5: Winner Reveal — scale bounce using Model:ScaleTo()
	-----------------------------------------------------------------------
	local winnerModel = chairClones[winnerChairId]
	local baseScale = chairBaseScales[winnerChairId] or 1

	if winnerModel then
		-- Shrink to 0.5x
		local t0 = os.clock()
		while os.clock() - t0 < 0.15 do
			local t = (os.clock() - t0) / 0.15
			winnerModel:ScaleTo(lerp(baseScale, baseScale * 0.5, t))
			task.wait()
		end

		-- Overshoot to 1.8x with back easing
		t0 = os.clock()
		while os.clock() - t0 < 0.3 do
			local t = (os.clock() - t0) / 0.3
			local c1 = 1.70158
			local c3 = c1 + 1
			local eased = 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
			winnerModel:ScaleTo(lerp(baseScale * 0.5, baseScale * 1.8, eased))
			task.wait()
		end

		-- Settle to 1.3x
		t0 = os.clock()
		while os.clock() - t0 < 0.15 do
			local t = (os.clock() - t0) / 0.15
			winnerModel:ScaleTo(lerp(baseScale * 1.8, baseScale * 1.3, t))
			task.wait()
		end
		winnerModel:ScaleTo(baseScale * 1.3)
	end

	-- Sparkle particles + light ring
	local sparkleEmitter = createRevealParticles(chairPos)
	createLightRing(groundPos)

	-- Fanfare on reveal
	makeSound(soundAnchor, Constants.SFX_FANFARE, 1):Play()

	-- Shimmer loop during display
	local shimmer = makeSound(soundAnchor, Constants.SFX_SHIMMER, 0.4, true)
	shimmer:Play()

	-- Show notification only for the player who opened the block
	if notificationMsg and isLocalPlayer then
		NotificationHud.Show(notificationMsg)
	end

	-----------------------------------------------------------------------
	-- Phase 6: Display, tween chair into player, cleanup
	-----------------------------------------------------------------------
	task.wait(DISPLAY_TIME)

	-- Fade out shimmer
	TweenService:Create(shimmer, TweenInfo.new(0.5), { Volume = 0 }):Play()

	-- Stop spinning
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end

	-- Tween the winner chair into the opening player's torso
	if winnerModel then
		local openerPlayer = Players:FindFirstChild(playerName)
		local targetPos = chairPos -- fallback if player left
		if openerPlayer and openerPlayer:IsA("Player") and openerPlayer.Character then
			local hrp = openerPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				targetPos = hrp.Position
			end
		end

		local flyDuration = 0.8
		local flyStart = os.clock()
		local startPivot = winnerModel:GetPivot()
		local startScale = winnerModel:GetScale()
		while os.clock() - flyStart < flyDuration do
			local t = (os.clock() - flyStart) / flyDuration
			-- Quad ease in: accelerating "sucked in" feel
			local eased = t * t

			-- Update target in case player is moving
			if openerPlayer and openerPlayer:IsA("Player") and openerPlayer.Character then
				local hrp = openerPlayer.Character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					targetPos = hrp.Position
				end
			end

			local pos = startPivot.Position:Lerp(targetPos, eased)
			winnerModel:PivotTo(CFrame.new(pos) * CFrame.Angles(0, eased * math.pi * 2, 0))
			winnerModel:ScaleTo(lerp(startScale, startScale * 0.2, eased))
			setModelTransparency(winnerModel, eased)
			task.wait()
		end
	end

	-- Cleanup
	for _, clone in chairClones do
		clone:Destroy()
	end
	sparkleEmitter:Destroy()
	soundAnchor:Destroy()

	if isLocalPlayer then
		activeOpenings[playerName] = nil
	end
end

---------------------------------------------------------------------------
-- Tool activation
---------------------------------------------------------------------------

local function onToolActivated(tool: Tool)
	if activeOpenings[localPlayer.Name] then
		return
	end

	local blockIdValue = tool:FindFirstChild("BlockId")
	if not blockIdValue or not blockIdValue:IsA("StringValue") then
		return
	end
	local blockId = blockIdValue.Value

	local character = localPlayer.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?

	activeOpenings[localPlayer.Name] = true

	-- Compute drop position: in front of the player, on the ground
	local dropOrigin = hrp.Position + hrp.CFrame.LookVector * 4
	local dropPos = getGroundPosition(dropOrigin)

	-- Unequip the tool
	if humanoid then
		humanoid:UnequipTools()
	end

	-- Fire to server
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local openRemote = remotes:FindFirstChild("OpenLuckyBlock") :: RemoteEvent?
	if openRemote then
		openRemote:FireServer(blockId, dropPos)
	end
end

local function watchTool(tool: Tool)
	if not tool.Name:match("^LuckyBlock_") then
		return
	end
	tool.Activated:Connect(function()
		onToolActivated(tool)
	end)
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function LuckyBlockClient.Start()
	-- Preload SFX so first open has no audio delay
	task.spawn(preloadSounds)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	-- Listen for result from server
	local resultRemote = remotes:WaitForChild("LuckyBlockResult") :: RemoteEvent
	resultRemote.OnClientEvent:Connect(function(data)
		if typeof(data) == "table" then
			task.spawn(playRevealAnimation, data)
		end
	end)

	-- Watch for lucky block tools in backpack
	local backpack = localPlayer:WaitForChild("Backpack")
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") then
			watchTool(child)
		end
	end
	backpack.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			watchTool(child)
		end
	end)

	-- Also watch character (tool moves there when equipped)
	localPlayer.CharacterAdded:Connect(function(character)
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				watchTool(child)
			end
		end
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				watchTool(child)
			end
		end)
	end)
	if localPlayer.Character then
		for _, child in localPlayer.Character:GetChildren() do
			if child:IsA("Tool") then
				watchTool(child)
			end
		end
	end
end

return LuckyBlockClient
