#!/usr/bin/env bash
#
# Updates Sources/Unlatch/Resources/Localizable.xcstrings from the strings the
# code actually uses. Run it after adding, changing, or removing a user-facing
# string, translate the new entries, and commit the catalog. It deletes the
# entries the code no longer uses, translated or not, and lists them. See
# Design/spanish-localization.md, section 2.10.
#
# Usage:
#   Scripts/sync-strings.sh
#
# Can be run from anywhere; it locates the repository root itself. Builds the
# debug configuration with Swift Build, collects the .stringsdata files the
# Unlatch target emits, and passes them to `xcstringstool sync`. Then it removes
# the entries sync marked stale (see below) and keeps the file ending in a
# newline. Needs jq (in macOS since 15 and on the GitHub runners). It exits
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

# Sync deletes an unused key only when it has no translations; a translated one stays,
# marked "extractionState": "stale", and LocalizationTests rejects it. Delete those here.
# jq's JSON formatting is not xcstringstool's, and a sync with nothing to change does not
# rewrite the file, so jq also adds an empty placeholder entry: the second sync drops it
# as unused and writes the whole catalog back in its own format.
echo "==> Removing stale entries"
STALE=()
while IFS= read -r KEY; do
    STALE+=("$KEY")
done < <(jq -r '.strings | to_entries[] | select(.value.extractionState == "stale") | .key' "$CATALOG")

if [[ ${#STALE[@]} -eq 0 ]]; then
    echo "    none"
else
    PLACEHOLDER="__sync-strings placeholder__"
    PRUNED="$(mktemp "${TMPDIR:-/tmp}/sync-strings.XXXXXX")"
    trap 'rm -f "$PRUNED"' EXIT
    jq --arg placeholder "$PLACEHOLDER" '
        .strings |= (with_entries(select(.value.extractionState != "stale"))
            | .[$placeholder] = {})
    ' "$CATALOG" > "$PRUNED"
    cat "$PRUNED" > "$CATALOG"
    xcrun xcstringstool sync "$CATALOG" --stringsdata "${STRINGSDATA[@]}"

    if jq -e --arg placeholder "$PLACEHOLDER" '
        .strings | has($placeholder) or any(.[]; .extractionState == "stale")
    ' "$CATALOG" > /dev/null; then
        echo "error: $CATALOG still has stale entries or the placeholder after the second sync" >&2
        exit 1
    fi
    for KEY in "${STALE[@]}"; do
        echo "    removed: $KEY"
    done
fi

# xcstringstool writes the file without a final newline whenever it changes it, and leaves
# it alone when nothing changed. Always end with one, so a run on a committed catalog stays
# a no-op whichever way it was last written.
if [[ -n "$(tail -c 1 "$CATALOG")" ]]; then
    printf '\n' >> "$CATALOG"
fi
