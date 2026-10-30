#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=12.0
mode="${1:-native}"
if [ "$mode" = "universal" ]; then
    rustup target add aarch64-apple-darwin x86_64-apple-darwin
    cargo build --locked --release --target x86_64-apple-darwin
    cargo build --locked --release --target aarch64-apple-darwin
    resource_dir=target/x86_64-apple-darwin/release
else
    cargo build --locked --release
    resource_dir=target/release
fi
bundle="dist/Side Feather.plugin"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
if [ "$mode" = "universal" ]; then
    lipo target/x86_64-apple-darwin/release/libedge_feather.dylib target/aarch64-apple-darwin/release/libedge_feather.dylib -create -output "$bundle/Contents/MacOS/Edge Feather"
else
    cp target/release/libedge_feather.dylib "$bundle/Contents/MacOS/Edge Feather"
fi
cp "$resource_dir/edge_feather.rsrc" "$bundle/Contents/Resources/Edge Feather.rsrc"
install_name_tool -id '@rpath/Side Feather.plugin/Contents/MacOS/Edge Feather' "$bundle/Contents/MacOS/Edge Feather"
python3 - "$bundle/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'Edge Feather',
        'CFBundleIdentifier': 'com.mathewharwich.EdgeFeather',
        'CFBundleName': 'Side Feather',
        'CFBundleDisplayName': 'Side Feather',
        'CFBundlePackageType': 'eFKT',
        'CFBundleSignature': 'FXTC',
        'CFBundleVersion': '3',
        'CFBundleShortVersionString': '0.1.0',
        'CFBundleInfoDictionaryVersion': '6.0',
        'LSMinimumSystemVersion': '12.0',
        'NSHumanReadableCopyright': 'Copyright © 2026 Mathew Harwich',
    }, f)
PY
printf 'eFKTFXTC' > "$bundle/Contents/PkgInfo"
codesign --force --sign - "$bundle"
touch "$bundle"
codesign --verify --strict --verbose=2 "$bundle"
file "$bundle/Contents/MacOS/Edge Feather"
printf 'Built: %s/%s\n' "$PWD" "$bundle"
