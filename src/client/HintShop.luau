local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local NotificationHud = require(script.Parent:WaitForChild("NotificationHud"))
local PromptPurchase = require(script.Parent:WaitForChild("ui"):WaitForChild("PromptPurchase"))

local MIN_GUESS_TIME_TO_USE = 3 -- seconds remaining required to use a hint during guessing

local HintShop = {}

function HintShop.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local isSolo = false
	local hintCount = 0
	local matchColorCount = 0
	local gamepassSpam: Frame? = nil
	local itemLabel: TextLabel? = nil
	local robuxLabel: TextLabel? = nil
	local itemImage: ImageLabel? = nil
	local item2Label: TextLabel? = nil
	local item2RobuxLabel: TextLabel? = nil
	local item2Image: ImageLabel? = nil
	local originalLabelText = "HINT"
	local originalRobuxText = ""
	local original2LabelText = "MATCH"
	local original2RobuxText = ""
	local connections: { RBXScriptConnection } = {}

	-- Phase/timing tracking for edge case protection
	local currentPhase = "idle" -- "showing" | "guessing" | "idle"
	local guessStartTime = 0 -- os.clock() when guessing began

	local function getGuessTimeLeft(): number
		if currentPhase ~= "guessing" then
			return 999 -- not in guessing, no restriction
		end
		return math.max(0, Constants.GUESS_TIMEOUT - (os.clock() - guessStartTime))
	end

	local function updateButtonText()
		if not itemLabel then return end
		if hintCount > 0 then
			itemLabel.Text = `Use Hint ({hintCount})`
			if robuxLabel then
				robuxLabel.Visible = false
			end
		else
			itemLabel.Text = originalLabelText
			if robuxLabel then
				robuxLabel.Visible = true
			end
		end
	end

	local function updateItem2Text()
		if not item2Label then return end
		if matchColorCount > 0 then
			item2Label.Text = `Use Match ({matchColorCount})`
			if item2RobuxLabel then
				item2RobuxLabel.Visible = false
			end
		else
			item2Label.Text = original2LabelText
			if item2RobuxLabel then
				item2RobuxLabel.Visible = true
			end
		end
	end

	local function onItem2Clicked()
		if matchColorCount > 0 then
			if currentPhase ~= "guessing" then
				return -- can only use during guessing (sliders must be visible)
			end
			if getGuessTimeLeft() < MIN_GUESS_TIME_TO_USE then
				return
			end
			matchColorCount -= 1
			localPlayer:SetAttribute("MatchColorActive", true)
			updateItem2Text()
			NotificationHud.Show("Match Color activated!")
			ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UseMatch"):FireServer()
		else
			PromptPurchase.Product(localPlayer, Constants.MATCH_COLOR_PRODUCT_ID)
		end
	end

	local function onItem1Clicked()
		if hintCount > 0 then
			-- Use a hint
			if currentPhase == "idle" then
				return -- not in a round
			end
			if currentPhase == "guessing" and getGuessTimeLeft() < MIN_GUESS_TIME_TO_USE then
				return -- too little time left, don't waste it
			end
			hintCount -= 1
			localPlayer:SetAttribute("HintActive", true)
			updateButtonText()
			NotificationHud.Show("Hint activated!")
			ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UseHint"):FireServer()
		else
			-- Purchase a hint
			PromptPurchase.Product(localPlayer, Constants.HINT_PRODUCT_ID)
		end
	end

	local function resolveGui()
		local screenGui = playerGui:WaitForChild("ScreenGui", 10)
		if not screenGui then
			warn("[HintShop] ScreenGui not found")
			return
		end

		local spam = screenGui:WaitForChild("GamepassSpam", 10) :: Frame?
		if not spam then
			warn("[HintShop] GamepassSpam not found in ScreenGui")
			return
		end
		gamepassSpam = spam
		gamepassSpam.Visible = false

		-- Only Hint (Item1) and Match (Item2) are supported. Hide any extra
		-- Studio-authored slots (Item3, Item4, ...) so they don't render.
		for _, child in spam:GetChildren() do
			if child:IsA("GuiObject") then
				local n = child.Name
				if n:sub(1, 4) == "Item" and n ~= "Item1" and n ~= "Item2" then
					child.Visible = false
				end
			end
		end

		local item1 = spam:WaitForChild("Item1", 5) :: Frame?
		if not item1 then
			warn("[HintShop] Item1 not found in GamepassSpam")
			return
		end

		-- Set up labels and image
		itemLabel = item1:FindFirstChild("ItemLabel") :: TextLabel?
		robuxLabel = item1:FindFirstChild("RobuxLabel") :: TextLabel?
		itemImage = item1:FindFirstChild("ItemImage") :: ImageLabel?
		if itemLabel then
			itemLabel.Text = "HINT"
		end
		if robuxLabel then
			robuxLabel.Text = utf8.char(0xE002) .. " 9"
			originalRobuxText = robuxLabel.Text
		end

		-- Dancing magnifying glass animation loop
		if itemImage then
			task.spawn(function()
				local startTime = os.clock()
				while true do
					if gamepassSpam and gamepassSpam.Visible then
						local t = os.clock() - startTime
						itemImage.Rotation = 15 * math.sin(t * 3) + 8 * math.sin(t * 7)
						task.wait()
					else
						if itemImage then
							itemImage.Rotation = 0
						end
						task.wait(0.2)
					end
				end
			end)
		end

		-- Add transparent click overlay (Item1 is a Frame, not a button)
		local clickButton = Instance.new("TextButton")
		clickButton.Name = "HintClickArea"
		clickButton.Size = UDim2.fromScale(1, 1)
		clickButton.BackgroundTransparency = 1
		clickButton.Text = ""
		clickButton.ZIndex = 10
		clickButton.Selectable = true
		clickButton.Parent = item1

		table.insert(connections, clickButton.Activated:Connect(onItem1Clicked))

		-- Item2: Match Color
		local item2 = spam:FindFirstChild("Item2") :: Frame?
		if item2 then
			item2Label = item2:FindFirstChild("ItemLabel") :: TextLabel?
			item2RobuxLabel = item2:FindFirstChild("RobuxLabel") :: TextLabel?
			item2Image = item2:FindFirstChild("ItemImage") :: ImageLabel?
			if item2Image then
				item2Image.Image = "rbxassetid://122361035967380"
			end
			if item2Label then
				item2Label.Text = "MATCH"
			end
			if item2RobuxLabel then
				original2RobuxText = item2RobuxLabel.Text
			end

			-- Dancing animation for Item2 image
			if item2Image then
				task.spawn(function()
					local startTime = os.clock()
					while true do
						if gamepassSpam and gamepassSpam.Visible then
							local t = os.clock() - startTime
							item2Image.Rotation = 12 * math.sin(t * 4) + 6 * math.sin(t * 9)
							task.wait()
						else
							if item2Image then
								item2Image.Rotation = 0
							end
							task.wait(0.2)
						end
					end
				end)
			end

			local click2 = Instance.new("TextButton")
			click2.Name = "MatchColorClickArea"
			click2.Size = UDim2.fromScale(1, 1)
			click2.BackgroundTransparency = 1
			click2.Text = ""
			click2.ZIndex = 10
			click2.Selectable = true
			click2.Parent = item2

			table.insert(connections, click2.Activated:Connect(onItem2Clicked))
		end
	end

	local function setVisible(visible: boolean)
		if gamepassSpam then
			gamepassSpam.Visible = visible
		end
		if not visible then
			if itemImage then
				itemImage.Rotation = 0
			end
			if item2Image then
				item2Image.Rotation = 0
			end
		end
	end

	-- Remote listeners
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	table.insert(connections, remotes:WaitForChild("MatchStart").OnClientEvent:Connect(function(data)
		isSolo = data.solo or false
		currentPhase = "idle"
		setVisible(false)
	end))

	table.insert(connections, remotes:WaitForChild("RoundShowColor").OnClientEvent:Connect(function()
		currentPhase = "showing"
		localPlayer:SetAttribute("HintActive", false)
		localPlayer:SetAttribute("MatchColorActive", false)
		updateButtonText()
		updateItem2Text()
		if not isSolo then
			setVisible(true)
		end
	end))

	table.insert(connections, remotes:WaitForChild("RoundGuessPhase").OnClientEvent:Connect(function()
		currentPhase = "guessing"
		guessStartTime = os.clock()
	end))

	table.insert(connections, remotes:WaitForChild("RoundResult").OnClientEvent:Connect(function()
		currentPhase = "idle"
		setVisible(false)
	end))

	table.insert(connections, remotes:WaitForChild("MatchEnd").OnClientEvent:Connect(function()
		currentPhase = "idle"
		setVisible(false)
	end))

	table.insert(connections, remotes:WaitForChild("HintActivated").OnClientEvent:Connect(function()
		NotificationHud.Show("Hint purchased!")
	end))

	table.insert(connections, remotes:WaitForChild("MatchColorActivated").OnClientEvent:Connect(function()
		NotificationHud.Show("Match Color purchased!")
	end))

	table.insert(connections, remotes:WaitForChild("PlayerDataUpdate").OnClientEvent:Connect(function(data)
		if not data then return end
		hintCount = data.Hints or 0
		matchColorCount = data.Matches or 0
		updateButtonText()
		updateItem2Text()
	end))

	resolveGui()
end

return HintShop
