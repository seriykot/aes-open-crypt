#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="dist/AES Open Crypt.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" App/Info.plist)
PKG="dist/AES Open Crypt $VERSION.pkg"

if [[ ! -d "$APP" ]]; then
    echo "Build the app first: ./scripts/build-app.sh" >&2
    exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/aesopen-pkg.XXXXXX")
ROOT="$WORK/root"
COMPONENT_PLIST="$WORK/component.plist"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ROOT/Applications"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$APP" "$ROOT/Applications/AES Open Crypt.app"
chmod +x scripts/pkg/postinstall

# Without this, Installer relocates the app to any existing copy with the same
# bundle identifier (for example a checkout's dist/ build) and the postinstall
# script then cannot find it in /Applications.
pkgbuild --analyze --root "$ROOT" "$COMPONENT_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"

pkgbuild --root "$ROOT" --component-plist "$COMPONENT_PLIST" --scripts scripts/pkg \
    --identifier dev.aesopencrypt.pkg --version "$VERSION" \
    --install-location / --ownership recommended \
    "$PKG"

echo "$PKG"
