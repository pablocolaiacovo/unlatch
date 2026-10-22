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
# Resources:
#   If the build produced .build/release/UnlatchCore_Unlatch.bundle (the
#   Unlatch target's resources, i.e. the compiled string catalog), the script
#   copies it into Contents/Resources, where Bundle.module looks first, and
#   signs it before the app. A build without it skips all of that. It fails if
#   the bundle has no es.lproj/Localizable.strings: that means the catalog
#   shipped uncompiled, so the app would be English-only. This needs Swift
#   Build, hence the pinned --build-system below. See
#   Design/spanish-localization.md, section 2.3. Separately, every
#   Resources/*.lproj directory (the app's own strings, e.g. the Finder
#   Services menu title in ServicesMenu.strings, which macOS reads from the
#   main bundle and not from the module bundle) is copied into
#   Contents/Resources before the app is signed; none present skips it. The app
#   signature seals Contents/Resources, so these need no signature of their own.
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
# Must match `name:` in Package.swift: SwiftPM names a target's resource bundle
# <package>_<target>.
PACKAGE_NAME="UnlatchCore"
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
swift build -c release --product "$APP_NAME" --arch arm64 --arch x86_64 \
    --build-system swiftbuild

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
# Capture otool output and grep the variable: `otool | grep -q` under
# pipefail fails intermittently (grep exits early, otool dies of SIGPIPE).
LINKED_LIBS="$(otool -L "$BINARY")"
if grep -q '@rpath/Sparkle.framework/' <<<"$LINKED_LIBS"; then
    echo "==> Embedding Sparkle.framework"
    SPARKLE_SRC="$REPO_ROOT/.build/release/Sparkle.framework"
    [[ -d "$SPARKLE_SRC" ]] || { echo "error: binary links Sparkle but $SPARKLE_SRC is missing" >&2; exit 1; }
    LOAD_COMMANDS="$(otool -l "$BINARY")"
    grep -q '@executable_path/../Frameworks' <<<"$LOAD_COMMANDS" \
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

RESOURCE_BUNDLE_SRC="$REPO_ROOT/.build/release/${PACKAGE_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE_SRC" ]]; then
    echo "==> Embedding ${PACKAGE_NAME}_${APP_NAME}.bundle"
    RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Resources/${PACKAGE_NAME}_${APP_NAME}.bundle"
    ditto "$RESOURCE_BUNDLE_SRC" "$RESOURCE_BUNDLE"
    # A raw catalog means the native build system ran: the app would be English-only.
    [[ -f "$RESOURCE_BUNDLE/Contents/Resources/es.lproj/Localizable.strings" ]] \
        || { echo "error: $RESOURCE_BUNDLE has no compiled es.lproj (was it built with --build-system swiftbuild?)" >&2; exit 1; }
    echo "==> Signing resource bundle (SIGN_IDENTITY=$SIGN_IDENTITY)"
    sign "$RESOURCE_BUNDLE"
fi

# Main-bundle localizations (e.g. ServicesMenu.strings for the Finder Services
# menu title, Apple QA1605). Sealed by the app signature below. nullglob makes
# an unmatched pattern expand to nothing, so no lproj directories skips the step.
shopt -s nullglob
LPROJ_DIRS=("$REPO_ROOT"/Resources/*.lproj)
shopt -u nullglob
if (( ${#LPROJ_DIRS[@]} > 0 )); then
    echo "==> Embedding main-bundle localizations"
    for LPROJ in "${LPROJ_DIRS[@]}"; do
        if [[ -d "$LPROJ" ]]; then
            ditto "$LPROJ" "$APP_BUNDLE/Contents/Resources/$(basename "$LPROJ")"
        fi
    done
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
