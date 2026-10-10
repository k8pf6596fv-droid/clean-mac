#!/bin/bash
# Compile CLEAN pour Apple Silicon, assemble CLEAN.app, vérifie, puis crée le .dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
VERSION="${VERSION#v}"
BUILD="${BUILD_NUMBER:-1}"
IDENTITY="${CODESIGN_IDENTITY:--}"   # "-" = signature ad hoc (sans certificat Apple)
OUT="dist"
APP="$OUT/CLEAN.app"
DMG="$OUT/CLEAN-$VERSION-arm64.dmg"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▶ Compilation (arm64, release)"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/Clean"
test -f "$BIN"

echo "▶ Assemblage de CLEAN.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clean"
chmod +x "$APP/Contents/MacOS/Clean"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▶ Icône"
ICON_TMP="$(mktemp -d)"
if swift scripts/make_icon.swift "$ICON_TMP/icon_1024.png"; then
  ICONSET="$ICON_TMP/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || echo "⚠ icône non convertie"
else
  echo "⚠ icône non générée (l'application fonctionne quand même)"
fi

echo "▶ Signature ($IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

echo "▶ Vérification de l'application"
plutil -lint "$APP/Contents/Info.plist"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Clean")"
echo "Architectures : $ARCHS"
[ "$ARCHS" = "arm64" ] || { echo "ERREUR : le binaire n'est pas arm64 pur"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Signature|Identifier|TeamIdentifier" || true

echo "▶ Création du DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "CLEAN" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

echo "▶ Vérification du contenu du DMG"
MNT="$(mktemp -d)"
hdiutil attach "$DMG" -mountpoint "$MNT" -nobrowse -readonly -quiet
trap 'hdiutil detach "$MNT" -quiet || true' EXIT
test -x "$MNT/CLEAN.app/Contents/MacOS/Clean"
lipo -archs "$MNT/CLEAN.app/Contents/MacOS/Clean"
test -L "$MNT/Applications"
codesign --verify --deep --strict "$MNT/CLEAN.app"

( cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
echo "✅ DMG prêt : $DMG"
ls -lh "$OUT"
