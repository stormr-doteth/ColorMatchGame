-- LuckyBlockHotbar
-- Custom replacement for Roblox's default hotbar, just for lucky-block tools.
-- Unlike the built-in hotbar (which shows one slot per Tool instance and caps
-- at 3 slots on mobile), this stacks duplicate blocks into a single slot with
-- a count badge, so players always see everything they own at a glance.
--
-- Data flow:
--   * Per-type counts come from profile.LuckyBlocks via PlayerDataUpdate.
--   * Equip/unequip is done client-side by finding a matching Tool instance
--     in Backpack/Character and using Humanoid:EquipTool / UnequipTools.
--   * The Tool instances still come from LuckyBlockShop.GrantTool on the
--     server — we just present them differently.
--
-- The default CoreGui Backpack is disabled so this is the only hotbar the
-- player sees.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LuckyBlockCatalog = require(Shared:WaitForChild("LuckyBlockCatalog"))

local LuckyBlockHotbar = {}

local localPlayer = Players.LocalPlayer
local started = false

-- Max hotbar slots by platform. Beyond this, overflow goes into the expanded
-- panel. The hotbar also shrinks *below* this if the player owns fewer types —
-- we only render one slot per unique block they actually have.
local MAX_SLOTS_MOBILE = 3
local MAX_SLOTS_DESKTOP = 10

-- Slot height as a fraction of screen height. Aspect-ratio constraint keeps
-- slots square. Mobile gets a slightly taller slot for comfortable tap.
local SLOT_HEIGHT_SCALE_MOBILE = 0.085
local SLOT_HEIGHT_SCALE_DESKTOP = 0.075

-- Rarity tint applied by block id prefix (common_block, rare_block, etc).
local RARITY_BY_PREFIX: { [string]: { top: Color3, bottom: Color3, stroke: Color3 } } = {
	common       = { top = Color3.fromRGB(170, 175, 180), bottom = Color3.fromRGB(70, 75, 80),    stroke = Color3.fromRGB(200, 205, 210) },
	uncommon     = { top = Color3.fromRGB(90, 220, 110),  bottom = Color3.fromRGB(30, 110, 50),   stroke = Color3.fromRGB(130, 255, 150) },
	rare         = { top = Color3.fromRGB(80, 150, 255),  bottom = Color3.fromRGB(25, 65, 160),   stroke = Color3.fromRGB(120, 190, 255) },
	epic         = { top = Color3.fromRGB(200, 100, 255), bottom = Color3.fromRGB(95, 30, 160),   stroke = Color3.fromRGB(220, 140, 255) },
	legendary    = { top = Color3.fromRGB(255, 180, 60),  bottom = Color3.fromRGB(180, 90, 0),    stroke = Color3.fromRGB(255, 215, 100) },
	glacial      = { top = Color3.fromRGB(140, 230, 255), bottom = Color3.fromRGB(40, 110, 170),  stroke = Color3.fromRGB(180, 240, 255) },
	stormbringer = { top = Color3.fromRGB(180, 120, 255), bottom = Color3.fromRGB(60, 20, 120),   stroke = Color3.fromRGB(210, 160, 255) },
}

local function rarityFor(blockId: string)
	local prefix = blockId:match("^(.-)_block") or blockId
	return RARITY_BY_PREFIX[prefix] or RARITY_BY_PREFIX.common
end

-- Treat a device as mobile if touch is available AND the viewport is narrow.
-- The old check required TouchEnabled with *no* keyboard/mouse — but Studio's
-- device emulator exposes all three as true (it fakes touch on top of the host
-- mouse/keyboard), so the emulator always looked like desktop. Using viewport
-- width lets the emulator's simulated screen sizes flip us to the mobile layout
-- while still keeping real desktops on the desktop layout.
--
-- Dev override: setting `_G.DEV_FORCE_MOBILE = true` (or the PlayerGui
-- attribute "DevForceMobile") forces the mobile layout regardless of viewport
-- or device. This is the bulletproof way to test mobile in Studio when the
-- device emulator's viewport detection is flaky.
local function isTouchOnly(): boolean
	if _G.DEV_FORCE_MOBILE == true then return true end
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	if pg and pg:GetAttribute("DevForceMobile") == true then return true end
	if not UserInputService.TouchEnabled then return false end
	local camera = workspace.CurrentCamera
	local viewportX = if camera then camera.ViewportSize.X else 1920
	-- ~iPad landscape is 1180px; phones are well below that.
	return viewportX < 1200
end

---------------------------------------------------------------------------
-- Tool helpers: find, equip, unequip by blockId
---------------------------------------------------------------------------

local function toolNameFor(blockId: string): string
	return "LuckyBlock_" .. blockId
end

local function findTool(blockId: string): Tool?
	local name = toolNameFor(blockId)
	local character = localPlayer.Character
	if character then
		local t = character:FindFirstChild(name)
		if t and t:IsA("Tool") then return t end
	end
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		local t = backpack:FindFirstChild(name)
		if t and t:IsA("Tool") then return t end
	end
	return nil
end

local function isEquipped(blockId: string): boolean
	local character = localPlayer.Character
	if not character then return false end
	return character:FindFirstChild(toolNameFor(blockId)) ~= nil
end

local function equipBlock(blockId: string)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local tool = findTool(blockId)
	if not tool then return end
	-- If it's already equipped, unequip. Otherwise swap to it (the built-in
	-- EquipTool unequips any other tool first, which is what we want).
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

---------------------------------------------------------------------------
-- Data source: counts from profile.LuckyBlocks (authoritative) fall back to
-- Backpack-instance counts (for dev-console grants and edge cases where the
-- PlayerDataUpdate hasn't landed yet).
---------------------------------------------------------------------------

local latestBlocks: { [string]: number } = {}

local function mergedCounts(): { [string]: number }
	local out: { [string]: number } = {}
	for id, count in latestBlocks do
		if count and count > 0 then
			out[id] = count
		end
	end
	-- Merge in any Tool instances that exist but aren't reflected in the
	-- profile snapshot yet (e.g. first-load race before PlayerDataUpdate
	-- arrives, or dev grant). Count instances per id so the badge shows the
	-- correct xN even before the profile snapshot lands — otherwise the badge
	-- stays hidden until the first profile update.
	local instanceCounts: { [string]: number } = {}
	local function bump(name: string?)
		if not name then return end
		local id = name:match("^LuckyBlock_(.+)$")
		if not id then return end
		instanceCounts[id] = (instanceCounts[id] or 0) + 1
	end
	local character = localPlayer.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then bump(child.Name) end
		end
	end
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then bump(child.Name) end
		end
	end
	for id, c in instanceCounts do
		out[id] = math.max(out[id] or 0, c)
	end
	return out
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function disableCoreBackpack()
	-- Roblox re-enables the backpack CoreGui on respawn, so we re-assert.
	local function apply()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)
			if ok then break end
			task.wait(0.25)
		end
	end
	task.spawn(apply)
	localPlayer.CharacterAdded:Connect(apply)
end

type SlotRefs = {
	frame: Frame,
	button: TextButton,
	icon: ImageLabel,
	countLabel: TextLabel,
	stroke: UIStroke,
	gradient: UIGradient,
	blockId: string?,
}

local function buildSlot(parent: Instance, layoutOrder: number, _unused: number?): SlotRefs
	local frame = Instance.new("Frame")
	frame.Name = "Slot" .. layoutOrder
	-- Pixel-offset square. The actual pixel size is set by relayout() once
	-- viewport dimensions are known. Scale-only sizing + UIAspectRatioConstraint
	-- inside a scale-sized parent produced 0-size boxes in Roblox's engine, so
	-- we resolve pixels explicitly and respond to viewport resize events.
	frame.Size = UDim2.fromOffset(64, 64)
	frame.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
	frame.BorderSizePixel = 0
	frame.LayoutOrder = layoutOrder
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(80, 85, 95)
	-- Border mode draws the stroke inside the frame bounds so it isn't clipped
	-- by tight UIListLayout padding or screen edges on mobile.
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	-- Disable descendant clipping so the stroke isn't trimmed by the frame's
	-- own rounded corners on rare devices where Border mode still clips.
	frame.ClipsDescendants = false

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(55, 58, 66), Color3.fromRGB(28, 30, 36))
	gradient.Parent = frame

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.85, 0.85)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = frame

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.AnchorPoint = Vector2.new(1, 0)
	countLabel.Position = UDim2.fromScale(0.98, 0.03)
	countLabel.Size = UDim2.fromScale(0.45, 0.3)
	countLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	countLabel.BackgroundTransparency = 0.25
	countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	countLabel.Font = Enum.Font.FredokaOne
	countLabel.TextScaled = true
	countLabel.Text = ""
	countLabel.Visible = false
	countLabel.ZIndex = 3
	countLabel.Parent = frame
	local ccorner = Instance.new("UICorner"); ccorner.CornerRadius = UDim.new(0.3, 0); ccorner.Parent = countLabel
	local cPad = Instance.new("UIPadding")
	cPad.PaddingLeft = UDim.new(0.1, 0); cPad.PaddingRight = UDim.new(0.1, 0)
	cPad.Parent = countLabel

	local button = Instance.new("TextButton")
	button.Name = "Tap"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.ZIndex = 5
	button.Parent = frame

	return {
		frame = frame,
		button = button,
		icon = icon,
		countLabel = countLabel,
		stroke = stroke,
		gradient = gradient,
	}
end

local function styleSlot(slot: SlotRefs, blockId: string?, count: number, equipped: boolean)
	slot.blockId = blockId
	if not blockId then
		slot.icon.Image = ""
		slot.countLabel.Visible = false
		slot.stroke.Color = Color3.fromRGB(80, 85, 95)
		slot.stroke.Thickness = 2
		slot.gradient.Color = ColorSequence.new(Color3.fromRGB(55, 58, 66), Color3.fromRGB(28, 30, 36))
		slot.frame.BackgroundTransparency = 0.25
		return
	end
	slot.frame.BackgroundTransparency = 0
	local entry = LuckyBlockCatalog.Get(blockId)
	local imageId = entry and entry.imageId
	slot.icon.Image = if imageId then "rbxassetid://" .. tostring(imageId) else ""

	local style = rarityFor(blockId)
	slot.gradient.Color = ColorSequence.new(style.top, style.bottom)
	slot.stroke.Color = if equipped then Color3.fromRGB(255, 215, 0) else style.stroke
	slot.stroke.Thickness = if equipped then 4 else 2

	if count > 1 then
		slot.countLabel.Text = `x{count}`
		slot.countLabel.Visible = true
	else
		slot.countLabel.Visible = false
	end
end

local function popSlot(slot: SlotRefs)
	local orig = slot.frame.Size
	slot.frame.Size = UDim2.new(
		orig.X.Scale * 0.9, orig.X.Offset * 0.9,
		orig.Y.Scale * 0.9, orig.Y.Offset * 0.9
	)
	TweenService:Create(slot.frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = orig,
	}):Play()
end

-- Restart tears down the existing hotbar + expanded panel and lets a future
-- Start() build them fresh. Useful for the DevMenu's "Force Mobile" toggle so
-- the layout switches without having to Stop+Play.
function LuckyBlockHotbar.Restart()
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then
		local existing = pg:FindFirstChild("LuckyBlockHotbar")
		if existing then existing:Destroy() end
		local existingPanel = pg:FindFirstChild("LuckyBlockExpandedPanel")
		if existingPanel then existingPanel:Destroy() end
	end
	started = false
	LuckyBlockHotbar.Start()
end

function LuckyBlockHotbar.Start()
	if started then return end
	started = true

	disableCoreBackpack()

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local mobile = isTouchOnly()
	local maxSlots = if mobile then MAX_SLOTS_MOBILE else MAX_SLOTS_DESKTOP
	local slotHeightScale = if mobile then SLOT_HEIGHT_SCALE_MOBILE else SLOT_HEIGHT_SCALE_DESKTOP

	-- Render below other lobby HUDs (shop, inventory, ads, etc.) so the hotbar
	-- and its expanded panel don't cover them when overlap happens. Previous
	-- value (40) was higher than the default-0 screen UIs, so the hotbar
	-- punched through things like the shop/inventory buttons.
	local gui = Instance.new("ScreenGui")
	gui.Name = "LuckyBlockHotbar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -5
	gui.Parent = playerGui

	-- Hotbar container: bottom-center, height = slotHeightScale + a bit of
	-- breathing room, width = auto-sized by the UIListLayout inside. Using
	-- AutomaticSize lets the hotbar shrink to fit exactly the visible slots.
	-- The hotbar container takes its height directly from screen scale. Slots
	-- inside use scale=1 against this container so their pixel height equals
	-- the container's. Previously slots used `slotHeightScale` inside a
	-- container that was already `slotHeightScale` tall — the scales
	-- multiplied and everything rendered as a tiny speck.
	-- Full-width container at bottom. UIListLayout centers the visible slots
	-- inside it. Previous version used AutomaticSize.X, but scale-sized
	-- children (slots use UDim2.fromScale + aspect ratio) don't contribute to
	-- AutomaticSize, so the container collapsed to 0 width and everything
	-- rendered as a speck.
	local hotbar = Instance.new("Frame")
	hotbar.Name = "Hotbar"
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 0.95, 0)
	-- Extra vertical room so the stroke at the top/bottom edge of each slot
	-- isn't clipped by the hotbar frame's bounds. +8px on each side covers the
	-- 2px stroke plus the pop-scale tween wiggle room.
	hotbar.Size = UDim2.new(1, 0, slotHeightScale, 16)
	hotbar.BackgroundTransparency = 1
	hotbar.ClipsDescendants = false
	hotbar.Parent = gui

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = hotbar

	-- Pre-build max slots once. We hide unused slot frames so the UIListLayout
	-- collapses to fit only the owned blocks — no reserved empty space.
	-- Slots fill the hotbar height (scale=1) and width follows from aspect.
	local slots: { SlotRefs } = {}
	for i = 1, maxSlots do
		slots[i] = buildSlot(hotbar, i)
		slots[i].frame.Visible = false
	end

	-- Recompute pixel sizes whenever the viewport changes. We drive off the
	-- Camera's ViewportSize because ScreenGui.AbsoluteSize isn't a signal we
	-- can cheaply subscribe to. Slots are square boxes sized from screen height.
	local function currentSlotPixels(): number
		local camera = workspace.CurrentCamera
		local viewportY = if camera then camera.ViewportSize.Y else 720
		return math.max(48, math.floor(viewportY * slotHeightScale))
	end

	-- Expand button (opens a full scrollable grid of ALL owned blocks). Same
	-- height as slots (fills hotbar) with a narrower aspect.
	local expand = Instance.new("ImageButton")
	expand.Name = "Expand"
	expand.LayoutOrder = maxSlots + 1
	expand.Size = UDim2.fromScale(0, 1)
	expand.BackgroundColor3 = Color3.fromRGB(60, 63, 72)
	expand.BorderSizePixel = 0
	expand.AutoButtonColor = true
	-- Background only on the button itself; the arrow lives as a child
	-- ImageLabel so we can rotate JUST the arrow without flipping the
	-- rounded-corner background or messing with the button's hit region.
	expand.Image = ""
	expand.Visible = false
	expand.Parent = hotbar
	local ec = Instance.new("UICorner"); ec.CornerRadius = UDim.new(0.2, 0); ec.Parent = expand

	local expandArrow = Instance.new("ImageLabel")
	expandArrow.Name = "Arrow"
	expandArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	expandArrow.Position = UDim2.fromScale(0.5, 0.5)
	expandArrow.Size = UDim2.fromScale(0.64, 0.64)
	expandArrow.BackgroundTransparency = 1
	expandArrow.Image = "rbxassetid://84591418883059"
	expandArrow.ScaleType = Enum.ScaleType.Fit
	expandArrow.ImageColor3 = Color3.fromRGB(255, 255, 255)
	expandArrow.Parent = expand

	-- Expanded grid panel (hidden by default). Scale-sized against the screen
	-- so it feels consistent across devices.
	-- Panel sits in its own higher-DisplayOrder ScreenGui so it always renders
	-- above the hotbar's count badges (which would otherwise poke through the
	-- panel where it overlaps the hotbar area).
	local panelGui = Instance.new("ScreenGui")
	panelGui.Name = "LuckyBlockExpandedPanel"
	panelGui.ResetOnSpawn = false
	panelGui.IgnoreGuiInset = true
	-- Panel still sits above the hotbar (-5) but below the lobby HUDs (default
	-- 0). Using -4 keeps the expand arrow/panel layering correct without
	-- covering the shop/inventory/cash widgets.
	panelGui.DisplayOrder = -4
	panelGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "ExpandedPanel"
	-- Panel bottom sits comfortably above the hotbar top. Hotbar top is at
	-- roughly `0.95 - slotHeightScale` (hotbar.Position.Y=0.95,
	-- AnchorPoint.Y=1, height=slotHeightScale). Use a larger gap (~5% of
	-- screen) so the panel and the hotbar's count badges don't overlap when
	-- the row beneath the panel pokes up.
	local panelOpenY = 0.90 - slotHeightScale
	-- Closed state hides the panel offscreen below for the slide-in tween.
	local panelClosedY = 1.15
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, panelClosedY, 0)
	-- Cap the panel width at 50% of the screen so it stops bleeding edge-to-edge
	-- on mobile (which was clipping the panel stroke against the screen border
	-- and crowding the 3D scene).
	panel.Size = UDim2.fromScale(0.5, 0.4)
	panel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	-- ClipsDescendants is intentionally OFF so the panel's own stroke (and any
	-- slot strokes that hit the panel edge) render fully instead of being
	-- shaved by the rounded corner/clip rect.
	panel.ClipsDescendants = false
	panel.Visible = false
	panel.Parent = panelGui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0.03, 0); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(80, 85, 95); ps.Thickness = 2
	-- Contextual: on the expanded panel itself we want the stroke OUTSIDE the
	-- fill so the corner radius doesn't eat the top edge stroke under
	-- ApplyStrokeMode.Border (which was contributing to the "cut off" look).
	ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ps.Parent = panel

	-- Inner padding so cells don't butt up against the panel's rounded corners
	-- or its stroke — the expanded grid was clipping the right-side slot and
	-- looked like it was bleeding through the border.
	local panelPad = Instance.new("UIPadding")
	panelPad.PaddingLeft = UDim.new(0, 12)
	panelPad.PaddingRight = UDim.new(0, 12)
	panelPad.PaddingTop = UDim.new(0, 8)
	panelPad.PaddingBottom = UDim.new(0, 12)
	panelPad.Parent = panel

	local panelTitle = Instance.new("TextLabel")
	panelTitle.Size = UDim2.new(1, 0, 0.12, 0)
	panelTitle.Position = UDim2.fromScale(0.04, 0.02)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Text = "Lucky Blocks"
	panelTitle.TextColor3 = Color3.fromRGB(255, 220, 120)
	panelTitle.Font = Enum.Font.FredokaOne
	panelTitle.TextScaled = true
	panelTitle.TextXAlignment = Enum.TextXAlignment.Left
	panelTitle.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.AnchorPoint = Vector2.new(0.5, 1)
	scroll.Position = UDim2.fromScale(0.5, 0.97)
	-- Slightly tighter than full-width so the centered grid has equal margin
	-- on both sides relative to the panel stroke.
	scroll.Size = UDim2.fromScale(0.9, 0.8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	-- Grid cells sized as a scale of the panel so they stay proportional.
	-- UIGridLayout needs exact CellSize. We recompute it in render() from the
	-- scroll's current AbsoluteSize so cells stay square and responsive.
	-- Inset the scroll content a few px so the top row's stroke isn't shaved
	-- by the ScrollingFrame's default ClipsDescendants. Without this padding
	-- the stroke pops back in only after the user scrolls down (because the
	-- items move past the clip edge).
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 6)
	scrollPad.PaddingBottom = UDim.new(0, 6)
	scrollPad.PaddingLeft = UDim.new(0, 4)
	scrollPad.PaddingRight = UDim.new(0, 4)
	scrollPad.Parent = scroll

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(60, 60)
	grid.CellPadding = UDim2.fromScale(0.02, 0.03)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	-- Cap expanded-panel cells to the hotbar slot's physical size so they stay
	-- a reasonable tap target across screen widths. We pack as many columns as
	-- fit in the scroll's width — preventing the "3 huge cells" look on wide
	-- panels where naive (width / N) math ballooned each cell to 300+ px.
	local function resizeGridCells()
		-- Available width = scroll width minus the scrollbar and a generous
		-- safety margin. AbsoluteSize doesn't subtract the scrollbar, and
		-- UIGridLayout doesn't know about it either — without enough headroom
		-- the rightmost cell wraps or clips against the panel stroke. Bumped
		-- the safety margin so cells fit cleanly even with rounded-corner
		-- antialiasing on the panel.
		local w = scroll.AbsoluteSize.X - scroll.ScrollBarThickness - 12
		if w <= 0 then return end
		local padding = 8
		local maxCell = currentSlotPixels()
		local cellsPerRow = math.max(1, math.floor((w + padding) / (maxCell + padding)))
		local cellW = math.floor((w - padding * (cellsPerRow - 1)) / cellsPerRow)
		cellW = math.max(32, math.min(maxCell, cellW))
		grid.CellSize = UDim2.fromOffset(cellW, cellW)
		grid.CellPadding = UDim2.fromOffset(padding, padding)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeGridCells)

	-- Slide-in/out tween state. `panelOpen` is the logical toggle (source of
	-- truth); `panel.Visible` flips true immediately on open so the tween can
	-- animate, and flips false after the close tween completes so the panel
	-- fully clears the viewport and releases input.
	local panelOpen = false
	local TWEEN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function openPanel()
		if panelOpen then return end
		panelOpen = true
		panel.Visible = true
		panel.Position = UDim2.new(0.5, 0, panelClosedY, 0)
		-- Grid cell size needs the scroll's AbsoluteSize which is only
		-- populated once the panel is actually parented and visible.
		task.defer(resizeGridCells)
		TweenService:Create(panel, TWEEN_INFO, {
			Position = UDim2.new(0.5, 0, panelOpenY, 0),
		}):Play()
		TweenService:Create(expandArrow, TWEEN_INFO, { Rotation = 180 }):Play()
	end

	local function closePanel()
		if not panelOpen then return end
		panelOpen = false
		local tween = TweenService:Create(panel, TWEEN_INFO, {
			Position = UDim2.new(0.5, 0, panelClosedY, 0),
		})
		tween.Completed:Connect(function()
			-- Only hide if we're still closed — another open could have raced in.
			if not panelOpen then panel.Visible = false end
		end)
		tween:Play()
		TweenService:Create(expandArrow, TWEEN_INFO, { Rotation = 0 }):Play()
	end

	expand.Activated:Connect(function()
		if panelOpen then closePanel() else openPanel() end
	end)

	---------------------------------------------------------------------------
	-- Render
	---------------------------------------------------------------------------

	local function sortedIds(counts): { string }
		-- Stable order: by catalog position so the hotbar doesn't jump around
		-- as counts change.
		local ids: { string } = {}
		for _, entry in LuckyBlockCatalog.GetAll() do
			if (counts[entry.id] or 0) > 0 then
				table.insert(ids, entry.id)
			end
		end
		return ids
	end

	local function clearScroll()
		for _, child in scroll:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextButton") then
				child:Destroy()
			end
		end
	end

	local function render()
		local counts = mergedCounts()
		local ids = sortedIds(counts)

		-- Hotbar slots: show exactly as many as the player owns, up to maxSlots.
		-- Unused slots are hidden entirely so UIListLayout collapses them.
		for i = 1, maxSlots do
			local id = ids[i]
			local slot = slots[i]
			if id then
				styleSlot(slot, id, counts[id], isEquipped(id))
				slot.frame.Visible = true
			else
				slot.frame.Visible = false
			end
		end

		-- Expand only appears if there's overflow beyond maxSlots.
		local overflow = #ids > maxSlots
		expand.Visible = overflow
		if not overflow then
			closePanel()
		end

		-- Hide the whole hotbar if player has no blocks at all.
		hotbar.Visible = #ids > 0

		-- Expanded panel content (shows ALL owned blocks). Cells are
		-- offset-sized via the grid layout — we pass heightScale=1 but the
		-- grid.CellSize wins, so slots fill whatever pixel box the grid gives.
		clearScroll()
		resizeGridCells()
		for i, id in ids do
			local s = buildSlot(scroll, i)
			-- UIGridLayout drives the cell size; the slot's own Size is ignored.
			s.frame.Size = UDim2.fromScale(1, 1)
			styleSlot(s, id, counts[id], isEquipped(id))
			s.button.Activated:Connect(function()
				popSlot(s)
				equipBlock(id)
				closePanel()
			end)
		end
	end

	-- Slot tap handlers (bound once; they read the current blockId at tap time
	-- from slot.blockId which styleSlot keeps fresh).
	for _, slot in slots do
		slot.button.Activated:Connect(function()
			local id = slot.blockId
			if not id then return end
			popSlot(slot)
			equipBlock(id)
		end)
	end

	---------------------------------------------------------------------------
	-- Data + character watchers
	---------------------------------------------------------------------------

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local updateRemote = remotes:WaitForChild("PlayerDataUpdate") :: RemoteEvent
	updateRemote.OnClientEvent:Connect(function(data)
		if typeof(data) == "table" and typeof(data.LuckyBlocks) == "table" then
			latestBlocks = data.LuckyBlocks
			render()
		end
	end)

	local requestRemote = remotes:FindFirstChild("RequestPlayerData")
	if requestRemote and requestRemote:IsA("RemoteEvent") then
		requestRemote:FireServer()
	end

	-- Rebind on every Backpack/Character change so equipped ring + fallback
	-- instance counts stay accurate.
	local function bindBackpack(backpack: Instance)
		backpack.ChildAdded:Connect(render)
		backpack.ChildRemoved:Connect(render)
	end
	local function bindCharacter(character: Model)
		character.ChildAdded:Connect(function(c)
			if c:IsA("Tool") then render() end
		end)
		character.ChildRemoved:Connect(function(c)
			if c:IsA("Tool") then render() end
		end)
		render()
	end
	localPlayer.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then bindBackpack(c); render() end
	end)
	local bp = localPlayer:FindFirstChildOfClass("Backpack")
	if bp then bindBackpack(bp) end
	localPlayer.CharacterAdded:Connect(bindCharacter)
	if localPlayer.Character then bindCharacter(localPlayer.Character) end

	-- Apply pixel sizes now and whenever the viewport changes. This replaces
	-- the scale+aspect-constraint approach which produced 0-size boxes.
	local function relayout()
		local px = currentSlotPixels()
		for _, s in slots do
			s.frame.Size = UDim2.fromOffset(px, px)
		end
		expand.Size = UDim2.fromOffset(math.floor(px * 0.6), px)
		if panel.Visible then resizeGridCells() end
	end
	relayout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local c = workspace.CurrentCamera
		if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(relayout) end
		relayout()
	end)

	render()

	-- Number keys 1..maxSlots for quick equip on desktop (mirrors
	-- the default hotbar's 1-9 keybinds players expect).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local digit = input.KeyCode.Value - Enum.KeyCode.Zero.Value
		if digit >= 1 and digit <= maxSlots then
			local slot = slots[digit]
			if slot and slot.blockId then
				equipBlock(slot.blockId)
			end
		end
	end)
end

return LuckyBlockHotbar
