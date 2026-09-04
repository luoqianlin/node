FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG NDK_VERSION=r29
ARG NDK_SHA256=4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf
ARG NDK_URL=https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip

ENV ANDROID_NDK_ROOT=/opt/android-ndk-${NDK_VERSION}
ENV PATH=${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin:${PATH}
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
       binutils ca-certificates curl file g++-13 gcc-13 git make perl \
       python3 tar unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt \
    && curl --fail --location --retry 3 --output /tmp/android-ndk.zip "${NDK_URL}" \
    && printf '%s  %s\n' "${NDK_SHA256}" /tmp/android-ndk.zip | sha256sum --check --status \
    && unzip -q /tmp/android-ndk.zip -d /opt \
    && test -x "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" \
    && rm -f /tmp/android-ndk.zip

COPY docker-entrypoint.sh /usr/local/bin/node-android-build
RUN chmod 0755 /usr/local/bin/node-android-build

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/node-android-build"]
