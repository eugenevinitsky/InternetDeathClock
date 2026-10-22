#!/bin/bash
# Builds the Mac app. Usage: ./build.sh [--install]
# Needs your Apple developer account in Xcode → Settings → Accounts (for iCloud sync signing).
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project InternetDeathClock.xcodeproj -scheme InternetDeathClock -configuration Release \
  -derivedDataPath .build -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build
BUILT=.build/Build/Products/Release/InternetDeathClock.app
echo "Built $(pwd)/$BUILT"
if [[ "${1:-}" == "--install" ]]; then
  APP="/Applications/Internet Death Clock.app"
  pkill -x InternetDeathClock && while pgrep -x InternetDeathClock >/dev/null; do sleep 0.2; done || true
  rm -rf "$APP"
  cp -R "$BUILT" "$APP"
  # LaunchServices can take a moment to register the fresh copy (error -600).
  for _ in 1 2 3 4 5; do open "$APP" 2>/dev/null && break; sleep 1; done
  echo "Installed to $APP and launched"
fi
