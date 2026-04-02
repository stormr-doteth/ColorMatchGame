---
name: topbar
description: Create and manage TopBarPlus icons on the Roblox topbar. Use when the user wants to add, modify, or remove topbar icons, buttons, dropdowns, or menus.
argument-hint: "[action] [details]"
---

# TopBar Skill

You are managing topbar icons using TopBarPlus v3.4.0 via the project's `TopBar` singleton module.

## Project Architecture

### Key Files
- `src/client/TopBar/init.luau` — Singleton TopBar service (wrapper around TopBarPlus)
- `src/client/TopBar/Icons.luau` — Icon preset configurations (pure data)
- `src/client/init.client.luau` — Client bootstrap (starts TopBar, creates icons)

### TopBar Singleton API (`require(script:WaitForChild("TopBar"))`)
```luau
TopBar.Start()                          -- Idempotent init, parents ScreenGuis to PlayerGui
TopBar.CreateIcon(name, config)         -- Creates & registers icon, returns raw Icon object
TopBar.GetIcon(name)                    -- Retrieves registered icon by name
TopBar.RemoveIcon(name)                 -- Destroys and unregisters icon
TopBar.CreateSettingsIcon()             -- Convenience: creates "Settings" icon from preset
```

### Icons.luau Preset Format
```luau
Icons.PresetName = {
    Image = "rbxassetid://ASSET_ID",   -- optional icon image
    Caption = "Tooltip Text",           -- optional hover caption
    Order = 1,                          -- optional sort order (lower = more left)
}
```

### Adding a New Icon (Step-by-Step)
1. Add config to `Icons.luau`:
   ```luau
   Icons.Shop = { Image = "rbxassetid://123456", Caption = "Shop", Order = 2 }
   ```
2. Optionally add convenience method to `TopBar/init.luau`:
   ```luau
   function TopBar.CreateShopIcon(): any
       return TopBar.CreateIcon("Shop", Icons.Shop)
   end
   ```
3. Create icon in `init.client.luau` and chain TopBarPlus methods:
   ```luau
   local shopIcon = TopBar.CreateShopIcon()
   shopIcon:bindToggleItem(shopFrame)
   ```

## CRITICAL: React Coexistence Rule

React (`ReactRoblox.createRoot`) MUST render into a dedicated ScreenGui, NOT directly into PlayerGui. If React's root is PlayerGui, it will destroy TopBarPlus ScreenGuis during reconciliation.

```luau
-- CORRECT:
local reactGui = Instance.new("ScreenGui")
reactGui.Name = "ReactApp"
reactGui.ResetOnSpawn = false
reactGui.Parent = playerGui
local root = ReactRoblox.createRoot(reactGui)

-- WRONG: local root = ReactRoblox.createRoot(playerGui)
```

## TopBarPlus v3.4.0 Complete API Reference

### Constructor
```luau
local Icon = require(Packages.TopBarPlus)
local icon = Icon.new()  -- creates empty icon on topbar
```

### Static Methods
| Method | Description |
|--------|-------------|
| `Icon.new()` | Create a new topbar icon |
| `Icon.getIcons()` | Returns dictionary of all active icons |
| `Icon.getIcon(nameOrUID)` | Find icon by name or UID |
| `Icon.setTopbarEnabled(bool)` | Show/hide all TopBarPlus icons |
| `Icon.modifyBaseTheme(modifications)` | Update theme for ALL icons |
| `Icon.setDisplayOrder(int)` | Set ScreenGui DisplayOrder |

### Appearance Methods (all return self for chaining)
| Method | Description |
|--------|-------------|
| `:setImage(imageId, iconState?)` | Set icon image (asset ID or string) |
| `:setLabel(text, iconState?)` | Set text label |
| `:setOrder(int, iconState?)` | Set layout order |
| `:setCaption(text?)` | Set hover tooltip (nil to remove) |
| `:setCornerRadius(udim, iconState?)` | Set corner radius |
| `:setWidth(offsetMin, iconState?)` | Set minimum width (default 44) |
| `:setImageScale(number, iconState?)` | Image size relative to icon (default 0.5) |
| `:setImageRatio(number, iconState?)` | Image aspect ratio (default 1) |
| `:setTextSize(number, iconState?)` | Label text size (default 16) |
| `:setTextFont(font, weight?, style?, state?)` | Set label font |
| `:setTextColor(Color3, iconState?)` | Set label color |
| `:setName(name)` | Set name for `Icon.getIcon(name)` |
| `:setEnabled(bool)` | Show/hide this icon |

### Alignment Methods (all return self)
```luau
icon:align("Left")    -- or :setLeft()
icon:align("Center")  -- or :setMid()
icon:align("Right")   -- or :setRight()
```

### Interaction Methods (all return self unless noted)
| Method | Description |
|--------|-------------|
| `:select(source?, sourceIcon?)` | Programmatically select |
| `:deselect(source?, sourceIcon?)` | Programmatically deselect |
| `:lock()` | Disable user input |
| `:unlock()` | Re-enable user input |
| `:debounce(seconds)` | Lock, wait, unlock (cooldown) |
| `:oneClick(bool?)` | Auto-deselect after select (button mode) |
| `:autoDeselect(bool?)` | Deselect when other icons selected |
| `:notify(clearSignal?, noticeId?)` | Show notification bubble |
| `:clearNotices()` | Remove all notifications |
| `:disableOverlay(bool)` | Disable hover/press shade overlay |

### Toggle & Binding Methods (all return self)
| Method | Description |
|--------|-------------|
| `:bindToggleItem(guiObject)` | Show/hide GUI element on toggle |
| `:unbindToggleItem(guiObject)` | Remove toggle binding |
| `:bindToggleKey(keyCode)` | Bind keyboard shortcut |
| `:unbindToggleKey(keyCode)` | Remove key binding |
| `:bindEvent(eventName, callback)` | Connect to event by name |
| `:unbindEvent(eventName)` | Disconnect event |

### Dropdown & Menu Methods
```luau
-- Vertical dropdown
icon:setDropdown({
    Icon.new():setLabel("Option 1"),
    Icon.new():setLabel("Option 2"),
})

-- Horizontal menu
icon:setMenu({
    Icon.new():setLabel("Tab 1"),
    Icon.new():setLabel("Tab 2"),
})

-- Fixed menu (permanently open, no close button)
icon:setFixedMenu({ Icon.new():setLabel("A"), Icon.new():setLabel("B") })

-- Configure max visible items
icon:modifyTheme({"Dropdown", "MaxIcons", 3})
icon:modifyTheme({"Menu", "MaxIcons", 4})

-- Style child icons in dropdown/menu
icon:modifyChildTheme({"Widget", "MinimumWidth", 158})

-- Join/leave parent icon
childIcon:joinDropdown(parentIcon)
childIcon:joinMenu(parentIcon)
childIcon:leave()
```

### Theme System
```luau
-- Single modification: {instanceName, property, value, iconState?}
icon:modifyTheme({"IconLabel", "TextSize", 20})
icon:modifyTheme({"IconButton", "BackgroundColor3", Color3.fromRGB(255, 0, 0), "Selected"})

-- Multiple modifications
icon:modifyTheme({
    {"Widget", "MinimumWidth", 200},
    {"IconCorners", "CornerRadius", UDim.new(0, 0)},
})

-- Returns modificationUID for later removal
local icon, uid = icon:modifyTheme({"IconLabel", "TextColor3", Color3.new(1,1,0)})
icon:removeModification(uid)

-- Apply theme to ALL icons globally
Icon.modifyBaseTheme({{"IconButton", "BackgroundColor3", Color3.fromRGB(40, 40, 40)}})
```

### Signals / Events
| Signal | Fires With | Description |
|--------|-----------|-------------|
| `icon.selected` | `(source, sourceIcon)` | Icon selected |
| `icon.deselected` | `(source, sourceIcon)` | Icon deselected |
| `icon.toggled` | `(isSelected, source, sourceIcon)` | Any toggle |
| `icon.viewingStarted` | `(true)` | Mouse enter / controller focus |
| `icon.viewingEnded` | `(true)` | Mouse leave / controller unfocus |
| `icon.noticeChanged` | `(totalNotices)` | Notice count changed |
| `icon.alignmentChanged` | `(direction)` | Alignment changed |

Event sources: `"User"`, `"OneClick"`, `"AutoDeselect"`, `"HideParentFeature"`, `"Overflow"`

### Cleanup
```luau
icon:destroy()  -- Removes icon, cleans up all connections
```

### Utility
```luau
icon:call(function(self) ... end)  -- Call function mid-chain
icon:getInstance("IconLabel")       -- Get internal instance by name
icon:addToJanitor(connection)       -- Add to cleanup janitor
```

## Common Patterns

### Settings icon with toggle panel
```luau
local settingsIcon = TopBar.CreateSettingsIcon()
settingsIcon:bindToggleItem(settingsFrame)
```

### Shop button (one-click, opens GUI)
```luau
local shopIcon = TopBar.CreateIcon("Shop", Icons.Shop)
shopIcon:oneClick()
shopIcon.selected:Connect(function()
    shopGui.Visible = true
end)
```

### Dropdown with categories
```luau
local menuIcon = Icon.new()
    :setLabel("Menu")
    :modifyTheme({"Dropdown", "MaxIcons", 4})
    :setDropdown({
        Icon.new():setLabel("Settings"):oneClick(),
        Icon.new():setLabel("Shop"):oneClick(),
        Icon.new():setLabel("Inventory"):oneClick(),
    })
```

### Icon with notification badge
```luau
local mailIcon = TopBar.CreateIcon("Mail", Icons.Mail)
mailIcon:notify()  -- adds +1 badge
mailIcon:notify()  -- adds another
mailIcon:clearNotices()  -- removes all
```

### Keyboard shortcut
```luau
local icon = TopBar.CreateIcon("Settings", Icons.Settings)
icon:bindToggleKey(Enum.KeyCode.P)
icon:bindToggleItem(settingsFrame)
```

## Known Issues & Fixes

### v3.4.0 Clone/UIListLayout race condition
TopBarPlus v3.4.0 has a bug where `Clone()` on ScrollingFrames doesn't immediately include UIListLayout children (deferred cloning). We patched two files in `Packages/_Index/1foreverhd_topbarplus@3.4.0/topbarplus/src/`:

- **`Elements/Container.lua`**: Changed `center.UIListLayout` and `right.UIListLayout` to use `FindFirstChild("UIListLayout")` with fallback `UIListLayout:Clone()`.
- **`Features/Overflow.lua`**: Changed `holder.UIListLayout` to `holder:FindFirstChild("UIListLayout")` with early return guard.

These patches will be overwritten by `wally install`. Reapply if needed.

When following `$ARGUMENTS`, apply the patterns above. Always use the TopBar singleton wrapper for creating icons (not raw `Icon.new()` in client scripts). Add presets to `Icons.luau` and create icons through `TopBar.CreateIcon()`.
