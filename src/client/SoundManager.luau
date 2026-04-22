-- SoundManager
-- Keeps one persistent Sound per catalog entry parented to SoundService so
-- replay has no spawn/load latency. Call Play(name) to rewind and play.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local SoundCatalog = require(script.Parent:WaitForChild("SoundCatalog"))

local SoundManager = {}

local globalVolume = 1
local sounds: { [string]: Sound } = {}

local function urlFor(id: number): string
	return "rbxassetid://" .. tostring(id)
end

local function getOrCreate(name: string): Sound?
	local cached = sounds[name]
	if cached then return cached end

	local def = SoundCatalog[name]
	if not def or def.id <= 0 then return nil end

	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = urlFor(def.id)
	s.Volume = def.volume * globalVolume
	if def.pitch then s.PlaybackSpeed = def.pitch end
	s.Parent = SoundService
	sounds[name] = s
	return s
end

function SoundManager.SetGlobalVolume(v: number)
	globalVolume = math.clamp(v, 0, 1)
	for name, s in sounds do
		local def = SoundCatalog[name]
		if def then s.Volume = def.volume * globalVolume end
	end
end

function SoundManager.Play(name: string)
	local s = getOrCreate(name)
	if not s then return end
	s.TimePosition = 0
	s:Play()
end

function SoundManager.Start()
	local assets: { Instance } = {}
	for name, def in SoundCatalog do
		if def.id > 0 then
			local s = getOrCreate(name)
			if s then table.insert(assets, s) end
		end
	end
	if #assets == 0 then return end
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync(assets) end)
	end)
end

return SoundManager
