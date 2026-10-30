#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 APP_OUTPUT_PATH [PLUGIN_SOURCE_PATH]" >&2
  exit 2
fi

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_OUTPUT_PATH="$1"
if [[ "$APP_OUTPUT_PATH" != /* || "$APP_OUTPUT_PATH" != *.app ]]; then
  echo "APP_OUTPUT_PATH must be an absolute path ending in .app" >&2
  exit 2
fi
if [[ -e "$APP_OUTPUT_PATH" || -L "$APP_OUTPUT_PATH" ]]; then
  echo "Output already exists; refusing to overwrite it: $APP_OUTPUT_PATH" >&2
  exit 2
fi

BUILD_TEMP="$(mktemp -d /tmp/side-feather-installer-build.XXXXXX)"
trap 'rm -rf "$BUILD_TEMP"' EXIT
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -whole-module-optimization \
    -target "${ARCH}-apple-macos12.0" -framework AppKit \
    "$SOURCE_DIR/SideFeatherInstaller.swift" -o "$BUILD_TEMP/SideFeatherInstaller-$ARCH"
done
mkdir -p "$APP_OUTPUT_PATH/Contents/MacOS" "$APP_OUTPUT_PATH/Contents/Resources"
xcrun lipo -create "$BUILD_TEMP/SideFeatherInstaller-arm64" \
  "$BUILD_TEMP/SideFeatherInstaller-x86_64" -output "$APP_OUTPUT_PATH/Contents/MacOS/SideFeatherInstaller"
cat > "$APP_OUTPUT_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.mathewharwich.SideFeatherInstaller</string>
<key>CFBundleExecutable</key><string>SideFeatherInstaller</string>
<key>CFBundleName</key><string>Install Side Feather</string>
<key>CFBundleDisplayName</key><string>Install Side Feather</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRequiresAquaSystemAppearance</key><false/>
</dict></plist>
PLIST
if [[ $# -eq 2 ]]; then
  if [[ ! -d "$2" || -L "$2" ]]; then
    echo "PLUGIN_SOURCE_PATH must be a real bundle directory" >&2
    exit 2
  fi
  ditto "$2" "$APP_OUTPUT_PATH/Contents/Resources/Side Feather.plugin"
fi
if [[ -n "${SIDE_FEATHER_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIDE_FEATHER_SIGN_IDENTITY" "$APP_OUTPUT_PATH"
fi
echo "Built universal macOS 12+ installer: $APP_OUTPUT_PATH"
echo "Developer ID signing and notarization are required before public distribution."
