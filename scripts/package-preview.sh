#!/bin/bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
    echo "Usage: $0" >&2
    exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
build_number="$(plutil -extract CFBundleVersion raw Resources/Info.plist)"
case "$version" in
    *[!0-9.]*|'') echo 'Invalid app version' >&2; exit 1 ;;
esac
case "$build_number" in
    *[!0-9]*|'') echo 'Invalid app build number' >&2; exit 1 ;;
esac
name="IR2Studio-${version}-macOS-arm64-preview.${build_number}"
mkdir -p "$project_dir/work" "$project_dir/dist"
stage="$(mktemp -d "$project_dir/work/release.XXXXXX")"
payload="$stage/payload"
app="$payload/IR2Studio.app"
scratch="$project_dir/work/release-build"

build_options=(-c release --arch arm64 --scratch-path "$scratch"
    -Xswiftc -file-prefix-map -Xswiftc "$project_dir=/IR2Studio"
    -Xswiftc -file-compilation-dir -Xswiftc /IR2Studio)
swift build "${build_options[@]}"
bin_dir="$(swift build "${build_options[@]}" --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/IR2Studio" "$app/Contents/MacOS/IR2Studio"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp docs/INSTALL.txt "$payload/READ ME FIRST.txt"

[[ "$(lipo -archs "$app/Contents/MacOS/IR2Studio")" == "arm64" ]]
# Remove linker debug records (including absolute object-file paths) before signing.
xcrun strip -S "$app/Contents/MacOS/IR2Studio"
"$project_dir/scripts/check-package-privacy.sh" "$payload"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

# Archive before adding the Applications shortcut, which is only needed in the DMG.
ditto -c -k --sequesterRsrc "$payload" "$stage/$name.zip"
ditto -x -k "$stage/$name.zip" "$stage/zip-check"
test -x "$stage/zip-check/IR2Studio.app/Contents/MacOS/IR2Studio"
codesign --verify --deep --strict "$stage/zip-check/IR2Studio.app"
"$project_dir/scripts/check-package-privacy.sh" "$stage/zip-check"
ln -s /Applications "$payload/Applications"
hdiutil create -volname 'IR-2 Studio' -srcfolder "$payload" -format UDZO "$stage/$name.dmg"
hdiutil verify "$stage/$name.dmg"

(
    cd "$stage"
    shasum -a 256 "$name.zip" "$name.dmg" > "$name.sha256"
    shasum -a 256 -c "$name.sha256"
)
for extension in zip dmg sha256; do
    mv -f "$stage/$name.$extension" "$project_dir/dist/$name.$extension"
done
printf '\nPreview packages (not notarized):\n%s\n%s\n%s\n' \
    "$project_dir/dist/$name.zip" "$project_dir/dist/$name.dmg" "$project_dir/dist/$name.sha256"
