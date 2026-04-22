-- WinsLeaderboardUI / Global leaderboard renderer
-- Renders the all-time Wins and Streak boards on the workspace billboards
-- (Workspace.Leaderboard.WinsLeaderboard, Workspace.Leaderboard.StreakLeaderboard).
-- Each SurfaceGui is tagged with a unique attribute so we can find it without
-- hardcoding which child of the multi-part model it lives on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WinsLeaderboardUI = {}

local BOARDS = {
	{
		modelName = "WinsLeaderboard",
		surfaceAttr = "WinsLeaderboardSurface",
		remoteName = "WinsLeaderboardUpdate",
	},
	{
		modelName = "StreakLeaderboard",
		surfaceAttr = "StreakLeaderboardSurface",
		remoteName = "StreakLeaderboardUpdate",
	},
}

local function findSurfaceGui(modelName: string, surfaceAttr: string): SurfaceGui?
	local lb = Workspace:FindFirstChild("Leaderboard")
	if not lb then return nil end
	local model = lb:FindFirstChild(modelName)
	if not model then return nil end
	for _, part in model:GetDescendants() do
		if part:IsA("SurfaceGui") and part:GetAttribute(surfaceAttr) then
			return part
		end
	end
	-- Fallback: any SurfaceGui under the model.
	for _, part in model:GetDescendants() do
		if part:IsA("SurfaceGui") then
			return part
		end
	end
	return nil
end

local function clearEntries(scroll: ScrollingFrame)
	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") and child.Name:sub(1, 6) == "Entry_" then
			child:Destroy()
		end
	end
end

local function placeColor(rank: number): Color3
	if rank == 1 then return Color3.fromRGB(255, 215, 0) end
	if rank == 2 then return Color3.fromRGB(200, 200, 200) end
	if rank == 3 then return Color3.fromRGB(205, 127, 50) end
	return Color3.fromRGB(255, 255, 255)
end

local function render(template: Frame, scroll: ScrollingFrame, entries: { any })
	clearEntries(scroll)
	for rank, data in entries do
		local userId = data.userId or data.UserID or 0
		local name = data.username or data.Username or ("Player" .. tostring(userId))
		local value = data.value or data.wins or data.Wins or data.streak or data.Streak or 0

		local entry = template:Clone()
		entry.Name = "Entry_" .. tostring(rank)
		entry.LayoutOrder = rank
		entry.Visible = true

		local nameLbl = entry:FindFirstChild("NameLabel")
		if nameLbl and nameLbl:IsA("TextLabel") then
			nameLbl.Text = name
			nameLbl.TextColor3 = placeColor(rank)
		end

		local winsLbl = entry:FindFirstChild("WinsLabel")
		if winsLbl and winsLbl:IsA("TextLabel") then
			winsLbl.Text = tostring(value)
			winsLbl.TextColor3 = placeColor(rank)
		end

		local placeLbl = entry:FindFirstChild("PlaceLabel")
		if placeLbl and placeLbl:IsA("TextLabel") then
			placeLbl.Text = tostring(rank)
			placeLbl.TextColor3 = placeColor(rank)
		end

		local img = entry:FindFirstChild("ImageLabel")
		if img and img:IsA("ImageLabel") and userId > 0 then
			img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=352&h=352"
		end

		entry.Parent = scroll
	end
end

local function startBoard(cfg)
	task.spawn(function()
		local surface: SurfaceGui? = nil
		local deadline = os.clock() + 15
		while os.clock() < deadline do
			surface = findSurfaceGui(cfg.modelName, cfg.surfaceAttr)
			if surface then break end
			task.wait(0.25)
		end
		if not surface then
			warn("[LeaderboardUI] SurfaceGui not found for " .. cfg.modelName)
			return
		end

		local template = surface:FindFirstChild("EntryTemplate")
		if not (template and template:IsA("Frame")) then
			warn("[LeaderboardUI] EntryTemplate not found for " .. cfg.modelName)
			return
		end
		template.Visible = false

		local scroll = surface:FindFirstChild("ScrollingFrame")
		if not (scroll and scroll:IsA("ScrollingFrame")) then
			warn("[LeaderboardUI] ScrollingFrame not found for " .. cfg.modelName)
			return
		end
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

		local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
		if not remotes then return end
		local updateRemote = remotes:WaitForChild(cfg.remoteName, 10)
		if not updateRemote then return end

		(updateRemote :: RemoteEvent).OnClientEvent:Connect(function(entries)
			if typeof(entries) ~= "table" then return end
			render(template :: Frame, scroll :: ScrollingFrame, entries)
		end)
	end)
end

function WinsLeaderboardUI.Start()
	for _, cfg in BOARDS do
		startBoard(cfg)
	end
end

return WinsLeaderboardUI
