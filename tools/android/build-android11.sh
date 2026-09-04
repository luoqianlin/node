#!/usr/bin/env bash
# Build a self-contained Android arm64 Node.js distribution from this checkout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SOURCE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SOURCE_DIR
readonly NDK_VERSION="r27d"
readonly NDK_ARCHIVE="android-ndk-${NDK_VERSION}-linux.zip"
readonly NDK_SHA1="22105e410cf29afcf163760cc95522b9fb981121"
readonly NDK_URL="https://dl.google.com/android/repository/${NDK_ARCHIVE}"

ANDROID_API="${ANDROID_API:-30}"
ANDROID_ARCH="${ANDROID_ARCH:-arm64}"
BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/out/android-${ANDROID_ARCH}-api${ANDROID_API}}"
DIST_DIR="${DIST_DIR:-$SOURCE_DIR/android-build-${ANDROID_ARCH}-api${ANDROID_API}}"
CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/node-android-build}"
HOST_CPUS="$(nproc)"
DEFAULT_JOBS="$(( HOST_CPUS > 2 ? HOST_CPUS - 2 : 1 ))"
JOBS="${JOBS:-$DEFAULT_JOBS}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

for command in curl sha1sum unzip make tar install nproc; do require "$command"; done

mkdir -p "$CACHE_DIR"
ndk_archive="$CACHE_DIR/$NDK_ARCHIVE"
ndk_dir="$CACHE_DIR/android-ndk-$NDK_VERSION"
if [[ ! -f "$ndk_archive" ]]; then
  curl --fail --location --retry 3 --output "$ndk_archive" "$NDK_URL"
fi
printf '%s  %s\n' "$NDK_SHA1" "$ndk_archive" | sha1sum --check --status || die "NDK checksum mismatch: $ndk_archive"
if [[ ! -d "$ndk_dir" ]]; then
  unzip -q "$ndk_archive" -d "$CACHE_DIR"
fi
[[ -x "$ndk_dir/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]] || die "unsupported host or incomplete NDK: $ndk_dir"

rm -rf "$BUILD_DIR" "$DIST_DIR"
# Node's configure script always generates the default Make output in
# out/Release. Remove it so host and target objects cannot be mixed after a
# toolchain or source-configuration change.
rm -rf "$SOURCE_DIR/out/Release"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

cd "$SOURCE_DIR"
CC_host="${CC_host:-cc}" \
CXX_host="${CXX_host:-c++}" \
./android-configure "$ndk_dir" "$ANDROID_API" "$ANDROID_ARCH" \
  --prefix=/usr/local \
  --with-intl=small-icu \
  --without-npm \
  --without-corepack \
  --without-node-snapshot \
  --without-node-code-cache

make -j"$JOBS"
DESTDIR="$BUILD_DIR/stage" make install

install -Dm755 "$BUILD_DIR/stage/usr/local/bin/node" "$DIST_DIR/bin/node"
install -Dm755 \
  "$ndk_dir/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" \
  "$DIST_DIR/lib/libc++_shared.so"
cp -a "$BUILD_DIR/stage/usr/local/include" "$DIST_DIR/"
cp -a "$BUILD_DIR/stage/usr/local/share" "$DIST_DIR/"

node_version="$(sed -n "s/^#define NODE_VERSION \"\(.*\)\"/\1/p" src/node_version.h)"
git_revision="${GIT_REVISION:-$(git rev-parse HEAD 2>/dev/null || printf 'unknown')}"
cat > "$DIST_DIR/BUILD-INFO" <<EOF
node_version=$node_version
git_revision=$git_revision
target=android-${ANDROID_ARCH}
android_api=$ANDROID_API
ndk=$NDK_VERSION
intl=small-icu
snapshot=false
code_cache=false
EOF
(cd "$(dirname "$DIST_DIR")" && tar -cJf "$(basename "$DIST_DIR").tar.xz" "$(basename "$DIST_DIR")")
(cd "$(dirname "$DIST_DIR")" && sha256sum "$(basename "$DIST_DIR").tar.xz" > "$(basename "$DIST_DIR").tar.xz.sha256")
printf 'artifact: %s\n' "$(dirname "$DIST_DIR")/$(basename "$DIST_DIR").tar.xz"
