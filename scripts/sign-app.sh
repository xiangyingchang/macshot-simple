#!/bin/bash
# Sign MacShot Simple and its embedded Sparkle components inside-out.
# Usage: scripts/sign-app.sh <identity|-> <path/to/MacShot Simple.app>
# Sparkle documents that `codesign --deep` breaks its XPC services, so every
# nested bundle is signed explicitly with the same identity before the app.
set -euo pipefail
cd "$(dirname "$0")/.."
identity="$1" app="$2"
entitlements="$PWD/macshot/macshot.entitlements"
sign() { codesign --force --timestamp=none --sign "$identity" "$@"; }
framework="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$framework" ]]; then
  version="$framework/Versions/B"
  for xpc in "$version"/XPCServices/*.xpc; do
    [[ -e "$xpc" ]] || continue
    # Downloader.xpc keeps its own sandbox entitlements from the Sparkle build.
    if [[ "$(basename "$xpc")" == Downloader.xpc ]]; then
      sign -o runtime --preserve-metadata=entitlements "$xpc"
    else
      sign -o runtime "$xpc"
    fi
  done
  sign -o runtime "$version/Autoupdate"
  sign -o runtime "$version/Updater.app"
  sign -o runtime "$framework"
fi
sign --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"
