#!/bin/zsh

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure DEVELOPER_DIR is set to Xcode 27+ with macOS 27 SDK support
if [ -z "$DEVELOPER_DIR" ]; then
    # Prefer Xcode 27 if available
    XCODE_27_APP=$(ls -d /Applications/Xcode-27*.app /Applications/Xcode*27*.app 2>/dev/null | head -n 1)
    if [ -n "$XCODE_27_APP" ] && [ -d "$XCODE_27_APP/Contents/Developer" ]; then
        export DEVELOPER_DIR="$XCODE_27_APP/Contents/Developer"
        echo "Using Xcode 27 developer directory: $DEVELOPER_DIR"
    elif ! xcodebuild -version >/dev/null 2>&1; then
        XCODE_APP=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -n 1)
        if [ -n "$XCODE_APP" ] && [ -d "$XCODE_APP/Contents/Developer" ]; then
            export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
            echo "Using Xcode developer directory: $DEVELOPER_DIR"
        fi
    fi
fi

APP_NAME="MCSC"
BUNDLE_ID="sj010.MCSC"
APP_PATH="/Applications/${APP_NAME}.app"
DERIVED_DATA_PATH="build"
BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_NAME}.app"

echo "========================================="
echo "        MCSC Deploy & Launch Script      "
echo "        Target: macOS 27 (SDK 27.0)      "
echo "========================================="

# 1. Quit the app if running
echo "\n--- 1. Checking running instances ---"
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "Quitting running instance of $APP_NAME..."
    killall "$APP_NAME" || true
    while pgrep -x "$APP_NAME" > /dev/null; do
        sleep 0.5
    done
else
    echo "App is not currently running."
fi

# 2. Build Release configuration
echo "\n--- 2. Building Release configuration (macOS 27) ---"
echo "Building scheme '$APP_NAME' with Release configuration (macOS 27 SDK)..."
xcodebuild -project MCSC.xcodeproj -scheme "$APP_NAME" -configuration Release -derivedDataPath "$DERIVED_DATA_PATH" clean build

if [ ! -d "$BUILT_APP_PATH" ]; then
    echo "Error: Build succeeded but app binary was not found at: $BUILT_APP_PATH"
    exit 1
fi

# 3. Uninstall previous version
echo "\n--- 3. Uninstalling previous version ---"
if [ -d "$APP_PATH" ]; then
    echo "Removing previous installation at $APP_PATH..."
    rm -rf "$APP_PATH"
else
    echo "No previous installation found at $APP_PATH."
fi

# 4. Remove Accessibility permission & clean privacy database while app is closed and uninstalled
echo "\n--- 4. Resetting Accessibility Permissions ---"
echo "Clearing Accessibility permissions for '$BUNDLE_ID'..."
tccutil reset Accessibility "$BUNDLE_ID" || true

# 5. Install into /Applications
echo "\n--- 5. Installing to Applications Folder ---"
echo "Installing to $APP_PATH..."
# Copy the built bundle to the target location
cp -R "$BUILT_APP_PATH" "$APP_PATH"

# 6. Open the newly installed app
echo "\n--- 6. Launching the App ---"
echo "Opening $APP_PATH..."
open "$APP_PATH"

echo "\n========================================="
echo "    Deployment completed successfully!   "
echo "========================================="
