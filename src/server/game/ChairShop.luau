-- ChairShop
-- Server-side bootstrap for the chair shop + inventory system.
--
-- Responsibilities:
--   1. Clone every catalog chair model from Workspace into a new
--      ReplicatedStorage.ChairTemplates folder so the server (and clients,
--      via replication) can spawn fresh instances on demand.
--   2. Attach a ProximityPrompt + BillboardGui (name + price) to each chair
--      in the world, so players can hold E to buy.
--   3. Listen for PurchaseChair / EquipChair remotes from clients and route
--      through ProfileService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChairCatalog = require(Shared:WaitForChild("ChairCatalog"))
local ProfileService = require(script.Parent.Parent:WaitForChild("data"):WaitForChild("ProfileService"))

local ChairShop = {}

local templatesFolder: Folder? = nil

local function getRemote(name: string): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild(name)
end

-- Clone the world chairs into a templates folder so the rest of the codebase
-- has a stable, untouchable source for fresh chair clones.
local function buildTemplates()
	local folder = ReplicatedStorage:FindFirstChild("ChairTemplates")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ChairTemplates"
		folder.Parent = ReplicatedStorage
	end
	for _, entry in ChairCatalog.GetAll() do
		if folder:FindFirstChild(entry.modelName) then
			continue
		end
		local source = Workspace:FindFirstChild(entry.modelName)
		if not source or not source:IsA("Model") then
			warn(`[ChairShop] Missing chair model in Workspace: {entry.modelName}`)
			continue
		end
		local clone = source:Clone()
		clone.Parent = folder
	end
	templatesFolder = folder
end

-- Returns a fresh clone of the chair model for `chairId`, or nil if the id
-- isn't in the catalog or the template hasn't been built. Caller is
-- responsible for parenting and positioning the result.
function ChairShop.CloneChair(chairId: string): Model?
	if not templatesFolder then
		return nil
	end
	local entry = ChairCatalog.Get(chairId)
	if not entry then
		return nil
	end
	local template = templatesFolder:FindFirstChild(entry.modelName)
	if not template or not template:IsA("Model") then
		return nil
	end
	return template:Clone()
end

local function findRootPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	-- Prefer the Seat as the root if present (so PivotTo positions sensibly).
	local seat = model:FindFirstChildWhichIsA("Seat", true)
	if seat then
		return seat
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function makeShopBillboard(parent: BasePart, entry)
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShopBillboard"
	bb.Adornee = parent
	bb.Size = UDim2.fromOffset(160, 70)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 60
	bb.Parent = parent

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Size = UDim2.new(1, 0, 0.5, 0)
	name.BackgroundTransparency = 1
	name.Text = entry.displayName
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.Parent = bb

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 2
	nameStroke.Parent = name

	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.Size = UDim2.new(1, 0, 0.45, 0)
	price.Position = UDim2.fromScale(0, 0.5)
	price.BackgroundTransparency = 1
	price.Text = `${entry.price}`
	price.TextColor3 = Color3.fromRGB(255, 215, 0)
	price.TextScaled = true
	price.Font = Enum.Font.FredokaOne
	price.Parent = bb

	local priceStroke = Instance.new("UIStroke")
	priceStroke.Color = Color3.fromRGB(0, 0, 0)
	priceStroke.Thickness = 2
	priceStroke.Parent = price
end

local function setupShopChair(entry, model: Model)
	local rootPart = findRootPart(model)
	if not rootPart then
		warn(`[ChairShop] No root part for {entry.modelName}`)
		return
	end

	-- Disable the seat so players can't accidentally sit on the shop chair.
	local seat = model:FindFirstChildWhichIsA("Seat", true)
	if seat then
		seat.Disabled = true
	end

	makeShopBillboard(rootPart, entry)

	-- Avoid duplicate prompt if the script reloads.
	local existing = rootPart:FindFirstChild("BuyPrompt")
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = entry.displayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(player)
		ChairShop.AttemptPurchase(player, entry.id)
	end)
end

-- Validate + execute a purchase. Silent on failure (proximity prompt has no
-- error pathway). The client will see the result via the next PlayerDataUpdate.
function ChairShop.AttemptPurchase(player: Player, chairId: string)
	local entry = ChairCatalog.Get(chairId)
	if not entry then
		return
	end
	local data = ProfileService.GetData(player)
	if not data then
		return
	end
	if ProfileService.OwnsChair(player, chairId) then
		return
	end
	if (data.Cash or 0) < entry.price then
		return
	end
	ProfileService.AddCash(player, -entry.price)
	ProfileService.AddChair(player, chairId)

	-- Notify the player that the purchase went through.
	local notifyRemote = getRemote("ShowNotification")
	if notifyRemote then
		(notifyRemote :: RemoteEvent):FireClient(player, `Purchased {entry.displayName}!`)
	end
end

local function bindRemotes()
	local purchase = getRemote("PurchaseChair")
	if purchase then
		(purchase :: RemoteEvent).OnServerEvent:Connect(function(player, chairId)
			if typeof(chairId) ~= "string" then
				return
			end
			ChairShop.AttemptPurchase(player, chairId)
		end)
	end
	local equip = getRemote("EquipChair")
	if equip then
		(equip :: RemoteEvent).OnServerEvent:Connect(function(player, chairId)
			if typeof(chairId) ~= "string" then
				return
			end
			-- Empty string = unequip; otherwise must own it
			ProfileService.SetEquippedChair(player, chairId)
		end)
	end
end

function ChairShop.Init()
	buildTemplates()
	for _, entry in ChairCatalog.GetAll() do
		local model = Workspace:FindFirstChild(entry.modelName)
		if model and model:IsA("Model") then
			setupShopChair(entry, model)
		end
	end
	bindRemotes()
end

return ChairShop
