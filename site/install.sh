#!/bin/sh
# Installs Corner (https://corner-mac.vercel.app) into Applications:
#
#   curl -fsSL https://corner-mac.vercel.app/install.sh | sh
#
# Corner isn't notarized by Apple, so a copy downloaded in a browser has to be allowed once in
# System Settings. A copy fetched with curl isn't marked as downloaded, so macOS opens it without
# that prompt. This script installs exactly the build below: it checks the download against its
# SHA-256 (the same one printed on the website) and stops if they differ.

# Set by scripts/package-release.sh for each release.
version="1.3"
sha256="5d08fc4ae7e2fa5325d6c830251ad9bc1782a16ddcc146be3a13ab29ec045579"

set -eu

# Everything runs from main, so a download cut short can't run half the script.
main() {
  url="https://corner-mac.vercel.app/downloads/Corner-$version.dmg"

  [ "$(uname -s)" = Darwin ] || fail "Corner is a Mac app."
  macos="$(sw_vers -productVersion)"
  [ "${macos%%.*}" -ge 14 ] || fail "Corner needs macOS 14 Sonoma or later; this Mac has $macos."

  work="$(mktemp -d)"
  mount="$work/mount"
  trap 'hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

  say "Downloading Corner $version..."
  curl -fsSL "$url" -o "$work/Corner.dmg" || fail "couldn't download $url."
  actual="$(shasum -a 256 "$work/Corner.dmg" | cut -d ' ' -f 1)"
  [ "$actual" = "$sha256" ] || fail "the download doesn't match its published SHA-256, so nothing was installed."

  hdiutil attach "$work/Corner.dmg" -nobrowse -readonly -noautoopen -mountpoint "$mount" -quiet </dev/null ||
    fail "couldn't open the disk image."

  # Replace an existing copy where it is; otherwise /Applications if you can write there (admin
  # accounts can), else the Applications folder in your home folder.
  if [ -d /Applications/Corner.app ]; then
    dest=/Applications
  elif [ -d "$HOME/Applications/Corner.app" ] || [ ! -w /Applications ]; then
    dest="$HOME/Applications"
  else
    dest=/Applications
  fi
  mkdir -p "$dest"

  # Quit a running copy so it can be replaced. Corner saves as it goes, so nothing is lost.
  if pgrep -x Corner >/dev/null 2>&1; then
    say "Quitting the running Corner..."
    pkill -x Corner || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Corner >/dev/null 2>&1 || break; sleep 0.3; done
  fi

  rm -rf "$dest/Corner.app" || fail "couldn't replace $dest/Corner.app."
  ditto "$mount/Corner.app" "$dest/Corner.app" || fail "couldn't copy Corner into $dest."
  # Nothing curl fetches is quarantined, but an older copy dragged from a browser download may be.
  xattr -dr com.apple.quarantine "$dest/Corner.app" 2>/dev/null || true

  open "$dest/Corner.app"
  say "Corner $version is installed in $dest and running: look at the top-left corner of your screen."
  say "Press Option-Command-T to add your first timer."
}

say() { printf '%s\n' "$*"; }
fail() { printf 'Corner was not installed: %s\n' "$*" >&2; exit 1; }

main "$@"
