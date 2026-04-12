-- CashHud
-- Listens for PlayerDataUpdate from the server and writes the player's cash
-- value into the existing CashFrame TextLabel placed in StarterGui by the
-- UI artist. Animates the count-up smoothly so winning a match feels good.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashHud = {}

local function formatCash(n: number): string
	local int = math.floor(n + 0.5)
	local sign = ""
	if int < 0 then
		sign = "-"
		int = -int
	end
	local s = tostring(int)
	-- Insert commas every three digits from the right
	local withCommas = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	-- Strip any leading comma left by gsub when length is a multiple of 3
	withCommas = (withCommas:gsub("^,", ""))
	return `${sign}{withCommas}`
end

local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function resolveCashLabel(playerGui: PlayerGui): TextLabel?
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then
		return nil
	end
	local hud = screenGui:WaitForChild("HUD_Inventory_Numbers", 10)
	if not hud then
		return nil
	end
	local cashFrame = hud:WaitForChild("CashFrame", 10)
	if not cashFrame then
		return nil
	end
	local label = cashFrame:WaitForChild("Cash", 10)
	if not label or not label:IsA("TextLabel") then
		return nil
	end
	return label :: TextLabel
end

function CashHud.Start()
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
			label.Text = formatCash(value)
		end
	end

	local function ensureLabel()
		if label and label.Parent then
			return label
		end
		label = resolveCashLabel(playerGui)
		if label then
			-- Render whatever we know right now (zero on first paint, or the
			-- last known value after a respawn).
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
		local newCash = tonumber(data.Cash) or 0
		ensureLabel()
		if not hasInitialValue then
			hasInitialValue = true
			displayed = newCash
			target = newCash
			setLabelText(displayed)
			return
		end
		if newCash == target then
			return
		end
		local from = displayed
		target = newCash
		startCountUp(from, target)
	end

	updateRemote.OnClientEvent:Connect(applyUpdate)

	-- The CashFrame lives inside a ScreenGui that may have ResetOnSpawn = true,
	-- in which case the label is recreated each time the character respawns.
	-- Re-resolve and repaint with the latest known value when that happens.
	playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") and child.Name == "ScreenGui" then
			label = nil
			task.defer(function()
				ensureLabel()
				setLabelText(displayed)
			end)
		end
	end)

	-- Resolve once up front so we paint as soon as the GUI is available, even
	-- before the first server update arrives.
	ensureLabel()
end

return CashHud
