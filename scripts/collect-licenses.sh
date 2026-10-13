#!/bin/bash
set -euo pipefail
# Builds BlitztextShared/Licenses/Licenses.txt: our notices plus the full license
# (and NOTICE) text of every Swift package the apps link. Shipped inside the apps,
# as MIT, Apache 2.0, OFL and CC BY require for binary distribution.
#
#   ./scripts/collect-licenses.sh <path-to-SourcePackages/checkouts>
#
# Run after dependency updates (checkouts come from a build's derived data).

CHECKOUTS="${1:?Pfad zu SourcePackages/checkouts angeben}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/BlitztextShared/Licenses/Licenses.txt"
mkdir -p "$(dirname "$OUT")"

{
    echo "Blitztext: Lizenzen und Hinweise / Licenses and notices"
    echo "========================================================"
    echo
    cat "$ROOT/THIRD_PARTY_NOTICES.md"
    echo
    echo
    echo "Public Sans: SIL Open Font License 1.1"
    echo "--------------------------------------"
    echo "Copyright (c) 2015 The Public Sans Project Authors (https://github.com/uswds/public-sans)"
    echo "Full license text: https://openfontlicense.org/open-font-license-official-text/"
    for dir in "$CHECKOUTS"/*/; do
        name="$(basename "$dir")"
        for file in "$dir"LICENSE "$dir"LICENSE.txt "$dir"LICENSE.md "$dir"NOTICE "$dir"NOTICE.txt; do
            [ -f "$file" ] || continue
            echo
            echo
            echo "$name: $(basename "$file")"
            printf '%*s\n' $(( ${#name} + ${#file} - ${#dir} + 2 )) '' | tr ' ' '-'
            cat "$file"
        done
    done
} > "$OUT"

echo "Geschrieben: $OUT ($(wc -l < "$OUT") Zeilen)"
