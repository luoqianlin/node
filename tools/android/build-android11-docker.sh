#!/bin/sh
# Run the reproducible Android builder through Docker.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE_DIR="${SOURCE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
IMAGE="${IMAGE:-node-android-builder:r29}"
SOURCE_MODE="${SOURCE_MODE:-mount}"
HOST_CPUS="$(nproc)"
JOBS="${JOBS:-$(( HOST_CPUS > 2 ? HOST_CPUS - 2 : 1 ))}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || die 'missing required command: docker'
command -v nproc >/dev/null 2>&1 || die 'missing required command: nproc'
[ -d "$SOURCE_DIR" ] || die "missing source directory: $SOURCE_DIR"

if [ "${BUILD_IMAGE:-1}" = 1 ]; then
  set -- build --tag "$IMAGE" --file "$SCRIPT_DIR/Dockerfile"
  [ -n "${HTTP_PROXY:-}" ] && set -- "$@" --build-arg "HTTP_PROXY=$HTTP_PROXY"
  [ -n "${HTTPS_PROXY:-}" ] && set -- "$@" --build-arg "HTTPS_PROXY=$HTTPS_PROXY"
  [ -n "${NO_PROXY:-}" ] && set -- "$@" --build-arg "NO_PROXY=$NO_PROXY"
  [ -n "${http_proxy:-}" ] && set -- "$@" --build-arg "http_proxy=$http_proxy"
  [ -n "${https_proxy:-}" ] && set -- "$@" --build-arg "https_proxy=$https_proxy"
  [ -n "${no_proxy:-}" ] && set -- "$@" --build-arg "no_proxy=$no_proxy"
  set -- "$@" "$SCRIPT_DIR"
  docker "$@"
fi

ANDROID_API="${ANDROID_API:-30}"
ANDROID_ARCH="${ANDROID_ARCH:-arm64}"
OUTPUT_DIR="${OUTPUT_DIR:-$SOURCE_DIR/android-build-${ANDROID_ARCH}-api${ANDROID_API}}"
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
OUTPUT_NAME="$(basename "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"
OUTPUT_PARENT=$(CDPATH='' cd -- "$OUTPUT_PARENT" && pwd)
OUTPUT_DIR="$OUTPUT_PARENT/$OUTPUT_NAME"

set -- run --rm
if [ -t 0 ] && [ -t 1 ]; then
  set -- "$@" -t
fi
if [ -n "${CPUSET:-}" ]; then
  set -- "$@" --cpuset-cpus "$CPUSET"
fi

if [ "$SOURCE_MODE" = mount ]; then
  set -- "$@" \
    --env SOURCE_MODE=mount
  set -- "$@" --env SOURCE_DIR="$SOURCE_DIR" \
    --env OUTPUT_DIR="/output/$OUTPUT_NAME" \
    --env ANDROID_API="$ANDROID_API" \
    --env ANDROID_ARCH="$ANDROID_ARCH" \
    --env JOBS="$JOBS" \
    --volume "$SOURCE_DIR:$SOURCE_DIR" \
    --volume "$OUTPUT_PARENT:/output" \
    --workdir "$SOURCE_DIR"
elif [ "$SOURCE_MODE" = download ]; then
  set -- "$@" \
    --env SOURCE_MODE=download
  set -- "$@" --env OUTPUT_DIR="/output/$OUTPUT_NAME" \
    --env ANDROID_API="$ANDROID_API" \
    --env ANDROID_ARCH="$ANDROID_ARCH" \
    --env JOBS="$JOBS" \
    --volume "$OUTPUT_PARENT:/output"
else
  die 'SOURCE_MODE must be mount or download'
fi

[ -n "${INTL:-}" ] && set -- "$@" --env "INTL=$INTL"
[ -n "${REPOSITORY:-}" ] && set -- "$@" --env "REPOSITORY=$REPOSITORY"
[ -n "${REF:-}" ] && set -- "$@" --env "REF=$REF"
[ -n "${KEEP_BUILD:-}" ] && set -- "$@" --env "KEEP_BUILD=$KEEP_BUILD"
[ -n "${CC_host:-}" ] && set -- "$@" --env "CC_host=$CC_host"
[ -n "${CXX_host:-}" ] && set -- "$@" --env "CXX_host=$CXX_host"

[ -n "${HTTP_PROXY:-}" ] && set -- "$@" --env "HTTP_PROXY=$HTTP_PROXY"
[ -n "${HTTPS_PROXY:-}" ] && set -- "$@" --env "HTTPS_PROXY=$HTTPS_PROXY"
[ -n "${NO_PROXY:-}" ] && set -- "$@" --env "NO_PROXY=$NO_PROXY"
[ -n "${http_proxy:-}" ] && set -- "$@" --env "http_proxy=$http_proxy"
[ -n "${https_proxy:-}" ] && set -- "$@" --env "https_proxy=$https_proxy"
[ -n "${no_proxy:-}" ] && set -- "$@" --env "no_proxy=$no_proxy"

set -- "$@" "$IMAGE"
exec docker "$@"
