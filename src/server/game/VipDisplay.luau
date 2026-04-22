-- VipDisplay
-- Places the VIP Throne on Workspace.VipDisplay, hovers + rotates it, adds
-- billboard signage listing the VIP perks, and attaches a ProximityPrompt that
-- prompts the VIP gamepass purchase.

local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChairCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChairCatalog"))

local ChairShop = require(script.Parent:WaitForChild("ChairShop"))
local GamePassUtil = require(script.Parent:WaitForChild("GamePassUtil"))

local VipDisplay = {}

local HOVER_AMPLITUDE = 0.5   -- studs — sine oscillates between 0 and 2*amp
local HOVER_PERIOD = 3
local ROTATION_SPEED = 20     -- degrees/sec
local CHAIR_LIFT = 1          -- studs lifted above the stand
local BILLBOARD_LIFT = 11     -- studs from stand center to billboard

local VIP_PASS_ID = GamePassUtil.GetPassId("VIP") or 1796710377

local function findStand(display: Instance): BasePart?
	for _, d in display:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, 10) == "ChairStand" then
			return d
		end
	end
	return display:FindFirstChildWhichIsA("BasePart", true)
end

local function placeOnStand(chair: Model, stand: BasePart)
	for _, d in chair:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
		if d:IsA("Seat") then
			d.Disabled = true
		end
	end

	local _, size = chair:GetBoundingBox()
	local topY = stand.Position.Y + stand.Size.Y / 2
	-- Match ChairDisplays convention: if the catalog entry declares a
	-- `viewportFlip` preference, apply that yaw so the display orientation
	-- lines up with how every other shop chair is presented.
	local entry = ChairCatalog.Get("vip_throne")
	local shouldFlip = entry and entry.viewportFlip == true
	local yaw = shouldFlip and math.pi or 0
	chair:PivotTo(CFrame.new(stand.Position.X, topY + size.Y / 2, stand.Position.Z) * CFrame.Angles(0, yaw, 0))

	local lowestY = math.huge
	for _, d in chair:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local bottom = d.Position.Y - d.Size.Y / 2
			if bottom < lowestY then
				lowestY = bottom
			end
		end
	end
	if lowestY ~= math.huge then
		local correction = topY - lowestY
		chair:PivotTo(chair:GetPivot() + Vector3.new(0, correction, 0))
	end
end

local function makeLabel(parent: Instance, text: string, color: Color3, scaleY: number, posY: number)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, scaleY, 0)
	lbl.Position = UDim2.fromScale(0, posY)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextScaled = true
	lbl.Font = Enum.Font.FredokaOne
	lbl.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.5
	stroke.Parent = lbl
end

local function makeBillboard(adornee: BasePart)
	local bb = Instance.new("BillboardGui")
	bb.Name = "VipSign"
	bb.Adornee = adornee
	-- Studs-based size so the sign shrinks with distance (matches TableManager UI)
	bb.Size = UDim2.new(7, 0, 5, 0)
	bb.StudsOffset = Vector3.new(0, BILLBOARD_LIFT, 0)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 80
	bb.Parent = adornee

	makeLabel(bb, "⭐ VIP ⭐",            Color3.fromRGB(255, 215, 0),  0.35, 0.00)
	makeLabel(bb, "VIP Throne",           Color3.fromRGB(255, 255, 255), 0.22, 0.38)
	makeLabel(bb, "[VIP] Chat Tag",        Color3.fromRGB(140, 220, 255), 0.22, 0.60)
	makeLabel(bb, "1.5x Cash Rewards",     Color3.fromRGB(140, 255, 180), 0.22, 0.82)
end

local function attachPrompt(stand: BasePart)
	local existing = stand:FindFirstChild("VipPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VipPrompt"
	prompt.ActionText = "Buy VIP"
	prompt.ObjectText = "VIP Gamepass"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	prompt.Triggered:Connect(function(player)
		MarketplaceService:PromptGamePassPurchase(player, VIP_PASS_ID)
	end)
end

function VipDisplay.Init()
	local display = Workspace:FindFirstChild("VipDisplay") or Workspace:FindFirstChild("vipDisplay")
	if not display then
		return
	end

	local stand = findStand(display)
	if not stand then
		warn("[VipDisplay] No stand part inside VipDisplay")
		return
	end

	local chair = ChairShop.CloneChair("vip_throne")
	if not chair then
		warn("[VipDisplay] Failed to clone vip_throne")
		return
	end

	chair.Parent = display
	placeOnStand(chair, stand)

	-- basePivot = chair lifted CHAIR_LIFT studs above the stand so it hovers
	-- clearly above the platform. Oscillation adds a non-negative yOffset.
	local basePivot = chair:GetPivot() + Vector3.new(0, CHAIR_LIFT, 0)
	local startTime = os.clock()

	RunService.Heartbeat:Connect(function()
		if not chair.Parent then return end
		local t = os.clock() - startTime
		local yOffset = (1 - math.cos(t * math.pi * 2 / HOVER_PERIOD)) * HOVER_AMPLITUDE
		local angle = math.rad(t * ROTATION_SPEED)
		chair:PivotTo(basePivot * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, angle, 0))
	end)

	makeBillboard(stand)
	attachPrompt(stand)
end

return VipDisplay
