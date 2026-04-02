local ProfileService = require(script:WaitForChild("data"):WaitForChild("ProfileService"))
local RemoteSetup = require(script:WaitForChild("game"):WaitForChild("RemoteSetup"))
local TableManager = require(script:WaitForChild("game"):WaitForChild("TableManager"))

ProfileService.Start()
print("ProfileService started")

RemoteSetup.Init()
TableManager.Init()
