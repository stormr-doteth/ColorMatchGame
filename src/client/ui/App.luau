local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local GameController = require(script.Parent.GameController)

local function App()
	return React.createElement(GameController)
end

return App