# DailyRewards

Plug-and-play daily login rewards for Roblox. Cycles through N reward days
(default 7), tracks streak, breaks streak after 48h of inactivity, supports an
optional cash multiplier (e.g., for a VIP pass).

The module makes no assumptions about your data layer or remotes — you supply
a profile adapter and two `RemoteEvent`s.

## Install (Wally)

```toml
# wally.toml
[server-dependencies]
DailyRewards = "storm/daily-rewards@0.1.0"
```

Then `wally install`.

## Install (manual)

Copy `src/` into a `ModuleScript` somewhere your server code can require it
(e.g. `ServerScriptService.DailyRewards`).

## Usage

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyRewards = require(ServerScriptService.DailyRewards)

-- Create two RemoteEvents: one for server→client state, one for client→server claims.
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dataRemote = remotes:WaitForChild("DailyRewardData")
local claimRemote = remotes:WaitForChild("ClaimDailyReward")

local rewards = DailyRewards.new({
    profile = {
        isLoaded = function(player) return MyProfileSystem.IsLoaded(player) end,
        getData = function(player)
            -- Return lastRewardTimestamp, streak, totalLogins
            return MyProfileSystem.GetDailyData(player)
        end,
        setData = function(player, lastReward, streak, totalLogins)
            MyProfileSystem.SetDailyData(player, lastReward, streak, totalLogins)
        end,
        addCash = function(player, amount) MyProfileSystem.AddCash(player, amount) end,
        addHints = function(player, amount) MyProfileSystem.AddHints(player, amount) end,
        addMatches = function(player, amount) MyProfileSystem.AddMatches(player, amount) end,
        addLuckyBlock = function(player, id) MyProfileSystem.AddLuckyBlock(player, id) end,
        -- Optional: returns a multiplier for cash rewards only.
        cashMultiplier = function(player)
            return MyPassSystem.HasVIP(player) and 2 or 1
        end,
    },
    dataRemote = dataRemote,
    claimRemote = claimRemote,
    dayRewards = {
        { cash = 75,   hint = 1 },
        { cash = 150,  match = 1 },
        { cash = 250,  luckyBlock = "common_block" },
        { cash = 400,  hint = 1, match = 1 },
        { cash = 600,  luckyBlock = "uncommon_block" },
        { cash = 900,  hint = 2 },
        { cash = 1500, luckyBlock = "rare_block", hint = 1, match = 1 },
    },
    notify = function(player, message)
        remotes:WaitForChild("ShowNotification"):FireClient(player, message)
    end,
})
```

## Reward shape

```lua
type RewardEntry = {
    cash: number?,
    hint: number?,
    match: number?,
    luckyBlock: string?,
}
```

Extra keys are ignored — feel free to pass additional fields through the data
remote and render them client-side however you want.

## Data stored per player

- `lastReward` — `os.time()` of the last successful claim
- `streak` — consecutive claim count (resets to 0 after 48h gap)
- `totalLogins` — lifetime claim count

## Client

The module doesn't ship a UI. Listen to `dataRemote` on the client to render
your own; fire `claimRemote` (no args) when the player clicks Claim. The data
payload shape is:

```lua
{
    canClaim = boolean,
    currentStreak = number,
    nextDay = number,       -- 1..#dayRewards
    reward = RewardEntry,   -- preview of nextDay's reward
    dayRewards = { RewardEntry },
}
```
