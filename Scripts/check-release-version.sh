#!/usr/bin/env bash
# Prueft, dass alle Versionsnummern im Repo exakt zum Release-Tag passen.
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

if [ "$status" -eq 0 ]; then
    echo "Alle Versionsnummern stimmen mit $TAG ueberein."
fi
exit "$status"
