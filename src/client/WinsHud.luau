-- WinsHud
-- Mirrors CashHud, but writes the player's total Wins count into the
-- WinsFrame.Wins TextLabel placed in StarterGui by the UI artist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WinsHud = {}

local function formatWins(n: number): string
	local int = math.floor(n + 0.5)
	if int < 0 then
		int = 0
	end
	local s = tostring(int)
	local withCommas = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	withCommas = (withCommas:gsub("^,", ""))
	return withCommas
end

local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function resolveWinsLabel(playerGui: PlayerGui): TextLabel?
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then
		return nil
	end
	local hud = screenGui:WaitForChild("HUD_Inventory_Numbers", 10)
	if not hud then
		return nil
	end
	local winsFrame = hud:WaitForChild("WinsFrame", 10)
	if not winsFrame then
		return nil
	end
	local label = winsFrame:WaitForChild("Wins", 10)
	if not label or not label:IsA("TextLabel") then
		return nil
	end
	return label :: TextLabel
end

function WinsHud.Start()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local updateRemote = remotes:WaitForChild("PlayerDataUpdate") :: RemoteEvent

	local label: TextLabel? = nil
	local displayed = 0
	local target = 0
	local hasInitialValue = false
	local animToken = 0

	local function setLabelText(value: number)
		if label then
			label.Text = formatWins(value)
		end
	end

	local function ensureLabel()
		if label and label.Parent then
			return label
		end
		label = resolveWinsLabel(playerGui)
		if label then
			setLabelText(displayed)
		end
		return label
	end

	local function startCountUp(from: number, to: number)
		animToken += 1
		local myToken = animToken
		local startTime = os.clock()
		local duration = 0.6
		task.spawn(function()
			while myToken == animToken do
				local elapsed = os.clock() - startTime
				local t = math.clamp(elapsed / duration, 0, 1)
				local eased = easeOutQuad(t)
				displayed = from + (to - from) * eased
				setLabelText(displayed)
				if t >= 1 then
					displayed = to
					setLabelText(displayed)
					break
				end
				task.wait()
			end
		end)
	end

	local function applyUpdate(data)
		if typeof(data) ~= "table" then
			return
		end
		local newWins = tonumber(data.Wins) or 0
		ensureLabel()
		if not hasInitialValue then
			hasInitialValue = true
			displayed = newWins
			target = newWins
			setLabelText(displayed)
			return
		end
		if newWins == target then
			return
		end
		local from = displayed
		target = newWins
		startCountUp(from, target)
	end

	updateRemote.OnClientEvent:Connect(applyUpdate)

	playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") and child.Name == "ScreenGui" then
			label = nil
			task.defer(function()
				ensureLabel()
				setLabelText(displayed)
			end)
		end
	end)

	ensureLabel()
end

return WinsHud
