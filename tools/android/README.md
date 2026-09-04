# Android Docker builder

This builder pins the host build tools and Android NDK used by the Android 11
port. The image uses GCC 13/G++ 13 for host tools and the Android NDK Clang
toolchain for the target. The default output is an Android API 30 arm64
distribution with `small-icu` and a matching `libc++_shared.so`.

Build the image and a mounted checkout:

```bash
JOBS=110 CPUSET=0-109 \
  tools/android/build-android11-docker.sh
```

The image can also download a shallow checkout from GitHub:

```bash
SOURCE_MODE=download \
REPOSITORY=https://github.com/luoqianlin/node.git \
REF=android11-v24.19.0 \
tools/android/build-android11-docker.sh
```

Set `BUILD_IMAGE=0` to reuse an existing image. `ANDROID_API`, `ANDROID_ARCH`,
`INTL`, `JOBS`, `CPUSET`, and `OUTPUT_DIR` can be overridden. The output
directory contains `bin/node`, `lib/libc++_shared.so`, `BUILD-INFO`, headers,
share files, and a SHA-256-verified `tar.xz` archive.

The source checkout and output directory are mounted into the container. No
host-specific path, Android device serial, system image path, or GitLab URL is
embedded in the image.
