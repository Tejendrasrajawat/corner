#!/usr/bin/env bash
# Builds build/Corner.app. With --install, also copies it to ~/Applications and (re)launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f Resources/AppIcon.icns ]]; then
  tmp="$(mktemp -d)"
  swift scripts/make-icon.swift "$tmp/icon.png"
  mkdir -p "$tmp/AppIcon.iconset"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$tmp"
fi

swift build -c release
bin="$(swift build -c release --show-bin-path)/Corner"
app="build/Corner.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Corner"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Ad-hoc signature: enough for notifications and launch at login on this Mac.
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Corner 2>/dev/null && sleep 0.5 || true
  rm -rf "$HOME/Applications/Corner.app"
  cp -R "$app" "$HOME/Applications/"
  open "$HOME/Applications/Corner.app"
  echo "Installed ~/Applications/Corner.app and launched it"
fi
