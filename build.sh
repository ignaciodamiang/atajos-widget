#!/bin/zsh
set -euo pipefail
task_dir="${0:A:h}"
app_dir="/Users/nachogonzalez/Applications/Atajos.app"
staged_binary="$app_dir/Contents/MacOS/.Atajos-next"
if [[ -e "$staged_binary" ]]; then
    print -u2 "A staged Atajos binary already exists; finish or inspect that build first."
    exit 1
fi
trap 'rm -f "$staged_binary"' EXIT
swiftc "$task_dir/WindowLayout.swift" "$task_dir/Shortcuts.swift" "$task_dir/KeyboardPreview.swift" "$task_dir/main.swift" -o "$staged_binary"
chmod 755 "$staged_binary"
mv -f "$staged_binary" "$app_dir/Contents/MacOS/Atajos"
codesign --force --sign - -r '=designated => identifier "local.nacho.atajos-widget"' "$app_dir"
