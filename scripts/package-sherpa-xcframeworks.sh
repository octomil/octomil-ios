#!/usr/bin/env bash
#
# package-sherpa-xcframeworks.sh
#
# Repackages the sherpa-onnx and onnxruntime pre-built static libraries
# into proper xcframeworks with .framework bundles and module.modulemaps,
# matching the structure used by llama.xcframework and whisper.xcframework.
#
# Prerequisites:
#   - sherpa-onnx built for iOS via build-ios-no-tts.sh (or equivalent)
#     at $SHERPA_BUILD_DIR (default: research/engines/sherpa-onnx/build-ios)
#
# Outputs:
#   - sherpa_onnx.xcframework.zip   (ready for GitHub release upload)
#   - onnxruntime.xcframework.zip   (ready for GitHub release upload)
#
# Usage:
#   ./scripts/package-sherpa-xcframeworks.sh [--sherpa-build-dir <path>]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default paths
SHERPA_BUILD_DIR="${SHERPA_BUILD_DIR:-$REPO_ROOT/../research/engines/sherpa-onnx/build-ios}"
OUTPUT_DIR="$REPO_ROOT/.build/xcframeworks"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sherpa-build-dir) SHERPA_BUILD_DIR="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "SHERPA_BUILD_DIR: $SHERPA_BUILD_DIR"
echo "OUTPUT_DIR:       $OUTPUT_DIR"

# Validate inputs
for d in "$SHERPA_BUILD_DIR/build/os64/lib" \
         "$SHERPA_BUILD_DIR/build/simulator_arm64/lib" \
         "$SHERPA_BUILD_DIR/build/simulator_x86_64/lib" \
         "$SHERPA_BUILD_DIR/install/include/sherpa-onnx/c-api"; do
  if [ ! -d "$d" ]; then
    echo "ERROR: Required directory not found: $d"
    echo "Run the sherpa-onnx iOS build first (build-ios-no-tts.sh)"
    exit 1
  fi
done

ONNX_XCFW="$SHERPA_BUILD_DIR/ios-onnxruntime/onnxruntime.xcframework"
if [ ! -d "$ONNX_XCFW" ]; then
  echo "ERROR: onnxruntime.xcframework not found at $ONNX_XCFW"
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

WORK="$OUTPUT_DIR/work"
mkdir -p "$WORK"

# ─────────────────────────────────────────────────────────────────────────────
# 1. sherpa_onnx.xcframework
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Building sherpa_onnx.xcframework ==="

SHERPA_LIBS="libkaldi-native-fbank-core.a libkissfft-float.a libsherpa-onnx-c-api.a
             libsherpa-onnx-core.a libsherpa-onnx-fst.a libsherpa-onnx-fstfar.a
             libsherpa-onnx-kaldifst-core.a libkaldi-decoder-core.a libssentencepiece_core.a"

# Create fat simulator library (arm64 + x86_64)
echo "  Creating fat simulator library..."
mkdir -p "$WORK/sherpa-sim-fat"
for lib in $SHERPA_LIBS; do
  lipo -create \
    "$SHERPA_BUILD_DIR/build/simulator_arm64/lib/$lib" \
    "$SHERPA_BUILD_DIR/build/simulator_x86_64/lib/$lib" \
    -output "$WORK/sherpa-sim-fat/$lib"
done

# Merge into single archive per platform
echo "  Merging into single archive (device)..."
libtool -static -o "$WORK/sherpa-device.a" \
  $(for lib in $SHERPA_LIBS; do echo "$SHERPA_BUILD_DIR/build/os64/lib/$lib"; done)

echo "  Merging into single archive (simulator)..."
libtool -static -o "$WORK/sherpa-simulator.a" \
  $(for lib in $SHERPA_LIBS; do echo "$WORK/sherpa-sim-fat/$lib"; done)

# Prepare headers
SHERPA_HEADERS="$WORK/sherpa-headers"
mkdir -p "$SHERPA_HEADERS"
cp "$SHERPA_BUILD_DIR/install/include/sherpa-onnx/c-api/c-api.h" "$SHERPA_HEADERS/"
# cargs.h lives in install/lib (build system quirk)
if [ -f "$SHERPA_BUILD_DIR/install/lib/cargs.h" ]; then
  cp "$SHERPA_BUILD_DIR/install/lib/cargs.h" "$SHERPA_HEADERS/"
fi

# Create module.modulemap
cat > "$SHERPA_HEADERS/module.modulemap" << 'MODULEMAP'
framework module sherpa_onnx {
    header "c-api.h"
    link "c++"
    export *
}
MODULEMAP

# Build framework bundles
build_sherpa_framework() {
  local platform_id="$1"
  local static_lib="$2"
  local fw_dir="$OUTPUT_DIR/sherpa_onnx.xcframework/$platform_id/sherpa_onnx.framework"

  mkdir -p "$fw_dir/Headers"
  mkdir -p "$fw_dir/Modules"

  cp "$static_lib" "$fw_dir/sherpa_onnx"
  cp "$SHERPA_HEADERS"/*.h "$fw_dir/Headers/"
  cp "$SHERPA_HEADERS/module.modulemap" "$fw_dir/Modules/"

  # Framework Info.plist
  cat > "$fw_dir/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>ai.octomil.sherpa-onnx</string>
  <key>CFBundleName</key>
  <string>sherpa_onnx</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST
}

echo "  Building framework bundle (ios-arm64)..."
build_sherpa_framework "ios-arm64" "$WORK/sherpa-device.a"

echo "  Building framework bundle (ios-arm64_x86_64-simulator)..."
build_sherpa_framework "ios-arm64_x86_64-simulator" "$WORK/sherpa-simulator.a"

# XCFramework Info.plist
cat > "$OUTPUT_DIR/sherpa_onnx.xcframework/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AvailableLibraries</key>
  <array>
    <dict>
      <key>BinaryPath</key>
      <string>sherpa_onnx.framework/sherpa_onnx</string>
      <key>LibraryIdentifier</key>
      <string>ios-arm64</string>
      <key>LibraryPath</key>
      <string>sherpa_onnx.framework</string>
      <key>SupportedArchitectures</key>
      <array>
        <string>arm64</string>
      </array>
      <key>SupportedPlatform</key>
      <string>ios</string>
    </dict>
    <dict>
      <key>BinaryPath</key>
      <string>sherpa_onnx.framework/sherpa_onnx</string>
      <key>LibraryIdentifier</key>
      <string>ios-arm64_x86_64-simulator</string>
      <key>LibraryPath</key>
      <string>sherpa_onnx.framework</string>
      <key>SupportedArchitectures</key>
      <array>
        <string>arm64</string>
        <string>x86_64</string>
      </array>
      <key>SupportedPlatform</key>
      <string>ios</string>
      <key>SupportedPlatformVariant</key>
      <string>simulator</string>
    </dict>
  </array>
  <key>CFBundlePackageType</key>
  <string>XFWK</string>
  <key>XCFrameworkFormatVersion</key>
  <string>1.0</string>
</dict>
</plist>
PLIST

echo "  sherpa_onnx.xcframework created."

# ─────────────────────────────────────────────────────────────────────────────
# 2. onnxruntime.xcframework
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Building onnxruntime.xcframework ==="

# Prepare onnxruntime headers
ONNX_HEADERS="$WORK/onnx-headers"
mkdir -p "$ONNX_HEADERS"
if [ -d "$ONNX_XCFW/Headers" ]; then
  cp -R "$ONNX_XCFW/Headers/"* "$ONNX_HEADERS/" 2>/dev/null || true
fi

# Create module.modulemap for onnxruntime
cat > "$ONNX_HEADERS/module.modulemap" << 'MODULEMAP'
framework module onnxruntime {
    export *
}
MODULEMAP

build_onnx_framework() {
  local platform_id="$1"
  local src_dir="$ONNX_XCFW/$platform_id"
  local fw_dir="$OUTPUT_DIR/onnxruntime.xcframework/$platform_id/onnxruntime.framework"

  mkdir -p "$fw_dir/Headers"
  mkdir -p "$fw_dir/Modules"

  # Find the static lib (could be onnxruntime.a or libonnxruntime.a)
  if [ -f "$src_dir/onnxruntime.a" ]; then
    cp "$src_dir/onnxruntime.a" "$fw_dir/onnxruntime"
  elif [ -f "$src_dir/libonnxruntime.a" ]; then
    cp "$src_dir/libonnxruntime.a" "$fw_dir/onnxruntime"
  else
    echo "  WARNING: No onnxruntime static lib found in $src_dir"
    return 1
  fi

  cp "$ONNX_HEADERS"/*.h "$fw_dir/Headers/" 2>/dev/null || true
  cp "$ONNX_HEADERS/module.modulemap" "$fw_dir/Modules/"

  cat > "$fw_dir/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>ai.octomil.onnxruntime</string>
  <key>CFBundleName</key>
  <string>onnxruntime</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST
}

# Build for each available platform
ONNX_PLIST_ENTRIES=""

for platform_dir in "$ONNX_XCFW"/ios-* "$ONNX_XCFW"/macos-*; do
  [ -d "$platform_dir" ] || continue
  platform_id=$(basename "$platform_dir")
  echo "  Building framework bundle ($platform_id)..."
  build_onnx_framework "$platform_id" || continue

  # Determine plist metadata
  supported_platform="ios"
  variant=""
  archs=""

  case "$platform_id" in
    ios-arm64)
      supported_platform="ios"
      archs="<string>arm64</string>"
      ;;
    ios-arm64_x86_64-simulator)
      supported_platform="ios"
      variant="simulator"
      archs="<string>arm64</string><string>x86_64</string>"
      ;;
    macos-arm64_x86_64)
      supported_platform="macos"
      archs="<string>arm64</string><string>x86_64</string>"
      ;;
  esac

  variant_xml=""
  if [ -n "$variant" ]; then
    variant_xml="<key>SupportedPlatformVariant</key><string>$variant</string>"
  fi

  ONNX_PLIST_ENTRIES="$ONNX_PLIST_ENTRIES
    <dict>
      <key>BinaryPath</key>
      <string>onnxruntime.framework/onnxruntime</string>
      <key>LibraryIdentifier</key>
      <string>$platform_id</string>
      <key>LibraryPath</key>
      <string>onnxruntime.framework</string>
      <key>SupportedArchitectures</key>
      <array>$archs</array>
      <key>SupportedPlatform</key>
      <string>$supported_platform</string>
      $variant_xml
    </dict>"
done

cat > "$OUTPUT_DIR/onnxruntime.xcframework/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AvailableLibraries</key>
  <array>$ONNX_PLIST_ENTRIES
  </array>
  <key>CFBundlePackageType</key>
  <string>XFWK</string>
  <key>XCFrameworkFormatVersion</key>
  <string>1.0</string>
</dict>
</plist>
PLIST

echo "  onnxruntime.xcframework created."

# ─────────────────────────────────────────────────────────────────────────────
# 3. Create zip archives
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Creating zip archives ==="

cd "$OUTPUT_DIR"

zip -r -y sherpa_onnx.xcframework.zip sherpa_onnx.xcframework/
echo "  sherpa_onnx.xcframework.zip ($(du -sh sherpa_onnx.xcframework.zip | cut -f1))"

zip -r -y onnxruntime.xcframework.zip onnxruntime.xcframework/
echo "  onnxruntime.xcframework.zip ($(du -sh onnxruntime.xcframework.zip | cut -f1))"

# Compute checksums for Package.swift
echo ""
echo "=== Checksums for Package.swift ==="
SHERPA_CHECKSUM=$(swift package compute-checksum sherpa_onnx.xcframework.zip)
ONNX_CHECKSUM=$(swift package compute-checksum onnxruntime.xcframework.zip)
echo "  sherpa_onnx:  $SHERPA_CHECKSUM"
echo "  onnxruntime:  $ONNX_CHECKSUM"

echo ""
echo "Done. Upload the zips to a GitHub release, then update Package.swift checksums."
echo ""
echo "  sherpa_onnx checksum:  $SHERPA_CHECKSUM"
echo "  onnxruntime checksum:  $ONNX_CHECKSUM"

# Clean up work dir
rm -rf "$WORK"
