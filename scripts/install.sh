#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_bundle="$PWD/dist/Side Feather.plugin"
plugin_parent="$HOME/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore"
installed_bundle="$plugin_parent/Side Feather.plugin"
backup_parent="$HOME/Library/Application Support/Side Feather/Backups"

if [ ! -d "$source_bundle" ]; then
    printf 'Build the plug-in first: bash scripts/build.sh\n' >&2
    exit 1
fi
codesign --verify --strict "$source_bundle"
mkdir -p "$plugin_parent" "$backup_parent"
staging_dir="$(mktemp -d "$backup_parent/staging-XXXXXX")"
trap 'rmdir "$staging_dir" 2>/dev/null || true' EXIT
ditto "$source_bundle" "$staging_dir/Side Feather.plugin"
codesign --verify --strict "$staging_dir/Side Feather.plugin"
if [ -e "$installed_bundle" ]; then
    backup_dir="$(mktemp -d "$backup_parent/install-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
    mv "$installed_bundle" "$backup_dir/Side Feather.plugin"
    printf 'Previous build preserved: %s\n' "$backup_dir/Side Feather.plugin"
fi
# Replace the bundle directory as a whole so Premiere notices a new plug-in timestamp.
mv "$staging_dir/Side Feather.plugin" "$installed_bundle"
touch "$installed_bundle"
codesign --verify --strict "$installed_bundle"
printf 'Installed: %s\nRestart Premiere, then search Effects for Side Feather (Harwich).\n' "$installed_bundle"
