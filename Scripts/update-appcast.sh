#!/usr/bin/env bash
#
# Adds one release to the Sparkle appcast and validates the result. See
# issue #13 and Design/sparkle-updates.md, sections 2.6 and 2.7.
#
# Usage:
#   Scripts/update-appcast.sh --zip <Unlatch.zip> --notes <notes.md> \
#       --tag <vX.Y.Z[-beta.N]> --current-feed <appcast.xml or empty> --out <dir>
#
# Environment:
#   SPARKLE_ED_PRIVATE_KEY  Required. Base64 seed from `generate_keys -x`. Piped
#                           to generate_appcast on stdin; never written to
#                           disk and never passed as an argument.
#   SPARKLE_BIN             Directory with generate_appcast. Defaults to the
#                           SwiftPM artifact (run `swift package resolve`).
#   GITHUB_REPOSITORY       owner/name for the download and link URLs.
#
# Writes <dir>/appcast.xml and nothing else. Do not run this under `set -x`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="${SPARKLE_BIN:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
REPO="${GITHUB_REPOSITORY:-pablocolaiacovo/unlatch}"

die() { echo "::error::$*" >&2; exit 1; }

ZIP="" NOTES="" TAG="" CURRENT="" OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip) ZIP="${2:-}"; shift 2 ;;
    --notes) NOTES="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --current-feed) CURRENT="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ -f "$ZIP" ]] || die "--zip must be an existing file"
[[ -f "$NOTES" ]] || die "--notes must be an existing file"
[[ -n "$TAG" ]] || die "--tag is required"
[[ -n "$OUT" ]] || die "--out is required"
[[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]] || die "SPARKLE_ED_PRIVATE_KEY is not set"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || die "generate_appcast not found in $SPARKLE_BIN"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Read the bundle's identity.
ditto -x -k "$ZIP" "$WORK/unzipped"
PLIST="$WORK/unzipped/Unlatch.app/Contents/Info.plist"
[[ -f "$PLIST" ]] || die "Unlatch.app/Contents/Info.plist not found in $ZIP"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
BUILD="$(plist CFBundleVersion)"
SHORT="$(plist CFBundleShortVersionString)"
PUBKEY="$(plist SUPublicEDKey)"
FEED_URL="$(plist SUFeedURL)"
[[ -n "$BUILD" && -n "$PUBKEY" && -n "$FEED_URL" ]] || die "bundle is missing CFBundleVersion, SUPublicEDKey, or SUFeedURL"
[[ "$SHORT" == "${TAG#v}" ]] || die "bundle version '$SHORT' does not match tag '$TAG'"
echo "tag=$TAG build=$BUILD version=$SHORT"

# 2. Betas go to the beta channel; stable has no channel.
CHANNEL=""
if [[ "$TAG" == *-beta.* ]]; then CHANNEL="beta"; fi

# 3. Start from the current feed, minus any item with this build number.
#    Transform to a temp file and move it: a failed transform must not leave
#    an empty appcast.xml behind ("zero length data" in generate_appcast).
if [[ -n "$CURRENT" && -s "$CURRENT" ]]; then
  xsltproc --stringparam build "$BUILD" "$ROOT/Scripts/appcast-drop-build.xsl" "$CURRENT" > "$WORK/appcast.xml.tmp"
  mv "$WORK/appcast.xml.tmp" "$WORK/appcast.xml"
else
  echo "No current feed; starting a new one"
fi

# 4. The new archive and its notes, named so generate_appcast pairs them.
cp "$ZIP" "$WORK/Unlatch.zip"
cp "$NOTES" "$WORK/Unlatch.md"

# 5. Generate and sign. Output is captured into a variable, not piped through
#    grep, so a generate_appcast failure is not masked and SIGPIPE cannot hit.
CHANNEL_ARGS=()
if [[ -n "$CHANNEL" ]]; then CHANNEL_ARGS=(--channel "$CHANNEL"); fi
set +e
GEN_OUTPUT="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$REPO/releases" \
  --embed-release-notes --maximum-deltas 0 ${CHANNEL_ARGS[@]+"${CHANNEL_ARGS[@]}"} \
  -o "$WORK/appcast.xml" "$WORK" 2>&1)"
GEN_STATUS=$?
set -e
echo "$GEN_OUTPUT"
[[ $GEN_STATUS -eq 0 ]] || die "generate_appcast failed with status $GEN_STATUS"

# 6. Validate.
# generate_appcast only warns when the signing key does not match the bundle's
# SUPublicEDKey and still exits 0; such a feed would be rejected by every install.
if grep -qi 'does not match' <<<"$GEN_OUTPUT"; then
  die "generate_appcast reports the signing key does not match SUPublicEDKey in the bundle"
fi
xmllint --noout "$WORK/appcast.xml" || die "appcast.xml is not well-formed XML"

xp() { xmllint --xpath "$1" "$WORK/appcast.xml"; }
ITEM="//item[*[local-name()='version'][.='$BUILD'] or enclosure/@*[local-name()='version'][.='$BUILD']]"
COUNT="$(xp "count($ITEM)")"
[[ "$COUNT" == "1" ]] || die "expected exactly one item for build $BUILD, found $COUNT"
URL="$(xp "string($ITEM/enclosure/@url)")"
[[ "$URL" == */"$TAG"/Unlatch.zip ]] || die "enclosure URL '$URL' does not end in /$TAG/Unlatch.zip"
SIG="$(xp "string($ITEM/enclosure/@*[local-name()='edSignature'])")"
[[ -n "$SIG" ]] || die "enclosure has no sparkle:edSignature"
GOT_CHANNEL="$(xp "string($ITEM/*[local-name()='channel'])")"
[[ "$GOT_CHANNEL" == "$CHANNEL" ]] || die "item channel '$GOT_CHANNEL' is not the expected '${CHANNEL}'"
MINOS="$(xp "string($ITEM/*[local-name()='minimumSystemVersion'])")"
[[ "$MINOS" == "14.0" ]] || die "minimumSystemVersion is '$MINOS', expected 14.0"

# 7. Publish only appcast.xml.
mkdir -p "$OUT"
cp "$WORK/appcast.xml" "$OUT/appcast.xml"
echo "Wrote $OUT/appcast.xml (build $BUILD, channel '${CHANNEL:-stable}')"
