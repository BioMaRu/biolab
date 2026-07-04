#!/bin/bash
# Build a polished install DMG for BioLab: app + Applications alias, a
# Flint-themed background with a drag arrow, and a laid-out icon-view window.
#   ./make-dmg.sh            → dist/BioLab-<version>.dmg
# Run ./build.sh first (needs dist/BioLab.app).
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/BioLab.app"
VOL="BioLab"
[ -d "$APP" ] || { echo "✗ $APP not found — run ./build.sh first"; exit 1; }
VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/BioLab-$VER.dmg"

STAGE="$(mktemp -d)"
RW="$(mktemp -u).dmg"
cleanup() { rm -rf "$STAGE" "$RW"; }
trap cleanup EXIT

echo "▸ staging"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"

echo "▸ rendering background (1x + 2x → retina tiff)"
swift packaging/dmg-background.swift "$STAGE/.background/bg-1x.png" 1
swift packaging/dmg-background.swift "$STAGE/.background/bg-2x.png" 2
tiffutil -cathidpicheck "$STAGE/.background/bg-1x.png" "$STAGE/.background/bg-2x.png" \
    -out "$STAGE/.background/bg.tiff" >/dev/null
rm -f "$STAGE/.background/bg-1x.png" "$STAGE/.background/bg-2x.png"

echo "▸ creating writable image"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
    -format UDRW -ov "$RW" >/dev/null

DEV="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | egrep '^/dev/' | head -1 | awk '{print $1}')"
sleep 1

echo "▸ laying out install window"
osascript <<OSA || echo "  ⚠︎ Finder layout skipped (grant Automation access to enable the background/arrow); the Applications alias still works"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 104
    set text size of opts to 12
    set background picture of opts to file ".background:bg.tiff"
    set position of item "BioLab.app" of container window to {168, 196}
    set position of item "Applications" of container window to {472, 196}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true

echo "▸ compressing"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
