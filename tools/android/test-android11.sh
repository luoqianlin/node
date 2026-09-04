#!/usr/bin/env bash
# Run focused Android smoke tests using an already-connected adb device.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SOURCE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SOURCE_DIR
: "${ANDROID_SERIAL:?error: set ANDROID_SERIAL to the target adb serial}"
SERIAL="$ANDROID_SERIAL"
DIST_DIR="${DIST_DIR:-$SOURCE_DIR/android-build-arm64-api30}"
REMOTE_DIR="${REMOTE_DIR:-/data/local/tmp/node-android11-smoke}"

command -v adb >/dev/null 2>&1 || { echo 'error: missing adb' >&2; exit 1; }
[[ -x "$DIST_DIR/bin/node" ]] || { echo "error: missing $DIST_DIR/bin/node" >&2; exit 1; }
[[ -f "$DIST_DIR/lib/libc++_shared.so" ]] || { echo "error: missing $DIST_DIR/lib/libc++_shared.so" >&2; exit 1; }

adb -s "$SERIAL" wait-for-device
adb -s "$SERIAL" shell "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR/lib'"
adb -s "$SERIAL" push "$DIST_DIR/bin/node" "$REMOTE_DIR/node" >/dev/null
adb -s "$SERIAL" push "$DIST_DIR/lib/libc++_shared.so" "$REMOTE_DIR/lib/libc++_shared.so" >/dev/null
adb -s "$SERIAL" shell "chmod 0755 '$REMOTE_DIR/node' && LD_LIBRARY_PATH='$REMOTE_DIR/lib' '$REMOTE_DIR/node' -e '\
const assert = require(\"assert\"); \
const zlib = require(\"zlib\"); \
const fs = require(\"fs\"); \
const crypto = require(\"crypto\"); \
assert.strictEqual(process.platform, \"android\"); \
assert.strictEqual(process.arch, \"arm64\"); \
assert.strictEqual(zlib.gunzipSync(zlib.gzipSync(\"android11\")).toString(), \"android11\"); \
assert.strictEqual(crypto.createHash(\"sha256\").update(\"node\").digest(\"hex\").length, 64); \
fs.writeFileSync(\"$REMOTE_DIR/smoke.txt\", \"ok\"); \
assert.strictEqual(fs.readFileSync(\"$REMOTE_DIR/smoke.txt\", \"utf8\"), \"ok\"); \
assert.ok(new Intl.DateTimeFormat(\"zh-CN\").format(new Date())); \
console.log(JSON.stringify({node: process.version, napi: process.versions.napi, icu: process.versions.icu}));'"
