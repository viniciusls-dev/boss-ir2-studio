#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--build-only" ) ]]; then
    echo "Uso: $0 [--build-only]" >&2
    exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
swift build --scratch-path "$project_dir/work/build"
bin_dir="$(swift build --scratch-path "$project_dir/work/build" --show-bin-path)"
app_path="$project_dir/work/IR2Studio.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/IR2Studio" "$app_path/Contents/MacOS/IR2Studio.new"
mv -f "$app_path/Contents/MacOS/IR2Studio.new" "$app_path/Contents/MacOS/IR2Studio"
cp "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
printf 'Aplicativo: %s\n' "$app_path"

if [[ $# -eq 0 ]]; then
    open "$app_path"
fi
