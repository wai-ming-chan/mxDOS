#!/bin/bash
# Build opus + opusfile as static libraries for iOS ARM64.
# Output goes to: ~/dev/ios-dos-emulator/ios-deps/
# Run this once before meson setup build-ios.

set -e

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
IOS_TARGET="arm64-apple-ios15.0"
PREFIX="$HOME/dev/ios-dos-emulator/ios-deps"
JOBS=$(sysctl -n hw.ncpu)

export CC="$(xcrun --sdk iphoneos --find clang)"
export CXX="$(xcrun --sdk iphoneos --find clang++)"
export CFLAGS="-target $IOS_TARGET -isysroot $IOS_SDK -O2"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-target $IOS_TARGET -isysroot $IOS_SDK"

mkdir -p "$PREFIX"
cd /tmp

# ── libogg ────────────────────────────────────────────────────────────────────
echo ">>> Building libogg for iOS..."
rm -rf libogg-1.3.5
curl -fsSL "https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz" | tar xz
cd libogg-1.3.5

./configure \
  --host=aarch64-apple-darwin \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared

make -j"$JOBS"
make install
cd /tmp

# ── opus ──────────────────────────────────────────────────────────────────────
echo ">>> Building opus for iOS..."
rm -rf opus-1.5.2
curl -fsSL "https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz" | tar xz
cd opus-1.5.2

./configure \
  --host=aarch64-apple-darwin \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-extra-programs \
  --disable-doc

make -j"$JOBS"
make install
cd /tmp

# ── opusfile ──────────────────────────────────────────────────────────────────
echo ">>> Building opusfile for iOS..."
rm -rf opusfile-0.12
curl -fsSL "https://downloads.xiph.org/releases/opus/opusfile-0.12.tar.gz" | tar xz
cd opusfile-0.12

PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
./configure \
  --host=aarch64-apple-darwin \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-examples \
  --disable-doc \
  --disable-http

make -j"$JOBS"
make install
cd /tmp

echo ""
echo "Done. iOS deps installed to: $PREFIX"
echo "pkg-config path to pass to meson: $PREFIX/lib/pkgconfig"
