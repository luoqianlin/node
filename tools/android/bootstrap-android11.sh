#!/bin/sh
# Download the Android branch and build it without requiring a pre-existing clone.
set -eu

REPOSITORY="${REPOSITORY:-https://github.com/luoqianlin/node.git}"
REF="${REF:-android11-v24.19.0}"
WORK_DIR="${WORK_DIR:-$PWD/node-android11-build}"

command -v git >/dev/null 2>&1 || { echo 'error: missing git' >&2; exit 1; }
if [ -e "$WORK_DIR" ]; then
  echo "error: work directory already exists: $WORK_DIR" >&2
  exit 1
fi

git clone --branch "$REF" --depth 1 "$REPOSITORY" "$WORK_DIR"
exec "$WORK_DIR/tools/android/build-android11.sh"
