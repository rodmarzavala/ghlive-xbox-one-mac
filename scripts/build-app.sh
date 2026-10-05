#!/usr/bin/env bash
# Builds the universal GHLive.app and the ghlive CLI, ad-hoc signs them and packs both into dist/.
# The version comes from the VERSION file; the build fails if the compiled code disagrees with it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUNDLE_ID="io.github.rodmarzavala.ghlive"
MIN_MACOS="13.0"
DIST="$ROOT/dist"
APP="$DIST/GHLive.app"
APP_ZIP="GHLive-${VERSION}-macos-universal.zip"
CLI_TARBALL="ghlive-${VERSION}-macos-universal.tar.gz"
EXPECTED_ARCHS="x86_64 arm64"
# CFBundleShortVersionString must be numeric, so a prerelease keeps its suffix only in CFBundleVersion, which
# stays distinct between 0.1.0-beta.1 and 0.1.0. Non-App-Store bundles tolerate that format.
SHORT_VERSION="${VERSION%%-*}"

verify_universal() {
    local binary="$1" archs arch
    archs="$(lipo -archs "$binary")"
    echo "$(basename "$binary") architectures: ${archs}"
    for arch in $EXPECTED_ARCHS; do
        [[ " $archs " == *" $arch "* ]] || { echo "error: $(basename "$binary") lacks ${arch}" >&2; exit 1; }
    done
}

echo "==> Building GHLive ${VERSION} (universal)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

reported="$("$BIN_DIR/ghlive" --version)"
if [[ "$reported" != "ghlive ${VERSION}" ]]; then
    echo "error: VERSION is ${VERSION} but the binary reports '${reported}'. Update GHLiveInfo.version." >&2
    exit 1
fi

echo "==> Assembling ${APP}"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GHLiveApp" "$APP/Contents/MacOS/GHLiveApp"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>GHLiveApp</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>GHLive</string>
    <key>CFBundleDisplayName</key><string>GHLive</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 The GHLive Xbox One for Mac contributors. MIT License.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
verify_universal "$APP/Contents/MacOS/GHLiveApp"

echo "==> Packing"
ditto -c -k --keepParent "$APP" "$DIST/$APP_ZIP"

CLI_STAGE="$DIST/cli"
mkdir -p "$CLI_STAGE"
cp "$BIN_DIR/ghlive" "$CLI_STAGE/ghlive"
codesign --force --sign - "$CLI_STAGE/ghlive"
verify_universal "$CLI_STAGE/ghlive"
tar -czf "$DIST/$CLI_TARBALL" -C "$CLI_STAGE" ghlive
rm -rf "$CLI_STAGE"

(
    cd "$DIST"
    shasum -a 256 "$APP_ZIP" > "${APP_ZIP}.sha256"
    shasum -a 256 "$CLI_TARBALL" > "${CLI_TARBALL}.sha256"
)

echo "==> Done"
ls -l "$DIST"
