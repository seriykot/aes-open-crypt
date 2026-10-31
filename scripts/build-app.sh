#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AES Open Crypt"
BUNDLE="dist/$APP_NAME.app"
CONFIG="${CONFIG:-release}"
UNIVERSAL="${UNIVERSAL:-1}"

build_product() {
    if [[ "$UNIVERSAL" == "1" ]]; then
        swift build -c "$CONFIG" --arch arm64 --arch x86_64 --product "$1"
    else
        swift build -c "$CONFIG" --product "$1"
    fi
}

bin_path() {
    if [[ "$UNIVERSAL" == "1" ]]; then
        swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path
    else
        swift build -c "$CONFIG" --show-bin-path
    fi
}

build_product AESOpenCrypt
build_product aesopen
BIN_DIR="$(bin_path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/bin"

cp "$BIN_DIR/AESOpenCrypt" "$BUNDLE/Contents/MacOS/AESOpenCrypt"
cp "$BIN_DIR/aesopen" "$BUNDLE/Contents/Resources/bin/aesopen"

if [[ "$UNIVERSAL" == "1" ]]; then
    for binary in "$BUNDLE/Contents/MacOS/AESOpenCrypt" "$BUNDLE/Contents/Resources/bin/aesopen"; do
        lipo -info "$binary" | grep -q "x86_64" && lipo -info "$binary" | grep -q "arm64" \
            || { echo "Missing architecture in $binary" >&2; exit 1; }
    done
fi
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
