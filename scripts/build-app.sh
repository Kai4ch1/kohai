#!/usr/bin/env bash
# Builds build/Kohai.app (menu bar app + kohai-hook) from the Swift package.
# Uses only swift and codesign (ad-hoc signature, no notarization).
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product Kohai
swift build -c release --product kohai-hook
BIN="$(swift build -c release --show-bin-path)"

APP="build/Kohai.app"
rm -rf "$APP" # generated output only
mkdir -p "$APP/Contents/MacOS"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/Kohai" "$BIN/kohai-hook" "$APP/Contents/MacOS/"

codesign --force --sign - "$APP/Contents/MacOS/kohai-hook"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Hook binary: $(pwd)/$APP/Contents/MacOS/kohai-hook"
