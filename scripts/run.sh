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
ditto "$bin_dir/IR2Studio_IR2Studio.bundle" "$app_path/Contents/Resources/IR2Studio_IR2Studio.bundle"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
# Rebuilding in place can leave the Dock's closed-app icon cached from an
# earlier bundle. Refresh this bundle's registration after signing it.
touch "$app_path"
launch_services='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [[ -x "$launch_services" ]]; then
    if ! "$launch_services" -f "$app_path"; then
        echo 'Warning: macOS could not refresh the app registration.' >&2
    fi
fi
printf 'Aplicativo: %s\n' "$app_path"

if [[ $# -eq 0 ]]; then
    open "$app_path"
fi
