#!/usr/bin/env bash
# Build an arm64 local copy. Keep the installed upstream app intact.
set -euo pipefail
cd "$(dirname "$0")/.."
make xcode
build=(xcodebuild -project OpenDisplay.xcodeproj -configuration Release -derivedDataPath .build/xcode
       -destination 'generic/platform=macOS' ARCHS=arm64 CODE_SIGN_STYLE=Manual
       CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
for scheme in OpenDisplay opendisplay; do
    "${build[@]}" -scheme "$scheme" build
done
products=.build/xcode/Build/Products/Release
mkdir -p dist
stage=$(mktemp -d "$PWD/.build/lenovo-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
bundle="$stage/OpenDisplay.app"
ditto "$products/OpenDisplay.app" "$bundle"
mkdir -p "$bundle/Contents/Helpers"
cp "$products/opendisplay" "$bundle/Contents/Helpers/"
codesign --force --preserve-metadata=entitlements,flags --sign - "$bundle"
codesign --verify --strict --deep "$bundle"
"$bundle/Contents/Helpers/opendisplay" help >/dev/null
ditto -c -k --keepParent "$bundle" "$stage/OpenDisplay-Lenovo.zip"
if [[ -e dist/OpenDisplay.app ]]; then
    mv dist/OpenDisplay.app "$stage/previous.app"
fi
mv "$bundle" dist/OpenDisplay.app
mv -f "$stage/OpenDisplay-Lenovo.zip" dist/
echo "Built dist/OpenDisplay.app and dist/OpenDisplay-Lenovo.zip"
