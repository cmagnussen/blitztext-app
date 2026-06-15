#!/bin/bash
set -euo pipefail

# Blitztext macOS App - SPM-Build ohne volles Xcode
# Alternative zu build.sh, wenn nur die Command Line Tools installiert sind.
# Baut mit `swift build` (nur native Architektur, kein Universal Binary)
# und setzt das .app-Bundle manuell zusammen.
#
# Verwendung: ./build-spm.sh [--install] [--run] [--debug]

RUN_AFTER=false
INSTALL_APP=false
BUILD_CONFIGURATION="release"

for arg in "$@"; do
    case "$arg" in
        --debug)   BUILD_CONFIGURATION="debug" ;;
        --run)     RUN_AFTER=true ;;
        --install) INSTALL_APP=true ;;
        *)
            echo "Unbekannte Option: $arg"
            echo "Verwendung: ./build-spm.sh [--install] [--run] [--debug]"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/BlitztextMac"
RESOURCES_SRC="$PROJECT_DIR/Resources"

# Versionen aus project.yml lesen (Fallback auf Defaults)
MARKETING_VERSION="$(grep 'MARKETING_VERSION:' "$PROJECT_DIR/project.yml" | sed 's/.*"\(.*\)".*/\1/' || echo "1.5")"
PROJECT_VERSION="$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_DIR/project.yml" | sed 's/.*"\(.*\)".*/\1/' || echo "15")"

echo "🔨 Baue Blitztext mit Swift Package Manager ($BUILD_CONFIGURATION) ..."
cd "$PROJECT_DIR"
swift build -c "$BUILD_CONFIGURATION"

BUILD_DIR="$PROJECT_DIR/.build/$BUILD_CONFIGURATION"
BINARY="$BUILD_DIR/Blitztext"

if [ ! -f "$BINARY" ]; then
    echo "❌ Build fehlgeschlagen – Binary nicht gefunden: $BINARY"
    exit 1
fi

# .app-Bundle zusammensetzen
DEST="$SCRIPT_DIR/Blitztext.app"
echo "📦 Baue App-Bundle: $DEST"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

cp "$BINARY" "$DEST/Contents/MacOS/Blitztext"

# Info.plist mit aufgeloesten Variablen erzeugen
cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>app.blitztext.mac</string>
	<key>CFBundleName</key>
	<string>Blitztext</string>
	<key>CFBundleDisplayName</key>
	<string>Blitztext</string>
	<key>CFBundleExecutable</key>
	<string>Blitztext</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$MARKETING_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$PROJECT_VERSION</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>de</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Blitztext benötigt Mikrofon-Zugriff für die Sprach-Transkription.</string>
	<key>LSUIElement</key>
	<true/>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
</dict>
</plist>
PLIST

# Resources kopieren
cp -f "$RESOURCES_SRC/AppIcon.icns" "$DEST/Contents/Resources/" 2>/dev/null || true
cp -f "$RESOURCES_SRC/menubar_icon.png" "$DEST/Contents/Resources/" 2>/dev/null || true
cp -f "$RESOURCES_SRC/menubar_icon@2x.png" "$DEST/Contents/Resources/" 2>/dev/null || true

# SPM-Resource-Bundles der Dependencies mit ins Bundle nehmen
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$DEST/Contents/Resources/"
done

# Ad-hoc signieren mit Entitlements (Mikrofon, Netzwerk)
echo "🔏 Signiere lokale Development-App ad-hoc (nicht notarisiert) ..."
codesign --force --sign - \
    --entitlements "$RESOURCES_SRC/BlitztextMac.entitlements" \
    "$DEST"

RUN_TARGET="$DEST"

if [ "$INSTALL_APP" = true ]; then
    INSTALL_DEST="/Applications/Blitztext.app"
    if [ ! -w /Applications ]; then
        echo "❌ /Applications ist nicht beschreibbar – installiere stattdessen nach ~/Applications."
        mkdir -p "$HOME/Applications"
        INSTALL_DEST="$HOME/Applications/Blitztext.app"
    fi
    rm -rf "$INSTALL_DEST"
    cp -R "$DEST" "$INSTALL_DEST"
    codesign --force --sign - \
        --entitlements "$RESOURCES_SRC/BlitztextMac.entitlements" \
        "$INSTALL_DEST"
    RUN_TARGET="$INSTALL_DEST"

    # Zwischenkopie im Repo-Ordner entfernen, sonst sieht macOS zwei Blitztext-
    # Kopien und warnt vor doppelten Login-Items / startet die falsche Instanz.
    rm -rf "$DEST"
fi

echo ""
echo "✅ Fertig! App liegt unter:"
echo "   $RUN_TARGET"
echo ""
echo "Hinweis: SPM-Build ist nur fuer die native Architektur ($(uname -m)),"
echo "kein Universal Binary wie bei ./build.sh (benoetigt volles Xcode)."
echo ""
echo "Naechste Schritte:"
echo "1. App starten"
echo "2. Mikrofon erlauben"
echo "3. Fuer direktes Einfuegen zusaetzlich Bedienungshilfen erlauben"
echo "4. In Blitztext deinen eigenen OpenAI API Key eintragen"
echo ""

if [ "$RUN_AFTER" = true ]; then
    echo "🚀 Starte Blitztext ..."
    open "$RUN_TARGET"
fi
