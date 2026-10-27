#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Corner.app and wraps it in a drag-to-Applications DMG
# for the website: site/downloads/Corner-<version>.dmg, plus a stable Corner.dmg copy.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
[[ -f Resources/AppIcon.icns ]] || ./scripts/build-app.sh >/dev/null

for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx14.0"
done

app="build/release/Corner.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create \
  .build/arm64-apple-macosx/release/Corner \
  .build/x86_64-apple-macosx/release/Corner \
  -output "$app/Contents/MacOS/Corner"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Ad-hoc signature. Without an Apple Developer ID and notarization, people opening it from a
# browser download have to approve it once in System Settings (the site explains how), or use
# the Terminal installer, whose curl download macOS doesn't check.
codesign --force --sign - "$app"

stage="$(mktemp -d)"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
mkdir -p site/downloads
dmg="site/downloads/Corner-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "Corner $version" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$stage"
cp "$dmg" site/downloads/Corner.dmg

# The Terminal installer (site/install.sh) installs exactly this build.
sum="$(shasum -a 256 "$dmg" | cut -d ' ' -f 1)"
sed -i '' -e "s/^version=\".*\"/version=\"$version\"/" -e "s/^sha256=\".*\"/sha256=\"$sum\"/" site/install.sh

echo "Built $dmg ($(du -h "$dmg" | cut -f1))"
lipo -archs "$app/Contents/MacOS/Corner"
echo "$sum  $dmg"
