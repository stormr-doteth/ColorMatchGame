-- SafeSelect
-- Wraps GuiService.SelectedObject assignment with a validity check. Roblox
-- warns "Setting GuiService.SelectedObject to invalid GuiObject" if the
-- target is detached from the DataModel, its Selectable flag is false, or
-- any ancestor is hidden. This helper silently no-ops in those cases so
-- D-pad edge cases and race conditions (e.g. target unmounted between
-- search and set) don't spam the console.

local GuiService = game:GetService("GuiService")

local SafeSelect = {}

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
	if not target:IsDescendantOf(game) then return end
	if not target:IsA("GuiObject") then return end
	if not target.Selectable then return end
	if not target.Active then return end
	if not ancestorsVisible(target) then return end
	GuiService.SelectedObject = target
end

return SafeSelect
