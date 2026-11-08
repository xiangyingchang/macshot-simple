#!/bin/bash
# Build and package macOS previews. Does not publish or install.
set -euo pipefail
cd "$(dirname "$0")/.."
version=0.2.3
if [[ -z "${SIMPLE_SIGNING_IDENTITY:-}" || "$SIMPLE_SIGNING_IDENTITY" == "-" ]]; then
  echo "Refusing to create a release with an ad-hoc signature. Set SIMPLE_SIGNING_IDENTITY to a stable signing identity; ad-hoc builds can invalidate Screen Recording consent after updates or reinstalls." >&2
  exit 2
fi
signing_identity="$SIMPLE_SIGNING_IDENTITY"
identities=$(security find-identity -v -p codesigning)
if [[ "$identities" != *"$signing_identity"* ]]; then
  echo "SIMPLE_SIGNING_IDENTITY is not a valid code-signing identity in the current Keychain." >&2
  exit 2
fi
release_build="${SIMPLE_BUILD_ROOT:-$PWD/build/release-$version}"
SIMPLE_ARCHS='arm64 x86_64' SIMPLE_BUILD_ROOT="$release_build" SIMPLE_SIGNING_IDENTITY="$signing_identity" scripts/build-simple.sh
app="$release_build/Build/Products/Release/MacShot Simple.app"
verify_stable_signature_identity() {
  local bundle="$1" code_details requirement identifier team_identifier authority
  if ! code_details=$(codesign -dv --verbose=4 "$bundle" 2>&1); then
    echo "Unable to inspect the code signature for $bundle." >&2
    return 1
  fi
  local requirement_details
  if ! requirement_details=$(codesign -dr - "$bundle" 2>&1); then
    echo "Unable to read the designated code requirement for $bundle." >&2
    return 1
  fi
  requirement="${requirement_details%%$'\n'*}"
  if [[ "$requirement" == *cdhash* ]]; then
    echo "Refusing ad-hoc/CDHash-pinned signature for a release package: $bundle" >&2
    return 1
  fi
  identifier=$(printf '%s\n' "$code_details" | awk -F= '$1 == "Identifier" { print $2; exit }')
  team_identifier=$(printf '%s\n' "$code_details" | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')
  authority=$(printf '%s\n' "$code_details" | awk -F= '$1 == "Authority" { print $2; exit }')
  if [[ "$identifier" != "local.macshot.simple" || -z "$team_identifier" || "$team_identifier" == "not set" || -z "$authority" ]]; then
    echo "Release signing must use an Apple-issued identity with a stable TeamIdentifier." >&2
    return 1
  fi
  printf '%s|%s|%s' "$identifier" "$team_identifier" "$authority"
}
release_identity=$(verify_stable_signature_identity "$app")
output="$PWD/dist/release-$version"
staging=$(mktemp -d "${TMPDIR:-/tmp}/macshot-release.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$output"
for arch in arm64 x86_64; do
  case "$arch" in
    arm64) chip=AppleSilicon ;;
    x86_64) chip=Intel ;;
  esac
  stage="$staging/$chip"
  mkdir -p "$stage"
  ditto "$app" "$stage/MacShot Simple.app"
  binary="$stage/MacShot Simple.app/Contents/MacOS/MacShot Simple"
  lipo "$binary" -thin "$arch" -output "$staging/thin-$arch"
  cat "$staging/thin-$arch" > "$binary"
  # Thinning changes the executable, so sign again with the same stable identity
  # used by build-simple.sh. Do not silently replace it with an ad hoc signature.
  codesign --force --deep --sign "$signing_identity" --entitlements macshot/macshot.entitlements "$stage/MacShot Simple.app"
  codesign --verify --deep --strict "$stage/MacShot Simple.app"
  arch_identity=$(verify_stable_signature_identity "$stage/MacShot Simple.app")
  if [[ "$arch_identity" != "$release_identity" ]]; then
    echo "Architecture-specific app signature does not match the stable release identity: $chip" >&2
    exit 1
  fi
  lipo "$binary" -verify_arch "$arch"
  ln -s /Applications "$stage/Applications"
  cp LICENSE NOTICE "$stage/"
  signature_notice_cn='安装包使用配置的稳定签名身份，未经苹果公证；若签名身份改变，首次安装可能需要重新授权屏幕录制。'
  signature_notice_en='This preview uses the configured stable signing identity but is NOT notarized. Changing signing identity may require one fresh Screen Recording grant.'
  cat > "$stage/INSTALL.txt" <<TEXT
MacShot Simple $version — macOS development preview

中文：拖动 MacShot Simple.app 到 Applications。首次打开后，在系统设置允许屏幕录制。
默认快捷键为 Command+Shift+X，可在菜单栏设置中修改。
需要 macOS 12.3 或以上。$signature_notice_cn
同一签名身份更新/重装可保留屏幕录制授权；临时或 ad-hoc 签名可能在每次新构建后要求重新授权。
如果 macOS 阻止打开，请在系统设置 > 隐私与安全性中查看“仍要打开”。
请勿关闭系统安全保护。旧系统和 Apple Silicon 真机运行仍待验证。

English: Drag MacShot Simple.app into Applications. Grant Screen Recording permission
in System Settings. Default shortcut: Command+Shift+X; change it in menu bar settings.
Requires macOS 12.3+. $signature_notice_en
Reinstalling with the same signing identity should preserve Screen Recording consent; ad-hoc builds may require it again after each new build.
If macOS blocks opening, review Open Anyway in System Settings > Privacy & Security.
Do not disable system security. Older macOS
and Apple Silicon device runtime acceptance is pending.

Source / support: https://github.com/xiangyingchang/macshot-simple
GPL-3.0; derived from sw33tLie/macshot v4.3.0. See LICENSE and NOTICE.
TEXT
  dmg="$output/MacShot-Simple-$version-macOS-$chip.dmg"
  # Use a unique temporary destination, then atomically replace a previous package.
  hdiutil create -volname "MacShot Simple $version $chip" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$staging/$chip.dmg"
  hdiutil verify "$staging/$chip.dmg"
  mv "$staging/$chip.dmg" "$dmg"
done
python3 scripts/package-source.py
cp "dist/MacShot-Simple-$version-source.zip" "$output/"
(cd "$output" && shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt)
printf 'Release packages: %s\n' "$output"
