#!/bin/bash
# Regenerates the test fixture corpus in Tests/UnlatchCoreTests/Fixtures.
#
# Division of labour:
#   CoreGraphics  authors the neutral base document and the AcroForm sample
#   qpdf          applies all encryption, so the encrypted fixtures come from a
#                 producer other than PDFKit -- otherwise the encryption tests
#                 would only be checking PDFKit against itself
#
# Requires: qpdf (brew install qpdf)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Tests/UnlatchCoreTests/Fixtures"

command -v qpdf >/dev/null || { echo "qpdf not found: brew install qpdf" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"

echo "Authoring base documents with CoreGraphics/PDFKit:"
swift "$ROOT/Scripts/MakeBasePDFs.swift" "$OUT"

echo "Encrypting with qpdf $(qpdf --version | head -1 | awk '{print $3}'):"

# userLocked -- needs a password to open at all.
qpdf --encrypt hunter2 owner 256 -- "$OUT/plain.pdf" "$OUT/user-locked.pdf"
echo "  user-locked.pdf (user password: hunter2)"

# ownerRestricted -- opens freely, but printing and modification are forbidden.
qpdf --encrypt "" owner 256 --print=none --modify=none -- \
    "$OUT/plain.pdf" "$OUT/owner-restricted.pdf"
echo "  owner-restricted.pdf (owner password only, print/modify denied)"

# unreadable -- valid header, body cut off. 2000 bytes is short enough that
# PDFKit cannot reconstruct the cross-reference table.
head -c 2000 "$OUT/plain.pdf" > "$OUT/truncated.pdf"
echo "  truncated.pdf (2000 bytes)"

echo
echo "Corpus written to $OUT"
ls -1 "$OUT"
