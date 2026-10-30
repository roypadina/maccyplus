#!/bin/bash
# Regenerates the MaccyPlus demo from scratch, offscreen: (1) render the REAL popup views to transparent PNG layers with an
# app-hosted XCTest run in a temp COPY of the repo (throwaway bundle id com.royp.MaccyPlusShots: the user's prefs and history are never
# touched, the test never writes to the pasteboard, nothing is clicked or captured), (2) compose the layers with the kit and
# encode. One command: ./render.sh   (SKIP_LAYERS=1 reuses $BUILD/layers; useful while iterating on scene.swift)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="${KIT:-$HERE}"; [ -f "$KIT/DemoKit.swift" ] || KIT="$HERE/../kit"          # repo: kit is vendored next to this file
APP="${APP_SRC:-$HERE/../..}"                                                   # repo: docs/demo -> repo root
GIF="${GIF:-$HERE/../demo.gif}"                                                 # repo: docs/demo.gif
BUILD="${BUILD:-${TMPDIR:-/tmp}/maccyplus-demo}"                                # never inside the repo (derived data, frames)
LAYERS="$BUILD/layers"
limit() { perl -e 'alarm shift; exec @ARGV' "$@"; }                             # macOS has no timeout(1)
mkdir -p "$BUILD"

if [ -z "${SKIP_LAYERS:-}" ]; then
  rm -rf "$BUILD/repo" "$LAYERS"; mkdir -p "$BUILD/repo" "$LAYERS"
  rsync -a --exclude .git --exclude build --exclude .dd --exclude docs "$APP/" "$BUILD/repo/"
  cp "$HERE/DemoLayers.swift" "$BUILD/repo/MaccyTests/ScreenshotRenderTests.swift"   # a test file the target already compiles
  (cd "$BUILD/repo" && TEST_RUNNER_RENDER_DEMO_LAYERS=1 TEST_RUNNER_DEMO_LAYERS_OUT="$LAYERS" \
    limit 1500 xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' -derivedDataPath "$BUILD/dd" \
      -only-testing:MaccyTests/DemoLayerTests CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.royp.MaccyPlusShots \
      > "$BUILD/layers.log" 2>&1) || { tail -40 "$BUILD/layers.log"; exit 1; }
  [ -f "$LAYERS/panel.png" ] || { echo "layer render produced no panel.png (see $BUILD/layers.log)"; exit 1; }
fi

swiftc -swift-version 5 -parse-as-library -O -o "$BUILD/demo" "$KIT/DemoKit.swift" "$HERE/scene.swift"
rm -rf "$BUILD/frames"
MACCYPLUS_LAYERS="$LAYERS" MACCYPLUS_ASSETS="$APP/Maccy/Assets.xcassets/StatusBarMenuImage.imageset" limit 900 "$BUILD/demo" "$BUILD/frames" 30 -AppleLocale en_US -AppleLanguages "(en)"
POSTER=${POSTER:-228}  # panel + action menu open, pointer on "Web search (default)"
"$KIT/encode.sh" "$BUILD/frames" "$GIF" "${MP4:-}" "${WEBP:-}" "${POSTER:-}"
rm -rf "$BUILD/frames"                                                            # only after a successful encode (set -e)
