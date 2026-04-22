-- ChairDisplays
-- Finds `ChairDisplay_<Tier>` models in Workspace, places loot chairs from the
-- matching lucky block onto their ChairStand parts, and attaches a single
-- ProximityPrompt per stand that opens the block's shop UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))

local ChairShop = require(script.Parent:WaitForChild("ChairShop"))

-- Suffix (case-insensitive) → lucky block id
local DISPLAY_MAP: { [string]: string } = {
	common = "common_block",
	uncommon = "uncommon_block",
	rare = "rare_block",
	epic = "epic_block",
	legendary = "legendary_block",
	storm = "stormbringer_block",
	stormbringer = "stormbringer_block",
	glacial = "glacial_block",
}

local ChairDisplays = {}

local function getRemote(name: string): RemoteEvent?
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then return nil end
	return remotes:WaitForChild(name, 10)
end

local function findStands(displayModel: Model): { BasePart }
	local stands: { BasePart } = {}
	for _, desc in displayModel:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name:sub(1, 10) == "ChairStand" then
			table.insert(stands, desc)
		end
	end
	table.sort(stands, function(a, b) return a.Name < b.Name end)
	return stands
end

local function findNameDisplays(displayModel: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in displayModel:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name:sub(1, 11) == "NameDisplay" then
			table.insert(parts, desc)
		end
	end
	table.sort(parts, function(a, b) return a.Name < b.Name end)
	return parts
end

local function placeChairOnStand(chairId: string, stand: BasePart, parent: Instance): Model?
	local chair = ChairShop.CloneChair(chairId)
	if not chair then
		warn(`[ChairDisplays] Missing chair model: {chairId}`)
		return nil
	end

	-- Disable seat so players can't sit on display chairs
	for _, d in chair:GetDescendants() do
		if d:IsA("Seat") then
			d.Disabled = true
		end
	end

	-- Anchor + non-collide everything so the chair rests cleanly on the stand
	for _, d in chair:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	-- First pass: place chair roughly above the stand using the bounding box.
	local _, size = chair:GetBoundingBox()
	local topY = stand.Position.Y + stand.Size.Y / 2
	-- Display yaw: chairs on shop stands should face forward regardless of
	-- `flipSeat` (which is for in-table seating). Mirror the viewport
	-- convention: if `viewportFlip` is explicitly set, honor it; otherwise
	-- default to no flip so displays match how the chair was authored.
	local entry = ChairCatalog.Get(chairId)
	local shouldFlip = entry and entry.viewportFlip == true
	local yaw = shouldFlip and math.pi or 0
	chair:PivotTo(CFrame.new(stand.Position.X, topY + size.Y / 2, stand.Position.Z) * CFrame.Angles(0, yaw, 0))

	-- Second pass: find the lowest visible part (skip invisible VFX anchor
	-- parts so auras/trails don't throw off the bottom) and shift the chair so
	-- that lowest point rests exactly on the stand's top surface.
	-- Use the true world-space AABB per part (8 rotated corners) because many
	-- chair parts are tilted and `Position.Y - Size.Y/2` only holds for
	-- axis-aligned parts.
	local lowestY = math.huge
	for _, d in chair:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf = d.CFrame
			local sx, sy, sz = d.Size.X / 2, d.Size.Y / 2, d.Size.Z / 2
			for ix = -1, 1, 2 do
				for iy = -1, 1, 2 do
					for iz = -1, 1, 2 do
						local corner = cf * Vector3.new(ix * sx, iy * sy, iz * sz)
						if corner.Y < lowestY then
							lowestY = corner.Y
						end
					end
				end
			end
		end
	end
	if lowestY ~= math.huge then
		local correction = topY - lowestY
		chair:PivotTo(chair:GetPivot() + Vector3.new(0, correction, 0))
	end

	-- Per-chair display-stand Y nudge (for chairs whose computed bottom
	-- doesn't visually match due to hidden anchor/hitbox parts).
	if entry and entry.displayYOffset and entry.displayYOffset ~= 0 then
		chair:PivotTo(chair:GetPivot() + Vector3.new(0, entry.displayYOffset, 0))
	end

	chair.Parent = parent
	return chair
end

local function makeChairBillboard(adornee: BasePart, chairId: string, chance: number)
	local catalogEntry = ChairCatalog.Get(chairId)
	if not catalogEntry then return end

	local existing = adornee:FindFirstChild("ChairBillboard")
	if existing then existing:Destroy() end

	local bb = Instance.new("BillboardGui")
	bb.Name = "ChairBillboard"
	bb.Adornee = adornee
	bb.Size = UDim2.new(5, 0, 2.2, 0) -- studs-based, scales with distance
	bb.StudsOffset = Vector3.new(0, 1, 0)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 60
	bb.Parent = adornee

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, 0, 0.55, 0)
	nameLbl.Position = UDim2.fromScale(0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = catalogEntry.displayName
	nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLbl.TextScaled = true
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.Parent = bb

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 2.5
	nameStroke.Parent = nameLbl

	local chanceLbl = Instance.new("TextLabel")
	chanceLbl.Size = UDim2.new(1, 0, 0.45, 0)
	chanceLbl.Position = UDim2.fromScale(0, 0.55)
	chanceLbl.BackgroundTransparency = 1
	chanceLbl.Text = string.format("%d%% Chance", chance)
	chanceLbl.TextColor3 = Color3.fromRGB(255, 215, 0)
	chanceLbl.TextScaled = true
	chanceLbl.Font = Enum.Font.FredokaOne
	chanceLbl.Parent = bb

	local chanceStroke = Instance.new("UIStroke")
	chanceStroke.Color = Color3.fromRGB(0, 0, 0)
	chanceStroke.Thickness = 2.5
	chanceStroke.Parent = chanceLbl
end

local function attachShopPrompt(stand: BasePart, entry)
	local existing = stand:FindFirstChild("BlockPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BlockPrompt"
	prompt.ActionText = "Shop"
	prompt.ObjectText = entry.displayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	prompt.Triggered:Connect(function(player)
		local remoteName = if entry.shopType == "cosmetics" then "OpenCosmeticsShop" else "OpenLuckyBlockShop"
		local shopRemote = getRemote(remoteName)
		if shopRemote then
			(shopRemote :: RemoteEvent):FireClient(player, entry.id)
		end
	end)
end

local function buildDisplay(displayModel: Model)
	local suffix = displayModel.Name:match("ChairDisplay_(.+)")
	if not suffix then return end

	local blockId = DISPLAY_MAP[suffix:lower()]
	if not blockId then
		warn(`[ChairDisplays] No block mapped for "{displayModel.Name}"`)
		return
	end

	local entry = LuckyBlockCatalog.Get(blockId)
	if not entry then return end

	local stands = findStands(displayModel)
	if #stands == 0 then
		warn(`[ChairDisplays] No ChairStand parts in {displayModel.Name}`)
		return
	end

	-- Loot chairs sorted by weight descending (rarest last so they land on later stands)
	local sortedLoot = table.clone(entry.lootTable)
	table.sort(sortedLoot, function(a, b) return a.weight > b.weight end)

	local chances = LuckyBlockCatalog.GetChances(entry.id)
	local nameDisplays = findNameDisplays(displayModel)

	for i, stand in stands do
		local loot = sortedLoot[i]
		if not loot then break end
		placeChairOnStand(loot.chairId, stand, displayModel)
		attachShopPrompt(stand, entry)
		local nameDisplay = nameDisplays[i]
		if nameDisplay then
			makeChairBillboard(nameDisplay, loot.chairId, chances[loot.chairId] or 0)
		end
	end
end

function ChairDisplays.Init()
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("Model") and inst.Name:sub(1, 13) == "ChairDisplay_" then
			buildDisplay(inst)
		end
	end

	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") and inst.Name:sub(1, 13) == "ChairDisplay_" then
			task.wait(0.1)
			buildDisplay(inst)
		end
	end)
end

return ChairDisplays
