-- TablePromptSuppressor (client)
-- Hides the table's "Join"/"Practice" ProximityPrompt on the local client once
-- the player is seated at that table. Writing `Enabled = false` client-side
-- doesn't replicate back to the server, so other players still see the
-- prompt. The prompt is re-enabled when the player stands up (Humanoid.Seated
-- fires with active=false).

local Players = game:GetService("Players")

local TablePromptSuppressor = {}

function TablePromptSuppressor.Start()
	local localPlayer = Players.LocalPlayer
	local disabled: { ProximityPrompt } = {}

	local function restore()
		for _, p in disabled do
			if p.Parent then
				p.Enabled = true
			end
		end
		table.clear(disabled)
	end

	local function onSeated(active: boolean, seatPart: BasePart?)
		restore()
		if not active or not seatPart then
			return
		end
		local tableModel = seatPart:FindFirstAncestorOfClass("Model")
		if not tableModel then
			return
		end
		for _, d in tableModel:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				d.Enabled = false
				table.insert(disabled, d)
			end
		end
	end

	local function hookCharacter(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 5)
		if not humanoid then return end
		humanoid.Seated:Connect(onSeated)
		if humanoid.SeatPart then
			onSeated(true, humanoid.SeatPart)
		end
	end

	localPlayer.CharacterAdded:Connect(hookCharacter)
	if localPlayer.Character then
		hookCharacter(localPlayer.Character)
	end
end

return TablePromptSuppressor
