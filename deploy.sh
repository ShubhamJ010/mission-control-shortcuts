#!/bin/zsh

# Exit immediately if a command exits with a non-zero status
set -e

APP_NAME="MCSC"
BUNDLE_ID="sj010.MCSC"
APP_PATH="/Applications/${APP_NAME}.app"
DERIVED_DATA_PATH="build"
BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_NAME}.app"

echo "========================================="
echo "        MCSC Deploy & Launch Script      "
echo "========================================="

# 1. Quit the app if running
echo "\n--- 1. Checking running instances ---"
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "Quitting running instance of $APP_NAME..."
    killall "$APP_NAME" || true
    sleep 1
else
    echo "App is not currently running."
fi

# 2. Build Release configuration
echo "\n--- 2. Building Release configuration ---"
echo "Building scheme '$APP_NAME' with Release configuration..."
xcodebuild -project MCSC.xcodeproj -scheme "$APP_NAME" -configuration Release -derivedDataPath "$DERIVED_DATA_PATH" clean build

if [ ! -d "$BUILT_APP_PATH" ]; then
    echo "Error: Build succeeded but app binary was not found at: $BUILT_APP_PATH"
    exit 1
fi

# Optional: Reset accessibility permissions only if explicitly requested
if [[ "$*" == *"--reset-permissions"* ]]; then
    echo "\n--- Resetting Accessibility Permissions (--reset-permissions flag passed) ---"
    echo "Resetting Accessibility database for bundle ID '$BUNDLE_ID'..."
    tccutil reset Accessibility "$BUNDLE_ID" || echo "Warning: tccutil reset failed or Accessibility permission was not previously granted."
fi

# 3. Install into /Applications
echo "\n--- 3. Installing to Applications Folder ---"
if [ -d "$APP_PATH" ]; then
    echo "Removing previous installation at $APP_PATH..."
    rm -rf "$APP_PATH"
fi

echo "Installing to $APP_PATH..."
# Copy the built bundle to the target location
cp -R "$BUILT_APP_PATH" "$APP_PATH"

# 4. Open the newly installed app
echo "\n--- 4. Launching the App ---"
echo "Opening $APP_PATH..."
open "$APP_PATH"

echo "\n========================================="
echo "    Deployment completed successfully!   "
echo "========================================="
