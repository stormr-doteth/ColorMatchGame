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

local function restoreSelection(saved: Instance?)
	task.delay(0.1, function()
		if saved and saved:IsDescendantOf(game) then
			if saved:IsA("GuiObject") and saved.Visible then
				GuiService.SelectedObject = saved
			end
		end
	end)
end

function PromptPurchase.Product(player: Player, productId: number)
	local saved = GuiService.SelectedObject
	GuiService.SelectedObject = nil
	local conn
	-- PromptProductPurchaseFinished: (userId: number, productId: number, wasPurchased: boolean)
	conn = MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id)
		if userId ~= player.UserId or id ~= productId then return end
		conn:Disconnect()
		restoreSelection(saved)
	end)
	MarketplaceService:PromptProductPurchase(player, productId)
end

function PromptPurchase.GamePass(player: Player, gamePassId: number)
	local saved = GuiService.SelectedObject
	GuiService.SelectedObject = nil
	local conn
	-- PromptGamePassPurchaseFinished: (player: Player, gamePassId: number, wasPurchased: boolean)
	conn = MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(finishedPlayer, id)
		if finishedPlayer ~= player or id ~= gamePassId then return end
		conn:Disconnect()
		restoreSelection(saved)
	end)
	MarketplaceService:PromptGamePassPurchase(player, gamePassId)
end

return PromptPurchase
