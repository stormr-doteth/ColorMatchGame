-- SafeSelect
-- Wraps GuiService.SelectedObject assignment with a validity check. Roblox
-- warns "Setting GuiService.SelectedObject to invalid GuiObject" if the
-- target is detached from the DataModel, its Selectable flag is false, or
-- any ancestor is hidden. This helper silently no-ops in those cases so
-- D-pad edge cases and race conditions (e.g. target unmounted between
-- search and set) don't spam the console.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local SafeSelect = {}

-- Gamepad selection draws a visible highlight ring around the focused button.
-- On touch/mouse that ring shouldn't appear — it looks like a stuck hover and
-- implies the UI is being cycled by a controller. We treat "gamepad mode" as
-- the last input being a gamepad button/thumbstick. If a player switches back
-- to touch/mouse after we've set a selection, clear it so the ring disappears.
local function isGamepadMode(): boolean
	local lit = UserInputService:GetLastInputType()
	return lit == Enum.UserInputType.Gamepad1
		or lit == Enum.UserInputType.Gamepad2
		or lit == Enum.UserInputType.Gamepad3
		or lit == Enum.UserInputType.Gamepad4
		or lit == Enum.UserInputType.Gamepad5
		or lit == Enum.UserInputType.Gamepad6
		or lit == Enum.UserInputType.Gamepad7
		or lit == Enum.UserInputType.Gamepad8
end

UserInputService.LastInputTypeChanged:Connect(function()
	if not isGamepadMode() and GuiService.SelectedObject then
		GuiService.SelectedObject = nil
	end
end)

local function ancestorsVisible(obj: GuiObject): boolean
	local cur: Instance? = obj
	while cur and cur ~= game do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return true
end

function SafeSelect.Set(target: GuiObject?)
	if target == nil then
		GuiService.SelectedObject = nil
		return
	end
	-- On mobile/desktop, assigning SelectedObject paints a visible gamepad
	-- highlight ring that has no business being there. Only honor selection
	-- requests while the player is actually using a gamepad.
	if not isGamepadMode() then return end
	if not target:IsDescendantOf(game) then return end
	if not target:IsA("GuiObject") then return end
	if not target.Selectable then return end
	if not target.Active then return end
	if not ancestorsVisible(target) then return end
	GuiService.SelectedObject = target
end

return SafeSelect
