#!/bin/bash
# Build BioLab.app from the SPM package.
#   ./build.sh            → release build into dist/BioLab.app
#   ./build.sh --debug    → debug build (faster, for iteration)
#   ./build.sh --run      → build then launch
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
RUN=0
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG="debug" ;;
    --run) RUN=1 ;;
  esac
done

VERSION="1.0.0"
APP="dist/BioLab.app"
BIN=".build/$CONFIG/BioLab"
BUNDLE=".build/$CONFIG/BioLab_BioLab.bundle"
ICON="../desktop/src-tauri/icons/icon.icns"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/BioLab"
[ -d "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/Contents/Resources/"
[ -f "$ICON" ] && cp "$ICON" "$APP/Contents/Resources/icon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>BioLab</string>
	<key>CFBundleIconFile</key><string>icon</string>
	<key>CFBundleIdentifier</key><string>com.biomaru.biolab</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>BioLab</string>
	<key>CFBundleDisplayName</key><string>BioLab</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSHumanReadableCopyright</key><string>© BioMaRu</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ codesign (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "✓ $APP ($CONFIG, v$VERSION)"
if [ "$RUN" = "1" ]; then
  echo "▸ launching"
  open "$APP"
fi
