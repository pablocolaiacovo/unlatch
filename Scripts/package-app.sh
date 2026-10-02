#!/usr/bin/env bash
#
# Builds, assembles, ad-hoc signs, and zips Unlatch.app for distribution.
# See issue #7 and RELEASING.md's "Distribution and signing" section.
#
# Usage:
#   Scripts/package-app.sh
#
# Can be run from anywhere; it locates the repository root itself. Produces:
#   dist/Unlatch.app   the assembled, signed app bundle
#   dist/Unlatch.zip   a ditto archive of the bundle, ready to attach to a
#                       GitHub Release
#
# Environment variables:
#   SIGN_IDENTITY   Identity passed to `codesign --sign`. Defaults to "-"
#                   (ad-hoc signing: no Apple Developer account, certificate,
#                   or keychain needed). Issue #8 will pass a
#                   "Developer ID Application: Name (TEAMID)" identity here
#                   instead to switch to real signing; at that point also add
#                   `--options runtime --timestamp` to CODESIGN_ARGS below,
#                   and only there: it is the one argument list used for
#                   every signature in the bundle, nested code included. It
#                   is deliberately not inferred from SIGN_IDENTITY
#                   automatically. Do not add it while ad-hoc signing: under
#                   an ad-hoc signature the hardened runtime turns on library
#                   validation, which breaks loading embedded frameworks such
#                   as Sparkle (#13).
#
# Sparkle:
#   If the built binary links @rpath/Sparkle.framework, the script embeds
#   .build/release/Sparkle.framework in Contents/Frameworks, removes its
#   unused XPC services, and signs it inside-out. A binary that does not link
#   Sparkle skips all of that, so this script works before and after the
#   dependency lands. See Design/sparkle-updates.md, section 2.3.
#
# Version:
#   CFBundleShortVersionString comes from `git describe --tags`, leading "v"
#   stripped. CFBundleVersion is the commit count on HEAD, which only grows
#   as long as history stays linear (this repo squash-merges every PR onto
#   main, per RELEASING.md). An untagged tree still produces a usable dev
#   version, 0.0.0-<shortsha>. The git tag is the only source of truth for
#   the version; nothing in the repository is bumped by hand.
#
#   If a future CI job (#9) calls this script, it must fetch full history and
#   tags first (`actions/checkout` with `fetch-depth: 0`) - the default
#   shallow, tagless checkout makes both `git describe --tags` and
#   `git rev-list --count` meaningless.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Unlatch"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "==> Determining version from git"
if EXACT_TAG="$(git describe --tags --exact-match 2>/dev/null)"; then
    SHORT_VERSION="${EXACT_TAG#v}"
elif DESCRIBE="$(git describe --tags --dirty 2>/dev/null)"; then
    SHORT_VERSION="${DESCRIBE#v}"
else
    SHORT_SHA="$(git rev-parse --short HEAD)"
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        SHORT_VERSION="0.0.0-${SHORT_SHA}"
    else
        SHORT_VERSION="0.0.0-${SHORT_SHA}-dirty"
    fi
fi
BUILD_VERSION="$(git rev-list --count HEAD)"

echo "    CFBundleShortVersionString = $SHORT_VERSION"
echo "    CFBundleVersion            = $BUILD_VERSION"

echo "==> Cleaning $DIST_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "==> Building release binary (arm64 + x86_64)"
swift build -c release --product "$APP_NAME" --arch arm64 --arch x86_64

BUILT_BINARY="$REPO_ROOT/.build/release/$APP_NAME"
if [[ ! -f "$BUILT_BINARY" ]]; then
    echo "error: expected build output at $BUILT_BINARY, not found" >&2
    exit 1
fi

cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Writing Info.plist"
PLIST_TEMPLATE="$REPO_ROOT/Resources/Info.plist.template"
if [[ ! -f "$PLIST_TEMPLATE" ]]; then
    echo "error: missing $PLIST_TEMPLATE" >&2
    exit 1
fi
sed \
    -e "s/__SHORT_VERSION__/$SHORT_VERSION/g" \
    -e "s/__BUILD_VERSION__/$BUILD_VERSION/g" \
    "$PLIST_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null

echo "==> Generating AppIcon.icns"
ICONSET="$REPO_ROOT/Resources/AppIcon.iconset"
if [[ -d "$ICONSET" ]]; then
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    # #6 (the iconset) hasn't landed yet. Ship without an icon rather than
    # fail, so #7 can merge independently. Once Resources/AppIcon.iconset
    # exists this branch simply stops being taken - no script change needed.
    echo "warning: $ICONSET not found (issue #6 not yet merged) - packaging without an app icon" >&2
fi

# One argument list for every signature in the bundle, nested code included.
# Issue #8: append `--options runtime --timestamp` HERE, and only here, when
# SIGN_IDENTITY becomes a Developer ID identity. Never while ad-hoc: under an
# ad-hoc signature, hardened runtime turns on library validation, and dyld
# then refuses to load the embedded Sparkle.framework.
CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
sign() { codesign "${CODESIGN_ARGS[@]}" "$@"; }

BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if otool -L "$BINARY" | grep -q '@rpath/Sparkle.framework/'; then
    echo "==> Embedding Sparkle.framework"
    SPARKLE_SRC="$REPO_ROOT/.build/release/Sparkle.framework"
    [[ -d "$SPARKLE_SRC" ]] || { echo "error: binary links Sparkle but $SPARKLE_SRC is missing" >&2; exit 1; }
    otool -l "$BINARY" | grep -q '@executable_path/../Frameworks' \
        || { echo "error: binary has no @executable_path/../Frameworks rpath (Package.swift linkerSettings)" >&2; exit 1; }

    FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    ditto "$SPARKLE_SRC" "$FW"                       # ditto, not cp: keeps the Versions/ symlinks
    [[ -d "$FW/Versions/B" ]] || { echo "error: Sparkle layout changed (no Versions/B); revisit #13's design" >&2; exit 1; }
    # One -verify_arch call per architecture: this lipo rejects several at once.
    for ARCH in arm64 x86_64; do
        lipo "$FW/Versions/B/Sparkle" -verify_arch "$ARCH" \
            || { echo "error: embedded Sparkle is missing the $ARCH slice" >&2; exit 1; }
    done

    # Not sandboxed: Sparkle's XPC services are unused. Sparkle's sandboxing
    # guide allows removing them. Remove the versioned directory AND the
    # top-level symlink; a dangling symlink fails --strict verification.
    rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"

    echo "==> Signing Sparkle inside-out (SIGN_IDENTITY=$SIGN_IDENTITY)"
    sign "$FW/Versions/B/Autoupdate"
    sign "$FW/Versions/B/Updater.app"
    sign "$FW"
fi

echo "==> Signing app (SIGN_IDENTITY=$SIGN_IDENTITY)"
sign "$APP_BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Zipping"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Done"
echo "    $APP_BUNDLE"
echo "    $ZIP_PATH"
