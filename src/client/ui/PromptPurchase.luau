-- PromptPurchase
-- Thin wrapper around MarketplaceService:PromptProductPurchase /
-- :PromptGamePassPurchase that releases GuiService.SelectedObject before the
-- CoreGui purchase prompt opens and restores it when the prompt closes.
--
-- Why: our shop panels set SelectionGroup = true and pin SelectedObject to a
-- purchase button for controller navigation. When a native purchase prompt
-- opens on top, gamepad focus stays trapped on the pinned shop button and the
-- prompt's Buy/Close buttons are unreachable. Clearing SelectedObject before
-- the prompt opens lets CoreGui grab the gamepad; restoring after it closes
-- returns focus to the shop.

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")

local PromptPurchase = {}

-- Walk up from `from` collecting every ancestor GuiObject with
-- SelectionGroup = true. We temporarily clear them so CoreGui's PurchasePrompt
-- can grab gamepad focus; re-set on restore.
local function collectSelectionGroups(from: Instance?): { GuiObject }
	local groups: { GuiObject } = {}
	local cur = from
	while cur and cur ~= game do
		if cur:IsA("GuiObject") and cur.SelectionGroup then
			table.insert(groups, cur)
		end
		cur = cur.Parent
	end
	return groups
end

local function openPrompt(saved: Instance?, openFn: () -> (), finishedSignal: RBXScriptSignal, match: (any, any) -> boolean)
	local releasedGroups = collectSelectionGroups(saved)
	for _, g in releasedGroups do
		g.SelectionGroup = false
	end
	GuiService.SelectedObject = nil

	local function restore()
		task.delay(0.1, function()
			for _, g in releasedGroups do
				if g and g:IsDescendantOf(game) then
					g.SelectionGroup = true
				end
			end
			if saved and saved:IsDescendantOf(game) and saved:IsA("GuiObject") and saved.Visible then
				GuiService.SelectedObject = saved
			end
		end)
	end

	local conn
	conn = finishedSignal:Connect(function(a, b)
		if not match(a, b) then return end
		conn:Disconnect()
		restore()
	end)

	openFn()
end

function PromptPurchase.Product(player: Player, productId: number)
	local saved = GuiService.SelectedObject
	openPrompt(
		saved,
		function() MarketplaceService:PromptProductPurchase(player, productId) end,
		MarketplaceService.PromptProductPurchaseFinished,
		function(userId, id) return userId == player.UserId and id == productId end
	)
end

function PromptPurchase.GamePass(player: Player, gamePassId: number)
	local saved = GuiService.SelectedObject
	openPrompt(
		saved,
		function() MarketplaceService:PromptGamePassPurchase(player, gamePassId) end,
		MarketplaceService.PromptGamePassPurchaseFinished,
		function(finishedPlayer, id) return finishedPlayer == player and id == gamePassId end
	)
end

return PromptPurchase
