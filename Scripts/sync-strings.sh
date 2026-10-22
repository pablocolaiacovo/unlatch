#!/usr/bin/env bash
#
# Updates Sources/Unlatch/Resources/Localizable.xcstrings from the strings the
# code actually uses. Run it after adding or changing a user-facing string,
# translate the new entries, and commit the catalog. See
# Design/spanish-localization.md, section 2.10.
#
# Usage:
#   Scripts/sync-strings.sh
#
# Can be run from anywhere; it locates the repository root itself. Builds the
# debug configuration with Swift Build, collects the .stringsdata files the
# Unlatch target emits, and passes them to `xcstringstool sync`. It exits
# non-zero if the catalog does not exist yet, or if no .stringsdata is found
# (the path is a Swift Build internal and may move).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CATALOG="$REPO_ROOT/Sources/Unlatch/Resources/Localizable.xcstrings"
if [[ ! -f "$CATALOG" ]]; then
    echo "error: $CATALOG does not exist; nothing to sync before the catalog is created (T1)" >&2
    exit 1
fi

echo "==> Building (debug, Swift Build)"
swift build --build-system swiftbuild

echo "==> Collecting .stringsdata"
STRINGSDATA=()
while IFS= read -r FILE; do
    STRINGSDATA+=("$FILE")
done < <(find "$REPO_ROOT"/.build/out/Intermediates.noindex/*/Debug/Unlatch-p.build/Objects-normal \
    -name '*.stringsdata' ! -name '*-testable-*' 2>/dev/null | sort)

if [[ ${#STRINGSDATA[@]} -eq 0 ]]; then
    echo "error: no .stringsdata found under .build/out/Intermediates.noindex/*/Debug/Unlatch-p.build/Objects-normal; the Swift Build layout may have changed" >&2
    exit 1
fi
echo "    ${#STRINGSDATA[@]} files"

echo "==> Syncing $CATALOG"
xcrun xcstringstool sync "$CATALOG" --stringsdata "${STRINGSDATA[@]}"
