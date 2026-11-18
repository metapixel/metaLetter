#!/bin/bash
# Baut metaLetter.app (benötigt Xcode oder die Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

echo "▶︎ Kompiliere …"
swift build -c release

APP="build/metaLetter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/metaLetter" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

if [ -f Icon/icon_1024.png ]; then
  echo "▶︎ Erzeuge Icon …"
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Icon/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d Icon/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP" >/dev/null
echo "✅ Fertig: $APP"
echo "   Installieren:  mv \"$APP\" /Applications/"
