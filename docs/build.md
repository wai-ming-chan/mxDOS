# Building mxDOS

## Requirements

| | |
|---|---|
| **macOS** | 14 Sonoma or later |
| **Xcode** | 15 or later |
| **iOS device** | iOS 15+, ARM64 |
| **Homebrew packages** | `meson` `ninja` `pkg-config` |

---

## Step 1 — Clone dependencies

The upstream sources are excluded from this repo (see `.gitignore`). Clone them into the repo root:

```sh
git clone --branch v0.82.2 --depth 1 \
    https://github.com/dosbox-staging/dosbox-staging.git

git clone --depth 1 \
    https://github.com/libsdl-org/SDL.git SDL2
```

## Step 2 — Build audio libraries

Builds libogg, opus, and opusfile as iOS ARM64 static libraries and installs them into `ios-deps/`. Run once; re-run only if you clean that directory.

```sh
bash scripts/build-ios-deps.sh
```

## Step 3 — Build SDL2 for iOS

```sh
cd SDL2

xcodebuild \
    -project Xcode/SDL/SDL.xcodeproj \
    -scheme "Static Library-iOS" \
    -sdk iphoneos \
    -configuration Release \
    ARCHS=arm64 \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SYMROOT="$(pwd)/build-ios"

mkdir -p ../ios-deps/include/SDL2
cp -r include/*                             ../ios-deps/include/SDL2/
cp build-ios/Release-iphoneos/libSDL2.a     ../ios-deps/lib/

cd ..
```

## Step 4 — Build DOSBox Staging for iOS

> **Note**
> Before running `meson setup`, verify the `-isysroot` path in
> `cmake/ios-meson-cross.ini` matches the SDK shipped with your Xcode version:
> ```sh
> xcrun --sdk iphoneos --show-sdk-path
> ```
> Update the four `-isysroot` entries in `[built-in options]` if they differ.

```sh
cd dosbox-staging

meson setup build-ios \
    --cross-file=../cmake/ios-meson-cross.ini \
    --buildtype=release \
    -Ddefault_library=static \
    -Db_lto=false \
    -Duse_sdl2_net=false \
    -Duse_mt32emu=false \
    -Duse_fluidsynth=false \
    -Duse_slirp=false \
    -Duse_alsa=false \
    -Duse_opengl=false \
    -Dcpp_std=c++17

ninja -C build-ios dosbox

mkdir -p ../ios-deps/include/dosbox
cp build-ios/libdosbox.a   ../ios-deps/lib/libdosbox-ios.a
cp build-ios/config.h      ../ios-deps/include/dosbox/

cd ..
```

## Step 5 — Open in Xcode and run

```sh
open mxDOS/mxDOS.xcodeproj
```

Set your signing team under **mxDOS → Signing & Capabilities**, select your connected device, then press **⌘R**.

> **Note**
> A free Apple Developer account is sufficient. The certificate expires after
> 7 days and must be re-signed via Xcode or [AltStore](https://altstore.io).
> A paid $99/yr account gives a 1-year certificate.
