local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Icon = require(Packages.TopBarPlus)

local Icons = require(script.Icons)

local icons: { [string]: any } = {}
local started = false

local TopBar = {}

function TopBar.Start()
	if started then
		return
	end
	started = true

	-- Ensure TopBarPlus ScreenGuis are parented to PlayerGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, screenGui in Icon.container do
		if screenGui.Parent ~= playerGui then
			screenGui.Parent = playerGui
		end
	end
end

function TopBar.CreateIcon(name: string, config: { Image: string?, Caption: string?, Order: number? }): any
	if icons[name] then
		warn(`[TopBar] Icon "{name}" already exists`)
		return icons[name]
	end

	local icon = Icon.new()

	if config.Image then
		icon:setImage(config.Image)
	end
	if config.Caption then
		icon:setCaption(config.Caption)
	end
	if config.Order then
		icon:setOrder(config.Order)
	end

	icons[name] = icon
	return icon
end

function TopBar.GetIcon(name: string): any?
	return icons[name]
end

function TopBar.RemoveIcon(name: string)
	local icon = icons[name]
	if icon then
		icon:destroy()
		icons[name] = nil
	end
end

function TopBar.CreateSettingsIcon(): any
	local icon = TopBar.CreateIcon("Settings", Icons.Settings)
	return icon
end

function TopBar.CreateInviteFriendsIcon(): any
	local icon = TopBar.CreateIcon("InviteFriends", Icons.InviteFriends)
	return icon
end

return TopBar
