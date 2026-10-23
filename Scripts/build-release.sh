#!/bin/sh
# Universal release build + zip. The build is signed ad hoc ("Sign to Run Locally"). If
# MACCYPLUS_SIGN_IDENTITY names a keychain identity, the bundle is re-signed with it afterwards
# (the maintainer does this so macOS keeps the Accessibility grant across updates).
set -e
cd "$(dirname "$0")/.."
xcodebuild build -project Maccy.xcodeproj -scheme Maccy -configuration Release \
  -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
APP=build/Build/Products/Release/MaccyPlus.app
if [ -n "${MACCYPLUS_SIGN_IDENTITY:-}" ]; then
  ENT=$(mktemp)
  codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null
  # Inside-out: Sparkle's helpers, then the framework, then the app.
  for f in "$APP"/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/*.xpc \
           "$APP"/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app \
           "$APP"/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate \
           "$APP"/Contents/Frameworks/Sparkle.framework; do
    codesign --force --options runtime --preserve-metadata=identifier,entitlements,flags \
      -s "$MACCYPLUS_SIGN_IDENTITY" "$f"
  done
  codesign --force --options runtime --entitlements "$ENT" -s "$MACCYPLUS_SIGN_IDENTITY" "$APP"
  rm -f "$ENT"
  codesign --verify --deep --strict "$APP"
fi
rm -f build/MaccyPlus.zip
ditto -c -k --keepParent "$APP" build/MaccyPlus.zip
echo build/MaccyPlus.zip
