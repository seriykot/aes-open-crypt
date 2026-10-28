#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AES Open Crypt"
BUNDLE="dist/$APP_NAME.app"
CONFIG="${CONFIG:-release}"

swift build -c "$CONFIG" --product AESOpenCrypt

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp ".build/$CONFIG/AESOpenCrypt" "$BUNDLE/Contents/MacOS/AESOpenCrypt"
cp App/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

if [[ -f App/AppIcon.icns ]]; then
    cp App/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$BUNDLE" >/dev/null 2>&1

echo "$BUNDLE"
