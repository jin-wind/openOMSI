#!/bin/sh
# Build the iPhone/iPad app bundle (arm64). Set IOS_PLATFORM=iphonesimulator for an
# Apple-silicon Simulator build. The Rust game is a static library and the
# tiny Objective-C host lets winit own UIApplicationMain, as required by its iOS backend.
# The device IPA must be re-signed and provisioned by a sideloader before installation.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"

[ "$(uname -s)" = Darwin ] || { echo "Run this script on macOS." >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "Install Rust from https://rustup.rs, then run this script again." >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "Install Xcode with the iOS SDK first." >&2; exit 1; }

platform="${IOS_PLATFORM:-iphoneos}"
case "$platform" in
    iphoneos)
        target=aarch64-apple-ios
        sdk_name=iphoneos
        min_flag_name=miphoneos-version-min
        out=dist/ios
        ipa_suffix=ios-device-sideload
        ;;
    iphonesimulator)
        target=aarch64-apple-ios-sim
        sdk_name=iphonesimulator
        min_flag_name=mios-simulator-version-min
        out=dist/ios-simulator
        ipa_suffix=ios-simulator
        ;;
    *)
        echo "IOS_PLATFORM must be iphoneos or iphonesimulator." >&2
        exit 1
        ;;
esac
min_ios="${IOS_MIN_VERSION:-15.0}"
version="${OPENOMSI_VERSION:-$(sh scripts/version.sh 2>/dev/null || echo 0.0.0)}"
build_number="${IOS_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
printf '%s\n' "$min_ios" | LC_ALL=C grep -Eq '^[0-9]+(\.[0-9]+){0,2}$' || {
    echo "IOS_MIN_VERSION must be a numeric iOS version (for example, 15.0)." >&2; exit 1;
}
printf '%s\n' "$version" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "OPENOMSI_VERSION must contain three numeric components (for example, 0.1.851)." >&2; exit 1;
}
printf '%s\n' "$build_number" | LC_ALL=C grep -Eq '^[1-9][0-9]{0,3}$' || {
    echo "IOS_BUILD_NUMBER must be an integer from 1 to 9999." >&2; exit 1;
}

sdk="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
sdk_version="$(xcrun --sdk "$sdk_name" --show-sdk-version)"
export SDKROOT="$sdk"
export OPENOMSI_VERSION="$version"
export IPHONEOS_DEPLOYMENT_TARGET="$min_ios"
# Pass the deployment target to C/C++ build scripts used by transitive dependencies too.
case "$platform" in
    iphoneos)
        export CFLAGS_aarch64_apple_ios="${CFLAGS_aarch64_apple_ios:-} -miphoneos-version-min=$min_ios"
        export CXXFLAGS_aarch64_apple_ios="${CXXFLAGS_aarch64_apple_ios:-} -miphoneos-version-min=$min_ios"
        ;;
    iphonesimulator)
        export CFLAGS_aarch64_apple_ios_sim="${CFLAGS_aarch64_apple_ios_sim:-} -mios-simulator-version-min=$min_ios"
        export CXXFLAGS_aarch64_apple_ios_sim="${CXXFLAGS_aarch64_apple_ios_sim:-} -mios-simulator-version-min=$min_ios"
        ;;
esac
export CMAKE_OSX_DEPLOYMENT_TARGET="$min_ios"
export CMAKE_OSX_SYSROOT="$sdk"
# Vendored Lua does not track deployment flags in Cargo's build cache. Keep native
# objects built for different SDKs/deployment targets in separate directories.
cargo_base="${CARGO_TARGET_DIR:-$PWD/target}"
export CARGO_TARGET_DIR="$cargo_base/ios/$platform-min-$min_ios-sdk-$sdk_version"

rustup target list --installed | grep -qx "$target" || rustup target add "$target"
cargo rustc --locked --release --target "$target" -p omsi-app --lib --crate-type staticlib

app="$out/openOMSI.app"
rm -rf "$app"
mkdir -p "$app"

xcrun --sdk "$sdk_name" clang \
    -arch arm64 -isysroot "$sdk" "-$min_flag_name=$min_ios" \
    -fobjc-arc ios/main.m ios/game_controller.m "$CARGO_TARGET_DIR/$target/release/libopenomsi_game.a" \
    -framework UIKit -framework Foundation -framework Metal -framework QuartzCore \
    -framework CoreGraphics -framework CoreAudio -framework AudioToolbox \
    -framework GameController -framework Security -framework SystemConfiguration \
    -lc++ -Wl,-fatal_warnings -o "$app/openomsi"

sed -e "s/@VERSION@/$version/g" -e "s/@BUILD_NUMBER@/$build_number/g" \
    -e "s/@MIN_IOS@/$min_ios/g" ios/Info.plist > "$app/Info.plist"
plutil -lint "$app/Info.plist" >/dev/null
cp LICENSE "$app/LICENSE"
# This does not embed a provisioning profile or installation entitlements. A sideloader
# supplies those and replaces the default ad-hoc signature for a physical device.
codesign --force --timestamp=none --sign "${IOS_CODE_SIGN_IDENTITY:--}" "$app" >/dev/null
codesign --verify "$app"

ipa="dist/openOMSI-$version-$ipa_suffix.ipa"
staging="$(mktemp -d "${TMPDIR:-/tmp}/openomsi-ios.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$staging/Payload"
ditto --norsrc --noextattr "$app" "$staging/Payload/openOMSI.app"
rm -f "$ipa"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr "$staging" "$ipa"

printf '\nopenOMSI %s for iOS: %s\n' "$version" "$PWD/$app"
printf 'IPA: %s\n' "$PWD/$ipa"
