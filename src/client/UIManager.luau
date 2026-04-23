-- UIManager
-- Ensures only one full-screen UI panel is open at a time.
-- Each panel registers with a close callback. When any panel opens,
-- all other panels are closed first.

local ContextActionService = game:GetService("ContextActionService")

local UIManager = {}

local panels: { { name: string, close: () -> (), isOpen: () -> boolean } } = {}

function UIManager.Register(name: string, closeFn: () -> (), isOpenFn: () -> boolean)
	table.insert(panels, { name = name, close = closeFn, isOpen = isOpenFn })
end

-- Call before opening a panel to close any others that are open.
function UIManager.CloseOthers(exceptName: string)
	for _, panel in panels do
		if panel.name ~= exceptName and panel.isOpen() then
			panel.close()
		end
	end
end

-- Close every currently open registered panel. Returns true if at least one
-- panel was closed. Used by the global controller ButtonB bind.
function UIManager.CloseAll(): boolean
	local closedAny = false
	for _, panel in panels do
		if panel.isOpen() then
			panel.close()
			closedAny = true
		end
	end
	return closedAny
end

local buttonBBound = false
function UIManager.BindControllerClose()
	if buttonBBound then return end
	buttonBBound = true
	ContextActionService:BindAction("UIManager_ControllerClose", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if UIManager.CloseAll() then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonB)
end

return UIManager
