#!/usr/bin/env bash
# Prueft, dass alle Versionsnummern im Repo exakt zum Release-Tag passen und
# dass beide oeffentlichen Update-Schluessel hinterlegt sind.
# Nutzung: Scripts/check-release-version.sh v1.6.0
set -euo pipefail

TAG="${1:?Tag erwartet, zum Beispiel v1.6.0}"
EXPECTED="${TAG#v}"

if ! [[ "$EXPECTED" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Tag '$TAG' ist kein dreistelliges Semver. Erwartet wird vX.Y.Z." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

mac_version="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\} *$/\1/p' BlitztextMac/project.yml | head -1)"
win_package="$(node -p "require('./BlitztextWin/package.json').version")"
win_tauri="$(node -p "require('./BlitztextWin/src-tauri/tauri.conf.json').version")"

status=0
check() {
    local datei="$1"
    local wert="$2"
    if [ "$wert" != "$EXPECTED" ]; then
        echo "$datei steht auf '$wert', erwartet wird '$EXPECTED'." >&2
        status=1
    fi
}

check "BlitztextMac/project.yml (MARKETING_VERSION)" "$mac_version"
check "BlitztextWin/package.json (version)" "$win_package"
check "BlitztextWin/src-tauri/tauri.conf.json (version)" "$win_tauri"

# Ohne oeffentlichen Schluessel lehnt jeder Client das Update ab. Das faellt
# erst beim Nutzer auf, deshalb gehoert es hierher.
check_schluessel() {
    local datei="$1"
    local wert="$2"
    if [ -z "$wert" ]; then
        echo "$datei ist leer. Ohne oeffentlichen Schluessel lehnt jede Installation das Update ab." >&2
        status=1
    fi
}

# Kein PlistBuddy und kein plutil: dieses Skript laeuft auch auf dem
# Windows-Runner. Gelesen wird die Zeile direkt nach dem Schluesselnamen.
mac_pubkey="$(sed -n '/<key>BLZUpdatePublicKey<\/key>/{n;p;}' BlitztextMac/Resources/Info.plist \
    | sed -e 's/.*<string>//' -e 's/<\/string>.*//' -e 's/[[:space:]]//g')"
win_pubkey="$(node -p "(require('./BlitztextWin/src-tauri/tauri.conf.json').plugins?.updater?.pubkey || '').trim()")"

check_schluessel "BlitztextMac/Resources/Info.plist (BLZUpdatePublicKey)" "$mac_pubkey"
check_schluessel "BlitztextWin/src-tauri/tauri.conf.json (plugins.updater.pubkey)" "$win_pubkey"

if [ "$status" -eq 0 ]; then
    echo "Alle Versionsnummern stimmen mit $TAG ueberein, beide Update-Schluessel sind hinterlegt."
fi
exit "$status"
