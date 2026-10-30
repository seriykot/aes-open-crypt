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

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aesopen-pkg.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/Applications"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$APP" "$ROOT/Applications/AES Open Crypt.app"
chmod +x scripts/pkg/postinstall

pkgbuild --root "$ROOT" --scripts scripts/pkg \
    --identifier dev.aesopencrypt.pkg --version "$VERSION" \
    --install-location / --ownership recommended \
    "$PKG"

echo "$PKG"
