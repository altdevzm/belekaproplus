#!/bin/bash

# =============================================================================
# Beleka POS License Generator - Build Script
# Builds the standalone License Generator GUI for Windows & Android APK
# =============================================================================

set -e

ENTRY_POINT="lib/generator_main.dart"
APP_NAME="beleka_license_generator"

echo "======================================================="
echo "   BELEKA POS LICENSE GENERATOR - BUILD SCRIPT"
echo "======================================================="
echo ""

if [ "$1" == "android" ] || [ "$1" == "" ]; then
  echo "[1/2] Building Android APK..."
  flutter build apk \
    -t "$ENTRY_POINT" \
    --release \
    --build-name="1.0.0" \
    --build-number=1 \
    --dart-define=FLUTTER_APP_NAME="Beleka License Manager"

  APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
  if [ -f "$APK_PATH" ]; then
    cp "$APK_PATH" "${APP_NAME}.apk"
    echo ""
    echo "✅ Android APK built successfully!"
    echo "   Output: $(pwd)/${APP_NAME}.apk"
  fi
fi

if [ "$1" == "windows" ] || [ "$1" == "" ]; then
  echo ""
  echo "[2/2] Building Windows EXE..."
  flutter build windows \
    -t "$ENTRY_POINT" \
    --release \
    --build-name="1.0.0" \
    --build-number=1

  WIN_PATH="build/windows/x64/runner/Release"
  if [ -d "$WIN_PATH" ]; then
    echo ""
    echo "✅ Windows build complete!"
    echo "   Output folder: $(pwd)/$WIN_PATH"
    echo "   EXE: $WIN_PATH/beleka_pos.exe"
  fi
fi

echo ""
echo "======================================================="
echo "   BUILD COMPLETE"
echo "======================================================="
