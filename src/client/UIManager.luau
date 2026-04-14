-- UIManager
-- Ensures only one full-screen UI panel is open at a time.
-- Each panel registers with a close callback. When any panel opens,
-- all other panels are closed first.

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

return UIManager
