#!/usr/bin/env bash
# Build a Node.js Android distribution inside the pinned builder image.
set -euo pipefail

readonly BUILDER_VERSION="android-node-builder-r29-v1"
readonly DEFAULT_REPOSITORY="https://github.com/luoqianlin/node.git"
readonly DEFAULT_REF="android11-v24.19.0"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage: node-android-build [--help]

Build modes:
  SOURCE_MODE=mount     Build the checkout mounted at SOURCE_DIR (default).
  SOURCE_MODE=download  Clone REPOSITORY at REF inside the container.

Environment:
  ANDROID_API=30        Android API level, minimum 24.
  ANDROID_ARCH=arm64    arm, arm64, aarch64, x86, or x86_64.
  INTL=small-icu        small-icu, full-icu, or none.
  JOBS=$(nproc)-2        Parallel make jobs, leaving two host CPUs free.
  OUTPUT_DIR             Distribution output directory.
  REPOSITORY             Git URL for SOURCE_MODE=download.
  REF                    Git ref for SOURCE_MODE=download.
  SOURCE_DIR             Mounted checkout for SOURCE_MODE=mount.
  KEEP_BUILD=1           Keep generated out/Release files after the build.
EOF
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  '')
    ;;
  *)
    die "unexpected argument: $1 (use environment variables; see --help)"
    ;;
esac

for command in git install make nproc python3 sha256sum stat tar; do
  require "$command"
done

readonly SOURCE_MODE="${SOURCE_MODE:-mount}"
readonly ANDROID_API="${ANDROID_API:-30}"
readonly ANDROID_ARCH="${ANDROID_ARCH:-arm64}"
readonly INTL="${INTL:-small-icu}"
readonly REPOSITORY="${REPOSITORY:-$DEFAULT_REPOSITORY}"
readonly REF="${REF:-$DEFAULT_REF}"
readonly NDK_DIR="${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT is not set}"
HOST_CPUS="$(nproc)"
readonly HOST_CPUS
readonly JOBS="${JOBS:-$(( HOST_CPUS > 2 ? HOST_CPUS - 2 : 1 ))}"

case "$ANDROID_API" in
  ''|*[!0-9]*) die "ANDROID_API must be a number" ;;
esac
(( ANDROID_API >= 24 )) || die "ANDROID_API must be at least 24"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"

case "$SOURCE_MODE" in
  mount)
    readonly SOURCE_DIR="${SOURCE_DIR:-$PWD}"
    [[ -x "$SOURCE_DIR/android-configure" ]] || die "not a Node.js checkout: $SOURCE_DIR"
    ;;
  download)
    readonly SOURCE_DIR="${SOURCE_DIR:-/tmp/node-android-source}"
    git clone --depth 1 --branch "$REF" "$REPOSITORY" "$SOURCE_DIR"
    ;;
  *)
    die "SOURCE_MODE must be mount or download"
    ;;
esac

case "$ANDROID_ARCH" in
  arm|arm64|aarch64|x86|x86_64) ;;
  *) die "unsupported ANDROID_ARCH: $ANDROID_ARCH" ;;
esac

case "$INTL" in
  small-icu|full-icu|none) ;;
  *) die "INTL must be small-icu, full-icu, or none" ;;
esac

if [[ -z "${OUTPUT_DIR:-}" ]]; then
  OUTPUT_DIR="$SOURCE_DIR/android-build-${ANDROID_ARCH}-api${ANDROID_API}"
fi
readonly OUTPUT_DIR

case "$ANDROID_ARCH" in
  arm) readonly STL_ARCH=arm-linux-androideabi ;;
  arm64|aarch64) readonly STL_ARCH=aarch64-linux-android ;;
  x86) readonly STL_ARCH=i686-linux-android ;;
  x86_64) readonly STL_ARCH=x86_64-linux-android ;;
esac

readonly STL="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$STL_ARCH/libc++_shared.so"
[[ -f "$STL" ]] || die "missing NDK libc++_shared.so: $STL"

cleanup() {
  rm -rf "$SOURCE_DIR/.android-docker-stage"
}
trap cleanup EXIT

cd "$SOURCE_DIR"
if [[ "${KEEP_BUILD:-0}" != 1 ]]; then
  rm -rf "$SOURCE_DIR/out/Release"
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$SOURCE_DIR/.android-docker-stage"

configure_args=(
  --prefix=/usr/local
  --without-npm
  --without-corepack
)
if [[ "$INTL" == none ]]; then
  configure_args+=(--without-intl)
else
  configure_args+=(--with-intl="$INTL")
fi

CC_host="${CC_host:-gcc-13}" \
CXX_host="${CXX_host:-g++-13}" \
./android-configure "$NDK_DIR" "$ANDROID_API" "$ANDROID_ARCH" \
  "${configure_args[@]}"

make -j"$JOBS"
DESTDIR="$SOURCE_DIR/.android-docker-stage" make install

install -Dm755 \
  "$SOURCE_DIR/.android-docker-stage/usr/local/bin/node" \
  "$OUTPUT_DIR/bin/node"
install -Dm755 "$STL" "$OUTPUT_DIR/lib/libc++_shared.so"
cp -a "$SOURCE_DIR/.android-docker-stage/usr/local/include" "$OUTPUT_DIR/"
cp -a "$SOURCE_DIR/.android-docker-stage/usr/local/share" "$OUTPUT_DIR/"

node_version="$(sed -n 's/^#define NODE_VERSION "\(.*\)"/\1/p' src/node_version.h)"
git_revision="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
compiler="$(gcc-13 --version | sed -n '1s/^.*) //p')"
cat > "$OUTPUT_DIR/BUILD-INFO" <<EOF
builder=$BUILDER_VERSION
node_version=$node_version
git_revision=$git_revision
target=android-$ANDROID_ARCH
android_api=$ANDROID_API
ndk=r29
host_compiler=$compiler
intl=$INTL
snapshot=true
code_cache=false
EOF

archive="$(dirname "$OUTPUT_DIR")/$(basename "$OUTPUT_DIR").tar.xz"
tar -cJf "$archive" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")"
(cd "$(dirname "$archive")" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
printf 'artifact: %s\n' "$archive"
printf 'node: %s bytes\n' "$(stat -c '%s' "$OUTPUT_DIR/bin/node")"
