#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AES Open Crypt"
BUNDLE="dist/$APP_NAME.app"
CONFIG="${CONFIG:-release}"

swift build -c "$CONFIG" --product AESOpenCrypt
swift build -c "$CONFIG" --product aesopen

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/bin"

cp ".build/$CONFIG/AESOpenCrypt" "$BUNDLE/Contents/MacOS/AESOpenCrypt"
cp ".build/$CONFIG/aesopen" "$BUNDLE/Contents/Resources/bin/aesopen"
chmod +x "$BUNDLE/Contents/Resources/bin/aesopen"
cp App/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

if [[ -f App/AppIcon.icns ]]; then
    cp App/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$BUNDLE/Contents/Resources/bin/aesopen" >/dev/null 2>&1
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1
codesign --verify --deep --strict "$BUNDLE"

echo "$BUNDLE"
