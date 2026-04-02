#!/bin/bash
set -e

# Ensure Rokit tools (wally, rojo, etc.) are on PATH
export PATH="$HOME/.rokit/bin:$PATH"

# Verify wally is available
if ! command -v wally &> /dev/null; then
    echo "ERROR: wally not found. Install Rokit (https://github.com/rojo-rbx/rokit) first."
    echo "  PATH searched: $PATH"
    exit 1
fi

echo "Running wally install..."
wally install

TOPBAR="Packages/_Index/1foreverhd_topbarplus@3.4.0/topbarplus/src"
CONTAINER="$TOPBAR/Elements/Container.lua"
OVERFLOW="$TOPBAR/Features/Overflow.lua"

if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: $CONTAINER not found. Check TopBarPlus version in wally.toml."
    exit 1
fi
if [ ! -f "$OVERFLOW" ]; then
    echo "ERROR: $OVERFLOW not found. Check TopBarPlus version in wally.toml."
    exit 1
fi

echo "Patching TopBarPlus v3.4.0 deferred Clone() race condition..."

# --- Patch 1: Elements/Container.lua ---
# Insert FindFirstChild + fallback after "local center = left:Clone()"
sed -i '/local center = left:Clone()/a\\\tlocal centerUIList = center:FindFirstChild("UIListLayout")\n\tif not centerUIList then\n\t\tcenterUIList = UIListLayout:Clone()\n\t\tcenterUIList.Parent = center\n\tend' "$CONTAINER"

# Replace center.UIListLayout. with centerUIList.
sed -i 's/center\.UIListLayout\./centerUIList./g' "$CONTAINER"

# Insert FindFirstChild + fallback after "local right = left:Clone()"
sed -i '/local right = left:Clone()/a\\\tlocal rightUIList = right:FindFirstChild("UIListLayout")\n\tif not rightUIList then\n\t\trightUIList = UIListLayout:Clone()\n\t\trightUIList.Parent = right\n\tend' "$CONTAINER"

# Replace right.UIListLayout. with rightUIList.
sed -i 's/right\.UIListLayout\./rightUIList./g' "$CONTAINER"

# --- Patch 2: Features/Overflow.lua ---
# Replace direct .UIListLayout with FindFirstChild + early return guard
sed -i 's/local holderUIList = holder\.UIListLayout/local holderUIList = holder:FindFirstChild("UIListLayout")\n\tif not holderUIList then\n\t\treturn\n\tend/' "$OVERFLOW"

echo "Setup complete! TopBarPlus patches applied."
echo "You can now run: rojo serve"
