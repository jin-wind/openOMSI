#!/bin/sh
# Build the iPhone/iPad app bundle (arm64). Set IOS_PLATFORM=iphonesimulator for an
# Apple-silicon Simulator build. The Rust game is a static library and the
# tiny Objective-C host lets winit own UIApplicationMain, as required by its iOS backend.
# A development bundle is ad-hoc signed; install it on a device with a provisioning
# profile/Xcode signing identity when needed.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"

[ "$(uname -s)" = Darwin ] || { echo "Run this script on macOS." >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "Install Rust from https://rustup.rs, then run this script again." >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "Install Xcode Command Line Tools first." >&2; exit 1; }

platform="${IOS_PLATFORM:-iphoneos}"
case "$platform" in
    iphoneos)
        target=aarch64-apple-ios
        sdk_name=iphoneos
        min_flag_name=miphoneos-version-min
        out=dist/ios
        ;;
    iphonesimulator)
        target=aarch64-apple-ios-sim
        sdk_name=iphonesimulator
        min_flag_name=mios-simulator-version-min
        out=dist/ios-simulator
        ;;
    *)
        echo "IOS_PLATFORM must be iphoneos or iphonesimulator." >&2
        exit 1
        ;;
esac
min_ios="${IOS_MIN_VERSION:-15.0}"
version="${OPENOMSI_VERSION:-$(sh scripts/version.sh 2>/dev/null || echo 0.0.0)}"
export OPENOMSI_VERSION="$version"
export IPHONEOS_DEPLOYMENT_TARGET="$min_ios"
# Pass the deployment target to C/C++ build scripts used by transitive dependencies too.
export CFLAGS_aarch64_apple_ios="-miphoneos-version-min=$min_ios"
export CXXFLAGS_aarch64_apple_ios="-miphoneos-version-min=$min_ios"
export CFLAGS_aarch64_apple_ios_sim="-mios-simulator-version-min=$min_ios"
export CXXFLAGS_aarch64_apple_ios_sim="-mios-simulator-version-min=$min_ios"
export CMAKE_OSX_DEPLOYMENT_TARGET="$min_ios"

rustup target list --installed | grep -qx "$target" || rustup target add "$target"
cargo rustc --locked --release --target "$target" -p omsi-app --lib --crate-type staticlib

sdk="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
app="$out/openOMSI.app"
rm -rf "$app"
mkdir -p "$app"

xcrun --sdk "$sdk_name" clang \
    -arch arm64 -isysroot "$sdk" "-$min_flag_name=$min_ios" \
    ios/main.m "target/$target/release/libopenomsi_game.a" \
    -framework UIKit -framework Foundation -framework Metal -framework QuartzCore \
    -framework CoreGraphics -framework CoreAudio -framework AudioToolbox \
    -framework GameController -framework Security -framework SystemConfiguration \
    -lc++ -o "$app/openomsi"

sed -e "s/@VERSION@/$version/g" -e "s/@MIN_IOS@/$min_ios/g" ios/Info.plist > "$app/Info.plist"
# Ad-hoc signing makes the bundle inspectable and installable on a development device after
# replacing the identity/provisioning settings in Xcode.
codesign --force --timestamp=none --sign "${IOS_CODE_SIGN_IDENTITY:--}" "$app" >/dev/null

printf '\nopenOMSI %s for iOS: %s\n' "$version" "$PWD/$app"
