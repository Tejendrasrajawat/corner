#!/usr/bin/env bash
# Runs the CornerKit tests with only the Command Line Tools installed (no Xcode).
# Their Swift Testing install lacks the _Testing_Foundation overlay, so cross-import overlays are turned off.
set -euo pipefail
cd "$(dirname "$0")/.."
fw=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [[ -d "$fw/Testing.framework" ]]; then
  swift test -Xswiftc -F -Xswiftc "$fw" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$fw" -Xlinker -rpath -Xlinker "$fw" "$@"
else
  swift test "$@"
fi
