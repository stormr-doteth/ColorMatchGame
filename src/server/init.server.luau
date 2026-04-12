local ProfileService = require(script:WaitForChild("data"):WaitForChild("ProfileService"))
local RemoteSetup = require(script:WaitForChild("game"):WaitForChild("RemoteSetup"))
local ChairShop = require(script:WaitForChild("game"):WaitForChild("ChairShop"))
local TableManager = require(script:WaitForChild("game"):WaitForChild("TableManager"))

ProfileService.Start()
print("ProfileService started")

RemoteSetup.Init()
ChairShop.Init()
TableManager.Init()
