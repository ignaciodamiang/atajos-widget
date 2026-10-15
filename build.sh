#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'Atajos can only be built on macOS.\n' >&2
    exit 1
fi

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$HOME/Applications/Atajos.app"
contents_dir="$app_dir/Contents"
staged_binary="$contents_dir/MacOS/.Atajos-next"

mkdir -p "$contents_dir/MacOS"
if [[ -e "$staged_binary" ]]; then
    printf 'A staged Atajos binary already exists; inspect it before rebuilding.\n' >&2
    exit 1
fi
if [[ -e "$contents_dir/Info.plist" ]]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$contents_dir/Info.plist")"
    if [[ "$bundle_id" != "local.nacho.atajos-widget" ]]; then
        printf 'Refusing to replace an app with another bundle identifier.\n' >&2
        exit 1
    fi
fi

trap 'rm -f "$staged_binary"' EXIT
swiftc "$project_dir/WindowLayout.swift" "$project_dir/Shortcuts.swift" "$project_dir/KeyboardPreview.swift" "$project_dir/main.swift" -o "$staged_binary"
chmod 755 "$staged_binary"
cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
mv "$staged_binary" "$contents_dir/MacOS/Atajos"
codesign --force --sign - -r '=designated => identifier "local.nacho.atajos-widget"' "$app_dir"
python3 "$project_dir/mcp_server.py" --seed
printf 'Built %s\n' "$app_dir"
