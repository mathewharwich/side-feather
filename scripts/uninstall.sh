#!/bin/bash
set -euo pipefail
installed_bundle="$HOME/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Side Feather.plugin"
backup_parent="$HOME/Library/Application Support/Side Feather/Backups"
if [ ! -e "$installed_bundle" ]; then
    printf 'Side Feather is not installed in the per-user MediaCore folder.\n'
    exit 0
fi
mkdir -p "$backup_parent"
backup_dir="$(mktemp -d "$backup_parent/uninstall-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
mv "$installed_bundle" "$backup_dir/Side Feather.plugin"
printf 'Plug-in moved out of Premiere to: %s\nRestart Premiere to finish. Projects using this effect require it to render.\n' "$backup_dir/Side Feather.plugin"
