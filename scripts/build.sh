#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
BUILD_DIR="$PROJECT_ROOT/.build"
OUTPUT_DIR="$PROJECT_ROOT/packages"
PACKAGE_ID="$(awk '/^Package: / {print $2}' control)"
PACKAGE_VERSION="${PACKAGE_VERSION:-$(awk '/^Version: / {print $2}' control)}"
PACKAGE_ARCH="iphoneos-arm64"
PACKAGE_NAME="${PACKAGE_ID}_${PACKAGE_VERSION}_${PACKAGE_ARCH}.deb"
DEB_PATH="$OUTPUT_DIR/$PACKAGE_NAME"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-15.0}"
THEOS="${THEOS:-$HOME/theos}"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required tool not found: $1"; }

run_tests() {
    if [ ! -f tests/PNVideoTargetTests.m ]; then
        printf 'No standalone URL tests found; skipping.\n'
        return
    fi
    need clang
    mkdir -p "$BUILD_DIR"
    printf 'Running URL parser tests…\n'
    local mac_sdk
    mac_sdk="$(xcrun --sdk macosx --show-sdk-path)"
    env -u SDKROOT clang -isysroot "$mac_sdk" -fobjc-arc -Wall -Wextra -I. -framework Foundation \
        tests/PNVideoTargetTests.m PNVideoTarget.m -o "$BUILD_DIR/PNVideoTargetTests"
    "$BUILD_DIR/PNVideoTargetTests"
    printf 'Running button placement tests…\n'
    env -u SDKROOT clang -isysroot "$mac_sdk" -fobjc-arc -Wall -Wextra -Werror -I. \
        -framework Foundation -framework CoreGraphics \
        tests/PNButtonLayoutTests.m PNButtonLayout.m -o "$BUILD_DIR/PNButtonLayoutTests"
    "$BUILD_DIR/PNButtonLayoutTests"
    printf 'Running portrait native action rail tests…\n'
    env -u SDKROOT clang -isysroot "$mac_sdk" -fobjc-arc -Wall -Wextra -Werror -I. \
        -framework Foundation -framework CoreGraphics \
        tests/PNPortraitActionRailTests.m PNButtonLayout.m -o "$BUILD_DIR/PNPortraitActionRailTests"
    "$BUILD_DIR/PNPortraitActionRailTests"
}

verify_package() {
    local target="${1:-$DEB_PATH}"
    [ -f "$target" ] || fail "Package does not exist: $target"
    need dpkg-deb
    need lipo
    need otool
    need plutil
    local verify_dir
    verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/bilitopilinara-verify.XXXXXX")"
    dpkg-deb --extract "$target" "$verify_dir"
    local library="$verify_dir/var/jb/Library/MobileSubstrate/DynamicLibraries/BiliToPiliNara.dylib"
    local filter="$verify_dir/var/jb/Library/MobileSubstrate/DynamicLibraries/BiliToPiliNara.plist"
    [ "$(dpkg-deb --field "$target" Package)" = "$PACKAGE_ID" ] || fail 'Wrong package identifier.'
    [ "$(dpkg-deb --field "$target" Architecture)" = "$PACKAGE_ARCH" ] || fail 'Wrong package architecture.'
    [ -f "$library" ] || fail 'Rootless dynamic library missing.'
    [ -f "$filter" ] || fail 'Injection filter missing.'
    [ ! -d "$verify_dir/Library" ] || fail 'Unexpected rootful payload.'
    plutil -lint "$filter"
    lipo "$library" -verify_arch arm64 arm64e
    otool -L "$library" | grep -q '@rpath/CydiaSubstrate.framework/CydiaSubstrate' || fail 'Rootless Substrate link missing.'
    otool -l "$library" | grep -q '/var/jb/Library/Frameworks' || fail 'Rootless framework search path missing.'
    otool -l "$library" | grep -q '@loader_path/.jbroot/Library/Frameworks' || fail 'Relocated rootless search path missing.'
    otool -l "$library" | grep -q LC_CODE_SIGNATURE || fail 'Ad-hoc code signature missing.'
    [ -s "$verify_dir/var/jb/usr/share/doc/$PACKAGE_ID/SOURCE-COMMIT.txt" ] || fail 'Source provenance missing.'
    rm -rf "$verify_dir"
    printf 'Verified rootless DEB: %s\n' "$target"
    dpkg-deb --info "$target"
}

build_package() {
    need clang
    need lipo
    need ldid
    need dpkg-deb
    need shasum
    need plutil
    [ -f Tweak.m ] || fail 'Tweak.m is missing.'
    [ -f PNVideoTarget.m ] || fail 'PNVideoTarget.m is missing.'
    local sdk="${SDKROOT:-}"
    if [ -z "$sdk" ]; then
        if [ -d "$THEOS/sdks/iPhoneOS16.5.sdk" ]; then
            sdk="$THEOS/sdks/iPhoneOS16.5.sdk"
        else
            sdk="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)" || fail 'Set SDKROOT to an iPhoneOS SDK, or install Xcode.'
        fi
    fi
    [ -d "$sdk" ] || fail "iPhoneOS SDK not found: $sdk"
    local substrate_dir="$THEOS/vendor/lib/iphone/rootless"
    [ -f "$substrate_dir/CydiaSubstrate.framework/CydiaSubstrate.tbd" ] || fail "Rootless Substrate stub not found under $THEOS/vendor/lib; initialize the Theos vendor/lib submodule."
    local source_commit source_state
    source_commit="$(git rev-parse --verify HEAD 2>/dev/null || printf uncommitted)"
    source_state=clean
    if [ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]; then source_state=dirty; fi
    export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}"
    export ZERO_AR_DATE=1
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
    run_tests
    plutil -lint BiliToPiliNara.plist
    local stage="$BUILD_DIR/stage"
    rm -rf "$stage"
    local install_dir="$stage/var/jb/Library/MobileSubstrate/DynamicLibraries"
    local doc_dir="$stage/var/jb/usr/share/doc/$PACKAGE_ID"
    mkdir -p "$stage/DEBIAN" "$install_dir" "$doc_dir"
    local arch
    for arch in arm64 arm64e; do
        printf 'Building %s (iOS %s+)…\n' "$arch" "$MIN_IOS_VERSION"
        clang -target "$arch-apple-ios$MIN_IOS_VERSION" -isysroot "$sdk" \
            -fobjc-arc -fblocks -O2 -Wall -Wextra -I. \
            "-ffile-prefix-map=$PROJECT_ROOT=." "-ffile-prefix-map=$sdk=/SDK" \
            -F "$substrate_dir" -framework Foundation -framework UIKit -framework CoreGraphics -framework CydiaSubstrate \
            -dynamiclib -Wl,-no_uuid -Wl,-headerpad_max_install_names \
            -Wl,-install_name,@rpath/BiliToPiliNara.dylib \
            -Wl,-rpath,/var/jb/Library/Frameworks -Wl,-rpath,/var/jb/usr/lib \
            '-Wl,-rpath,@loader_path/.jbroot/Library/Frameworks' '-Wl,-rpath,@loader_path/.jbroot/usr/lib' \
            Tweak.m PNVideoTarget.m PNButtonLayout.m -o "$BUILD_DIR/BiliToPiliNara.$arch.dylib"
    done
    lipo -create "$BUILD_DIR/BiliToPiliNara.arm64.dylib" "$BUILD_DIR/BiliToPiliNara.arm64e.dylib" \
        -output "$install_dir/BiliToPiliNara.dylib"
    ldid -S "$install_dir/BiliToPiliNara.dylib"
    cp BiliToPiliNara.plist "$install_dir/BiliToPiliNara.plist"
    awk -v version="$PACKAGE_VERSION" '/^Version:/ {$0="Version: " version} {print}' control > "$stage/DEBIAN/control"
    {
        printf 'Repository: https://github.com/Caun1112/BiliToPiliNara\n'
        printf 'Commit: %s\nWorking tree: %s\nVersion: %s\nSource date epoch: %s\n' "$source_commit" "$source_state" "$PACKAGE_VERSION" "$SOURCE_DATE_EPOCH"
        printf '\nSource SHA256:\n'
        shasum -a 256 Tweak.m PNVideoTarget.m PNVideoTarget.h PNButtonLayout.m PNButtonLayout.h BiliToPiliNara.plist control Makefile scripts/build.sh
    } > "$doc_dir/SOURCE-COMMIT.txt"
    cp "$doc_dir/SOURCE-COMMIT.txt" "$OUTPUT_DIR/SOURCE-COMMIT.txt"
    cp LICENSE THIRD_PARTY_NOTICES.md "$doc_dir/"
    find "$stage" -type d -exec chmod 755 {} +
    find "$stage" -type f -exec chmod 644 {} +
    chmod 755 "$install_dir/BiliToPiliNara.dylib"
    # Normalize tar timestamps; dpkg also honors SOURCE_DATE_EPOCH for ar headers.
    local timestamp
    timestamp="$(date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%d%H%M.%S)"
    TZ=UTC find "$stage" -exec touch -t "$timestamp" {} +
    dpkg-deb --root-owner-group --uniform-compression -Zxz -z9 --build "$stage" "$DEB_PATH"
    verify_package "$DEB_PATH"
    (cd "$OUTPUT_DIR" && shasum -a 256 "$PACKAGE_NAME" SOURCE-COMMIT.txt > SHA256SUMS)
    printf '\nBuilt %s\n' "$DEB_PATH"
    cat "$OUTPUT_DIR/SHA256SUMS"
}

case "${1:-package}" in
    package) build_package ;;
    test) run_tests ;;
    verify) verify_package "${2:-$DEB_PATH}" ;;
    clean) rm -rf "$BUILD_DIR" "$OUTPUT_DIR" ;;
    *) fail 'Usage: scripts/build.sh [package|test|verify [package.deb]|clean]' ;;
esac
