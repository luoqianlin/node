#!/usr/bin/env bash
# Run the reproducible Android builder through Docker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SOURCE_DIR="${SOURCE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
readonly SOURCE_DIR
IMAGE="${IMAGE:-node-android-builder:r29}"
SOURCE_MODE="${SOURCE_MODE:-mount}"
readonly SOURCE_MODE
HOST_CPUS="$(nproc)"
readonly HOST_CPUS
JOBS="${JOBS:-$(( HOST_CPUS > 2 ? HOST_CPUS - 2 : 1 ))}"
readonly JOBS

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || die 'missing required command: docker'
command -v nproc >/dev/null 2>&1 || die 'missing required command: nproc'
[[ -d "$SOURCE_DIR" ]] || die "missing source directory: $SOURCE_DIR"

if [[ "${BUILD_IMAGE:-1}" == 1 ]]; then
  build_args=()
  for variable in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
    if [[ -n "${!variable:-}" ]]; then
      build_args+=(--build-arg "$variable=${!variable}")
    fi
  done
  docker build "${build_args[@]}" --tag "$IMAGE" --file "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
fi

ANDROID_API="${ANDROID_API:-30}"
ANDROID_ARCH="${ANDROID_ARCH:-arm64}"
OUTPUT_DIR="${OUTPUT_DIR:-$SOURCE_DIR/android-build-${ANDROID_ARCH}-api${ANDROID_API}}"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
OUTPUT_NAME="$(basename "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"

docker_args=(run --rm)
if [[ -t 0 && -t 1 ]]; then
  docker_args+=(-t)
fi
if [[ -n "${CPUSET:-}" ]]; then
  docker_args+=(--cpuset-cpus "$CPUSET")
fi

if [[ "$SOURCE_MODE" == mount ]]; then
  docker_args+=(
    --env SOURCE_MODE=mount
    --env SOURCE_DIR="$SOURCE_DIR"
    --env OUTPUT_DIR="/output/$OUTPUT_NAME"
    --env ANDROID_API="$ANDROID_API"
    --env ANDROID_ARCH="$ANDROID_ARCH"
    --env JOBS="$JOBS"
    --volume "$SOURCE_DIR:$SOURCE_DIR"
    --volume "$OUTPUT_PARENT:/output"
    --workdir "$SOURCE_DIR"
  )
elif [[ "$SOURCE_MODE" == download ]]; then
  docker_args+=(
    --env SOURCE_MODE=download
    --env OUTPUT_DIR="/output/$OUTPUT_NAME"
    --env ANDROID_API="$ANDROID_API"
    --env ANDROID_ARCH="$ANDROID_ARCH"
    --env JOBS="$JOBS"
    --volume "$OUTPUT_PARENT:/output"
  )
else
  die 'SOURCE_MODE must be mount or download'
fi

for variable in INTL REPOSITORY REF KEEP_BUILD CC_host CXX_host; do
  if [[ -n "${!variable:-}" ]]; then
    docker_args+=(--env "$variable=${!variable}")
  fi
done

for variable in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
  if [[ -n "${!variable:-}" ]]; then
    docker_args+=(--env "$variable=${!variable}")
  fi
done

docker_args+=("$IMAGE")
exec docker "${docker_args[@]}"
