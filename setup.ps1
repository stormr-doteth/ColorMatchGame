$ErrorActionPreference = "Stop"

# Ensure Rokit tools are on PATH
$env:PATH = "$env:USERPROFILE\.rokit\bin;$env:PATH"

$wally = Get-Command wally -ErrorAction SilentlyContinue
if (-not $wally) {
    Write-Host "ERROR: wally not found. Install Rokit (https://github.com/rojo-rbx/rokit) first." -ForegroundColor Red
    exit 1
}

Write-Host "Running wally install..."
wally install

$topbar = "Packages/_Index/1foreverhd_topbarplus@3.4.0/topbarplus/src"
$containerFile = "$topbar/Elements/Container.lua"
$overflowFile = "$topbar/Features/Overflow.lua"

if (-not (Test-Path $containerFile)) {
    Write-Host "ERROR: $containerFile not found. Check TopBarPlus version in wally.toml." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $overflowFile)) {
    Write-Host "ERROR: $overflowFile not found. Check TopBarPlus version in wally.toml." -ForegroundColor Red
    exit 1
}

Write-Host "Patching TopBarPlus v3.4.0 deferred Clone() race condition..."

# --- Patch 1: Elements/Container.lua ---
$container = Get-Content $containerFile -Raw

# Patch center block: insert FindFirstChild + fallback after "local center = left:Clone()"
$container = $container -replace '(\tlocal center = left:Clone\(\))\r?\n(\tinsetChanged:Connect\(function\(\)\r?\n\t\t)center\.UIListLayout(\.Padding)', "`$1`n`tlocal centerUIList = center:FindFirstChild(""UIListLayout"")`n`tif not centerUIList then`n`t`tcenterUIList = UIListLayout:Clone()`n`t`tcenterUIList.Parent = center`n`tend`n`$2centerUIList`$3"

# Replace remaining center.UIListLayout. references
$container = $container -replace 'center\.UIListLayout\.', 'centerUIList.'

# Patch right block: insert FindFirstChild + fallback after "local right = left:Clone()"
$container = $container -replace '(\tlocal right = left:Clone\(\))\r?\n(\tinsetChanged:Connect\(function\(\)\r?\n\t\t)right\.UIListLayout(\.Padding)', "`$1`n`tlocal rightUIList = right:FindFirstChild(""UIListLayout"")`n`tif not rightUIList then`n`t`trightUIList = UIListLayout:Clone()`n`t`trightUIList.Parent = right`n`tend`n`$2rightUIList`$3"

# Replace remaining right.UIListLayout. references
$container = $container -replace 'right\.UIListLayout\.', 'rightUIList.'

Set-Content $containerFile -Value $container -NoNewline

# --- Patch 2: Features/Overflow.lua ---
$overflow = Get-Content $overflowFile -Raw

$overflow = $overflow -replace 'local holderUIList = holder\.UIListLayout', "local holderUIList = holder:FindFirstChild(""UIListLayout"")`n`tif not holderUIList then`n`t`treturn`n`tend"

Set-Content $overflowFile -Value $overflow -NoNewline

Write-Host "Setup complete! TopBarPlus patches applied." -ForegroundColor Green
Write-Host "You can now run: rojo serve"
