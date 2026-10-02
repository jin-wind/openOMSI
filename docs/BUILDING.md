# Building from source

Releases for every commit are on the [Releases](https://github.com/openOMSI-Project/openOMSI/releases)
page; build from source only to work on openOMSI itself.

All scripts live in `scripts/`, run from any folder (paths with spaces are fine) and put the
result into `dist/<platform>/`. On desktop that folder is also the game's **content folder**
(mods go beside the binary), so the scripts replace only the binaries and never delete
anything else there. Mobile apps keep content in writable app storage instead.

## Requirements

* [Rust stable](https://rustup.rs), 1.85 or newer.
* **macOS**: Xcode Command Line Tools (`xcode-select --install`). Metal is used for drawing.
* **Windows**: Rust *x86_64 MSVC* and Visual Studio Build Tools with *Desktop development
  with C++* and the Windows SDK. CMake is needed to build the OpenXR dependency;
  it must be on `PATH`. Vulkan or DirectX 12 is used for drawing.
* **Linux** (Debian/Ubuntu names):
  `sudo apt install build-essential pkg-config libasound2-dev libudev-dev libgtk-3-dev libxkbcommon-dev libwayland-dev libssl-dev`.
  Vulkan drivers (Mesa, NVIDIA) are needed to play.
* **Android**: the `aarch64-linux-android` Rust target, JDK 17, and an Android SDK with
  platform 34 or newer, build-tools and the NDK. `scripts/build-android.sh` looks for them
  through `android/env.sh` (`ANDROID_HOME`, `ANDROID_NDK_HOME`).
* **iOS (experimental)**: macOS, full Xcode with the iOS SDK, and Rust. The script installs
  the `aarch64-apple-ios` Rust target if needed and builds an arm64 app using Metal. Set
  `IOS_PLATFORM=iphonesimulator` for an Apple-silicon Simulator build instead. Real-device
  behavior and older iOS versions have not been verified.

## Build

| Platform | Command | Result |
| --- | --- | --- |
| macOS | `scripts/build-macos.sh` | `dist/macos/openOMSI.app` |
| Windows | `scripts\build-windows.cmd` | `dist\windows\openomsi.exe`, `openomsi-launcher.exe` |
| Windows, from a Mac | `scripts/build-windows-cross.sh` (needs `brew install mingw-w64`) | `dist/windows/` |
| Linux | `scripts/build-linux.sh` | `dist/linux/openomsi`, `openomsi-launcher`, `.desktop` file |
| Android | `scripts/build-android.sh` | `dist/android/openOMSI-<version>.apk` |
| iOS | `scripts/build-ios.sh` | `dist/ios/openOMSI.app`, `dist/openOMSI-<version>-ios-device-sideload.ipa` |
| iOS Simulator (Apple silicon) | `IOS_PLATFORM=iphonesimulator scripts/build-ios.sh` | `dist/ios-simulator/openOMSI.app`, `dist/openOMSI-<version>-ios-simulator.ipa` |
| Dedicated server | `scripts/build-server.sh [folder]` | `dist/server/` with `start.sh` |
| 32-bit plugin host | `scripts/build-plugin-host.sh` | `dist/omsi-plugin-host32.exe` (see [PLUGINS.md](PLUGINS.md)) |

Plain cargo works too: `cargo build --release -p omsi-app` builds `target/release/openomsi`.

## iOS installation and content

The iOS build defaults to a deployment target of 15.0 (`IOS_MIN_VERSION`). This is a build
setting; testing has only covered the installed Simulator runtime. Native build caches are
isolated by platform, deployment target and SDK version under `target/ios/`, or under an
explicit `CARGO_TARGET_DIR`. `OPENOMSI_VERSION` is the three-component numeric display
version. `IOS_BUILD_NUMBER` is a separate integer from 1 to 9999 for `CFBundleVersion`; it
defaults to the Git commit count. Set it explicitly for distribution or shallow clones so
each distributed build gets an increasing number.

The device IPA is ad-hoc signed by default. Install it through a sideloader that re-signs
it and supplies the required provisioning profile and entitlements for the device.
`IOS_CODE_SIGN_IDENTITY` changes the signature but does not supply those installation
requirements. The package is not prepared for App Store submission. The Simulator IPA
contains a different executable and cannot be installed on a physical iPhone or iPad.
For Simulator testing, install the app with `xcrun simctl install booted
dist/ios-simulator/openOMSI.app`, then launch `io.github.openomsi.openomsi`.

Original OMSI 2 content is not included. Launch the app once to create its Documents
folder, then use Files > On My iPhone/iPad > openOMSI, or Finder file sharing over USB, to
copy the complete installation into a folder named `OMSI 2`. The resulting paths must
include `openOMSI/OMSI 2/Omsi.exe`, `openOMSI/OMSI 2/maps` and
`openOMSI/OMSI 2/Vehicles`. Close and reopen the app after the copy completes. Mods belong
in the separate `openOMSI/Content` folder; the signed app bundle is not writable storage.
Diagnostics are written to `openOMSI/Content/Logs/game.log`; the preceding app launch is
kept as `game-prev.log` in the same folder. Neither file includes the original game assets.

Xbox and other extended gamepads use Apple's GameController framework on iOS. Connect
the controller to the iPhone/iPad, or to the Mac for Simulator testing. Keep the Simulator
window in front. The left stick steers, RT accelerates and LT brakes. Default buttons:
A opens/closes the front door; B toggles the parking brake; X holds the horn; Y starts or
shuts down the bus; LB/RB toggle indicators; View changes camera; Menu pauses; D-pad
up/left/down selects D/N/R, and D-pad right operates the second door. L-stick click resets
the view; R-stick click toggles the stop brake. Gear defaults target automatic buses;
custom axes and buttons can be assigned in Controls. Force feedback is not implemented
for this backend. `OMSI_CONTROLLER_TRACE=1` logs stick/trigger changes for Simulator tests.

## The programs

* `openomsi` (`crates/omsi-app`) - the game. Started with no arguments it opens the launcher
  window; with arguments it starts a session directly (see [USER_GUIDE.md](USER_GUIDE.md));
  with `--server server.cfg` it is the dedicated server.
* `openomsi-launcher` (`crates/omsi-launcher-core`) - the launcher's commands for a terminal
  (`openomsi-launcher --cli maps`, `--cli install '{"path":"mod.zip"}'` …).
* `omsi-check` (`tools/omsi-check`) - loads every content file of an installation and reports
  what failed: `cargo run --release -p omsi-check -- "/path/to/OMSI 2"`.

## Icons

The application icon is made from the logos in `assets/logos`:
`assets/icons/app/openomsi.svg` (Windows/Linux) and `openomsi-macos.svg` (macOS, with the
standard margin). `openomsi.ico` is embedded into the Windows executables at build time
(`build.rs`, `winresource`), `openomsi.icns` goes into the macOS bundle, and
`openomsi-256.png` is the window icon on Windows and Linux. To regenerate them after changing
the SVGs (needs `cargo install resvg`):

```sh
scripts/make-icons.sh
```

## Tests

```sh
cargo test --workspace
```

Some tests read an OMSI 2 installation (`OMSI_ROOT=/path/to/OMSI 2`) and skip themselves
when there is none.
