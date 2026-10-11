#!/bin/bash
# Build and package macOS previews. Does not publish or install.
set -euo pipefail
cd "$(dirname "$0")/.."
version=0.2.0
release_build="${SIMPLE_BUILD_ROOT:-$PWD/build/release-$version}"
signing_identity="${SIMPLE_SIGNING_IDENTITY:--}"
SIMPLE_ARCHS='arm64 x86_64' SIMPLE_BUILD_ROOT="$release_build" scripts/build-simple.sh
app="$release_build/Build/Products/Release/MacShot Simple.app"
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
  lipo "$binary" -verify_arch "$arch"
  ln -s /Applications "$stage/Applications"
  cp LICENSE NOTICE "$stage/"
  if [[ "$signing_identity" == "-" ]]; then
    signature_notice_cn='安装包采用临时签名，未经苹果公证；系统可能阻止首次打开。'
    signature_notice_en='This preview is ad hoc signed and NOT notarized. macOS may block first opening.'
  else
    signature_notice_cn='安装包使用配置的开发者证书签名，但未经苹果公证；系统可能阻止首次打开。'
    signature_notice_en='This preview uses the configured developer certificate but is NOT notarized; macOS may block first opening.'
  fi
  cat > "$stage/INSTALL.txt" <<TEXT
MacShot Simple 0.2.0 — macOS development preview

中文：拖动 MacShot Simple.app 到 Applications。首次打开后，在系统设置允许屏幕录制。
默认快捷键为 Command+Shift+X，可在菜单栏设置中修改。
需要 macOS 12.3 或以上。$signature_notice_cn
如果 macOS 阻止打开，请在系统设置 > 隐私与安全性中查看“仍要打开”。
请勿关闭系统安全保护。旧系统和 Apple Silicon 真机运行仍待验证。

English: Drag MacShot Simple.app into Applications. Grant Screen Recording permission
in System Settings. Default shortcut: Command+Shift+X; change it in menu bar settings.
Requires macOS 12.3+. $signature_notice_en If macOS blocks opening, review Open Anyway
in System Settings > Privacy & Security. Do not disable system security. Older macOS
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
