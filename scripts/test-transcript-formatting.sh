#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blitztext-paragraph-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc -O -module-cache-path "$TEST_DIR/module-cache" \
    "$PROJECT_ROOT/BlitztextMac/Services/TranscriptParagraphService.swift" \
    "$PROJECT_ROOT/tests/TranscriptParagraphServiceTests.swift" \
    -o "$TEST_DIR/paragraph-tests"
"$TEST_DIR/paragraph-tests"
