#!/bin/bash
# Portable screenshot-only build. Never installs or publishes automatically.
set -euo pipefail
cd "$(dirname "$0")/.."
build_root="${SIMPLE_BUILD_ROOT:-$PWD/build}"
build_args=(-scheme macshot -configuration Release -derivedDataPath "$build_root"
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO)
# Optional universal build: SIMPLE_ARCHS='arm64 x86_64' scripts/build-simple.sh
if [[ -n "${SIMPLE_ARCHS:-}" ]]; then build_args+=("ARCHS=$SIMPLE_ARCHS" ONLY_ACTIVE_ARCH=NO); fi
xcodebuild "${build_args[@]}" build
app_path="$build_root/Build/Products/Release/MacShot Simple.app"
codesign --force --deep --sign "${SIMPLE_SIGNING_IDENTITY:--}" --entitlements macshot/macshot.entitlements "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built: %s\n' "$app_path"
