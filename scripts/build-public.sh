#!/bin/bash
# Build the tested source with sanitized paths into a separate public staging area.
set -euo pipefail
cd "$(dirname "$0")/.."
source_root="${1:-$PWD}"
if [ ! -f "$source_root/Cargo.toml" ]; then
    printf 'Source root must contain Cargo.toml.\n' >&2
    exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=12.0
export CARGO_TARGET_DIR="$PWD/release/build-target"
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=$HOME=."
export CXXFLAGS="${CXXFLAGS:-} -ffile-prefix-map=$HOME=. -fdebug-prefix-map=$HOME=. -fmacro-prefix-map=$HOME=."
export CFLAGS="${CFLAGS:-} -ffile-prefix-map=$HOME=. -fdebug-prefix-map=$HOME=. -fmacro-prefix-map=$HOME=."
sign_identity="${SIDE_FEATHER_SIGN_IDENTITY:-}"
if [ -z "$sign_identity" ]; then
    sign_identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$sign_identity" ]; then
    printf 'A Developer ID Application identity is required for a public build.\n' >&2
    exit 1
fi
rustup target add x86_64-apple-darwin aarch64-apple-darwin
# Switching between source checkouts with identical package names can otherwise
# reuse an older path package's dep-info. Dependencies remain cached, but the
# product/build script are always rebuilt from the explicitly selected checkout.
cargo clean --manifest-path "$source_root/Cargo.toml" --release -p edge_feather
cargo build --manifest-path "$source_root/Cargo.toml" --locked --release --target x86_64-apple-darwin
cargo build --manifest-path "$source_root/Cargo.toml" --locked --release --target aarch64-apple-darwin
bundle="release/public-build/Side Feather.plugin"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
# Stable metadata matches the original host-tested build 3.
python3 - "$bundle/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'Edge Feather',
        'CFBundleIdentifier': 'com.mathewharwich.EdgeFeather',
        'CFBundleName': 'Side Feather',
        'CFBundleDisplayName': 'Side Feather',
        'CFBundlePackageType': 'eFKT', 'CFBundleSignature': 'FXTC',
        'CFBundleVersion': '3', 'CFBundleShortVersionString': '0.1.0',
        'CFBundleInfoDictionaryVersion': '6.0', 'LSMinimumSystemVersion': '12.0',
        'NSHumanReadableCopyright': 'Copyright © 2026 Mathew Harwich',
    }, f)
PY
printf 'eFKTFXTC' > "$bundle/Contents/PkgInfo"
lipo "$CARGO_TARGET_DIR/x86_64-apple-darwin/release/libedge_feather.dylib" "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libedge_feather.dylib" -create -output "$bundle/Contents/MacOS/Edge Feather"
cp "$CARGO_TARGET_DIR/x86_64-apple-darwin/release/edge_feather.rsrc" "$bundle/Contents/Resources/Edge Feather.rsrc"
install_name_tool -id '@rpath/Side Feather.plugin/Contents/MacOS/Edge Feather' "$bundle/Contents/MacOS/Edge Feather"
strip -S "$bundle/Contents/MacOS/Edge Feather"
python3 scripts/package-public.py licenses --source-root "$source_root" --output release/licenses
mkdir -p "$bundle/Contents/Resources/Legal"
cp "$source_root/LICENSE" "$bundle/Contents/Resources/Legal/LICENSE"
for document in THIRD_PARTY_LICENSES.txt RUST_STANDARD_LIBRARY_COPYRIGHT.html DEPENDENCY_LICENSE_INVENTORY.json; do
    cp "release/licenses/$document" "$bundle/Contents/Resources/Legal/$document"
done
for document in PRIVACY.md SUPPORT.md SECURITY.md; do
    if [ -f "$source_root/$document" ]; then
        cp "$source_root/$document" "$bundle/Contents/Resources/Legal/$document"
    fi
done
python3 - "$bundle" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
for p in root.rglob('*'):
    if p.is_file():
        data = p.read_bytes()
        for marker in [b'/Users/', b'/home/', b'/private/var/', b'/private/tmp/', b'/tmp/']:
            if marker in data:
                raise SystemExit(f'Private build path marker found in {p.name}: {marker!r}')
PY
codesign --force --options runtime --timestamp --sign "$sign_identity" "$bundle"
codesign --verify --strict --verbose=2 "$bundle"
touch "$bundle"
python3 - "$source_root" "$bundle" <<'PY'
from pathlib import Path
import hashlib, json, sys
source, bundle = map(Path, sys.argv[1:])
files = ['Cargo.toml', 'Cargo.lock', 'build.rs', 'src/lib.rs', 'src/FeatherCore.h', 'src/FeatherBridge.cpp']
manifest = {
    'product': 'Side Feather', 'version': '0.1.0-beta.1', 'pluginBuild': 3,
    'sourceRepository': 'https://github.com/mathewharwich/side-feather',
    'sourceFiles': {name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files},
    'pluginExecutableSha256': hashlib.sha256((bundle / 'Contents/MacOS/Edge Feather').read_bytes()).hexdigest(),
    'architectures': ['x86_64', 'arm64'],
    'sourcePathRemapped': True, 'debugInfoStripped': True, 'bundledLegalNotices': True,
}
(bundle.parent / 'BUILD_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
file "$bundle/Contents/MacOS/Edge Feather"
shasum -a 256 "$bundle/Contents/MacOS/Edge Feather"
printf 'Public plugin staged in release/public-build/Side Feather.plugin\n'
