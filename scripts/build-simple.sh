#!/bin/bash
# Portable screenshot-only build. Never installs or publishes automatically.
set -euo pipefail
cd "$(dirname "$0")/.."
build_root="${SIMPLE_BUILD_ROOT:-$PWD/build}"
signing_identity="${SIMPLE_SIGNING_IDENTITY:--}"
build_args=(-scheme macshot -configuration Release -derivedDataPath "$build_root"
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO DEAD_CODE_STRIPPING=YES SWIFT_OPTIMIZATION_LEVEL=-Osize
  # Resolve exactly Package.resolved; netrc avoids a Keychain credential lookup
  # that can block non-interactive builds while fetching Sparkle's binary.
  -onlyUsePackageVersionsFromResolvedFile -packageAuthorizationProvider netrc)
# Optional universal build: SIMPLE_ARCHS='arm64 x86_64' scripts/build-simple.sh
if [[ -n "${SIMPLE_ARCHS:-}" ]]; then build_args+=("ARCHS=$SIMPLE_ARCHS" ONLY_ACTIVE_ARCH=NO); fi
xcodebuild "${build_args[@]}" build
app_path="$build_root/Build/Products/Release/MacShot Simple.app"
# Remove local/debug symbols before signing; keep runtime/exported symbols.
xcrun strip -S -x "$app_path/Contents/MacOS/MacShot Simple"
scripts/sign-app.sh "$signing_identity" "$app_path"
printf 'Built: %s\n' "$app_path"
