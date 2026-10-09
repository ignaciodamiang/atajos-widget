#!/bin/zsh
set -euo pipefail
task_dir="${0:A:h}"
app_dir="/Users/nachogonzalez/Applications/Atajos.app"
task_build_dir="$(mktemp -d /tmp/atajos-build.XXXXXX)"
trap 'rm -rf "$task_build_dir"' EXIT
swiftc "$task_dir/Shortcuts.swift" "$task_dir/KeyboardPreview.swift" "$task_dir/main.swift" -o "$task_build_dir/Atajos"
install -m 755 "$task_build_dir/Atajos" "$app_dir/Contents/MacOS/.Atajos-next"
mv -f "$app_dir/Contents/MacOS/.Atajos-next" "$app_dir/Contents/MacOS/Atajos"
codesign --force --sign - -r '=designated => identifier "local.nacho.atajos-widget"' "$app_dir"
