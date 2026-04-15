-- GamepassSpamRotator
-- Rotates promotional items in the "IngameAds" frame on the right side of the
-- screen. Always visible in the lobby. Each promo shows for a set duration
-- then swaps to the next.
--
-- Separate from GamepassSpam (which HintShop uses during rounds for hints).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local ROTATE_INTERVAL = 8 -- seconds per promo before rotating

type PromoItem = {
	label: string,
	robuxText: string,
	image: string,
	onClick: ((Player) -> ())?,
}

type PromoEntry = {
	id: string,
	items: { PromoItem },
}

local GamepassSpamRotator = {}

function GamepassSpamRotator.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("ScreenGui", 10)
	if not screenGui then
		warn("[GamepassSpamRotator] ScreenGui not found")
		return
	end

	local adsFrame = screenGui:WaitForChild("IngameAds", 10) :: Frame?
	if not adsFrame then
		warn("[GamepassSpamRotator] IngameAds not found")
		return
	end

	local starterPackFrame = screenGui:FindFirstChild("StarterPack") :: Frame?

	-- Collect item slots
	local itemSlots: { Frame } = {}
	for i = 1, 3 do
		local slot = adsFrame:FindFirstChild("Item" .. i) :: Frame?
		if slot then
			table.insert(itemSlots, slot)
		end
	end

	---------------------------------------------------------------------------
	-- StarterPack wiring
	---------------------------------------------------------------------------
	if starterPackFrame then
		starterPackFrame.Visible = false
		local header = starterPackFrame:FindFirstChild("Header")
		if header then
			local closeBtn = header:FindFirstChild("CloseButton") :: ImageButton?
			if closeBtn then
				closeBtn.Activated:Connect(function()
					starterPackFrame.Visible = false
				end)
			end
		end

		local submitFrame = starterPackFrame:FindFirstChild("SubmitButton")
		if submitFrame then
			local submitBtn = submitFrame:FindFirstChild("SubmitButton") :: TextButton?
			if submitBtn then
				submitBtn.Activated:Connect(function()
					MarketplaceService:PromptGamePassPurchase(localPlayer, 1796993729)
				end)
			end
		end
	end

	---------------------------------------------------------------------------
	-- Promo library
	---------------------------------------------------------------------------
	local promos: { PromoEntry } = {
		{
			id = "starter_pack",
			items = {
				{
					label = "Starter Pack",
					robuxText = "",
					image = "",
					onClick = function(_player)
						if starterPackFrame then
							starterPackFrame.Visible = true
						end
					end,
				},
			},
		},
		{
			id = "double_cash",
			items = {
				{
					label = "2x Cash",
					robuxText = " 99",
					image = "",
					onClick = function(player)
						MarketplaceService:PromptGamePassPurchase(player, 1797672278)
					end,
				},
			},
		},
		{
			id = "double_wins",
			items = {
				{
					label = "2x Wins",
					robuxText = " 99",
					image = "",
					onClick = function(player)
						MarketplaceService:PromptGamePassPurchase(player, 1796963414)
					end,
				},
			},
		},
		{
			id = "vip",
			items = {
				{
					label = "VIP",
					robuxText = " 49",
					image = "",
					onClick = function(player)
						MarketplaceService:PromptGamePassPurchase(player, 1796710377)
					end,
				},
			},
		},
	}

	---------------------------------------------------------------------------
	-- Click wiring
	---------------------------------------------------------------------------
	local activeConnections: { RBXScriptConnection } = {}

	local function clearConnections()
		for _, conn in activeConnections do
			conn:Disconnect()
		end
		table.clear(activeConnections)
	end

	local function applyPromo(promo: PromoEntry)
		clearConnections()

		for i, slot in itemSlots do
			local promoItem = promo.items[i]
			if promoItem then
				slot.Visible = true
				local lbl = slot:FindFirstChild("ItemLabel") :: TextLabel?
				local rbx = slot:FindFirstChild("RobuxLabel") :: TextLabel?
				local img = slot:FindFirstChild("ItemImage") :: ImageButton?

				if lbl then
					lbl.Text = promoItem.label
				end
				if rbx then
					if promoItem.robuxText ~= "" then
						rbx.Text = promoItem.robuxText
						rbx.Visible = true
					else
						rbx.Visible = false
					end
				end
				if img and promoItem.image ~= "" then
					img.Image = promoItem.image
				end

				-- Transparent click overlay
				local clickArea = slot:FindFirstChild("PromoClickArea")
				if not clickArea then
					local btn = Instance.new("TextButton")
					btn.Name = "PromoClickArea"
					btn.Size = UDim2.fromScale(1, 1)
					btn.BackgroundTransparency = 1
					btn.Text = ""
					btn.ZIndex = 10
					btn.Parent = slot
					clickArea = btn
				end

				if promoItem.onClick then
					local conn = (clickArea :: TextButton).Activated:Connect(function()
						promoItem.onClick(localPlayer)
					end)
					table.insert(activeConnections, conn)
				end
			else
				slot.Visible = false
			end
		end
	end

	---------------------------------------------------------------------------
	-- Rotation loop — always visible, no round coordination needed
	---------------------------------------------------------------------------
	adsFrame.Visible = true

	task.spawn(function()
		local index = 1
		while true do
			index = ((index - 1) % #promos) + 1
			applyPromo(promos[index])

			task.wait(ROTATE_INTERVAL)
			index += 1
		end
	end)
end

return GamepassSpamRotator
