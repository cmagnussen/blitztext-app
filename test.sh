#!/usr/bin/env bash
# Fuehrt die Unit-Tests von BlitztextMac aus.
# Beispiel fuer einen einzelnen Test:
#   ./test.sh -only-testing:BlitztextMacTests/VaultInboxDocumentDateTests/testViertelVorVierGehoertZumVortag
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/BlitztextMac"

if command -v xcodegen &> /dev/null; then
    xcodegen generate > /dev/null
fi

xcodebuild test \
    -project BlitztextMac.xcodeproj \
    -scheme BlitztextMac \
    -destination 'platform=macOS' \
    -derivedDataPath "$SCRIPT_DIR/.derivedData-blitztextmac-build" \
    ONLY_ACTIVE_ARCH=YES \
    "$@"
