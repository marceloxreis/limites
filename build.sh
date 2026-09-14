#!/bin/zsh
# Builds Limites.app, signs it and, with --install, copies it to /Applications.
set -euo pipefail
cd "${0:A:h}"

swift build -c release --arch arm64

[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources/AppIcon.icns

APP=build/Limites.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Limites "$APP/Contents/MacOS/"
cp .build/arm64-apple-macosx/release/limites-signal "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
plutil -lint -s "$APP"/Contents/Resources/*.lproj/*.strings

# A stable signing identity keeps the Automation permission across rebuilds.
# Without one, the app is signed ad hoc and macOS asks again after every build.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --timestamp=none --sign "${IDENTITY:--}" "$APP/Contents/MacOS/limites-signal"
codesign --force --timestamp=none --sign "${IDENTITY:--}" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Limites 2>/dev/null || true
  rm -rf /Applications/Limites.app
  cp -R "$APP" /Applications/
  open /Applications/Limites.app
  echo "Installed to /Applications/Limites.app"
fi
