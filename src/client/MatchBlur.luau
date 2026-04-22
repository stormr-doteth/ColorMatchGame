-- MatchBlur
-- Adds a soft depth-of-field blur to Lighting during matches (solo + 1v1)
-- so the background world recedes and the match UI reads more clearly.
-- Tweens in on MatchStart, out on MatchEnd / explicit Clear / respawn.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BLUR_SIZE = 18
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local MatchBlur = {}

local blur: BlurEffect? = nil

local function getBlur(): BlurEffect
	if blur and blur.Parent then return blur end
	local existing = Lighting:FindFirstChild("MatchBlur")
	if existing and existing:IsA("BlurEffect") then
		blur = existing
	else
		local b = Instance.new("BlurEffect")
		b.Name = "MatchBlur"
		b.Size = 0
		b.Parent = Lighting
		blur = b
	end
	return blur :: BlurEffect
end

function MatchBlur.Apply()
	local b = getBlur()
	TweenService:Create(b, FADE_IN, { Size = BLUR_SIZE }):Play()
end

function MatchBlur.Clear()
	local b = getBlur()
	TweenService:Create(b, FADE_OUT, { Size = 0 }):Play()
end

function MatchBlur.Start()
	getBlur()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("MatchStart").OnClientEvent:Connect(MatchBlur.Apply)
	remotes:WaitForChild("MatchEnd").OnClientEvent:Connect(MatchBlur.Clear)

	-- Catch-all: any character respawn/teleport clears the blur. This
	-- guarantees the blur can't stay stuck on in the lobby even if an
	-- explicit close-path signal was missed upstream.
	local localPlayer = Players.LocalPlayer
	localPlayer.CharacterAdded:Connect(function()
		MatchBlur.Clear()
	end)
end

return MatchBlur
