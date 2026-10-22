#!/bin/bash
# Builds the iPhone app and installs it on a connected/paired iPhone.
# Usage: ./phone.sh            (first available iPhone)
#        ./phone.sh <device-id>  (from `xcrun devicectl list devices`)
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp)
xcrun devicectl list devices --json-output "$TMP" >/dev/null 2>&1 || true
DEVICE="${1:-$(python3 -c '
import json, sys
devs = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
ok = [d for d in devs if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
      and d.get("connectionProperties", {}).get("tunnelState") != "unavailable"]
print(ok[0]["identifier"] if ok else "")
' "$TMP")}"
rm -f "$TMP"
if [[ -z "$DEVICE" ]]; then
  echo "No available iPhone. Plug it in (or put it on the same Wi-Fi), unlock it, and try again." >&2
  xcrun devicectl list devices >&2
  exit 1
fi
xcodegen generate --quiet
xcodebuild -project InternetDeathClock.xcodeproj -scheme DeathClockPhone -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath .build -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build
xcrun devicectl device install app --device "$DEVICE" ".build/Build/Products/Release-iphoneos/Death Clock.app"
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing ${CONSOLE:+--console} com.eugenevinitsky.internetdeathclock.phone || true
