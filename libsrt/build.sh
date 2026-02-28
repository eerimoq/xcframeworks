#!/bin/bash

set -euo pipefail

function clone_and_patch() {
    if [ ! -d OpenSSL ] ; then
        git clone --depth 1 --branch 3.3.3001 https://github.com/krzyzanowskim/OpenSSL
    fi
    if [ ! -d srt ] ; then
        git clone --depth 1 --branch moblin-0.1.0 https://github.com/eerimoq/srt
    fi
}

function build_srt() {
    export OPENSSL_ROOT_DIR=$(pwd)/OpenSSL/$1
    IOS_OPENSSL=$(pwd)/OpenSSL/$1
    mkdir -p build/$2/$3
    pushd build/$2/$3
    CC=clang CXX=clang++ ../../../srt/configure \
        --cmake-prefix-path=$IOS_OPENSSL \
        --cmake-policy-version-minimum=3.5 \
        --cmake-make-program=make \
        --ios-disable-bitcode=1 \
        --ios-platform=$2 \
        --ios-arch=$3 \
        --cmake-toolchain-file=scripts/iOS.cmake \
        --USE_OPENSSL_PC=off \
        --enable-maxrexmitbw=ON \
        --enable-apps=OFF \
        --enable-logging=OFF \
        --enable-shared=OFF
    make -j $(sysctl -n hw.ncpu)
    popd

    rm -f build/$2/libsrt-lipo.a
    lipo \
        -create build/$2/arm64/libsrt.a \
        -output build/$2/libsrt-lipo.a
    libtool \
        -static \
        -o build/$2/libsrt.a \
        build/$2/libsrt-lipo.a \
        OpenSSL/$1/lib/libcrypto.a \
        OpenSSL/$1/lib/libssl.a
}

function build() {
    rm -rf build

    export IPHONEOS_DEPLOYMENT_TARGET=16.4
    build_srt iphonesimulator SIMULATOR64 arm64
    build_srt iphoneos OS arm64

    MACOS_OPENSSL=$(pwd)/OpenSSL/macosx
    mkdir -p build/macos_catalyst
    pushd build/macos_catalyst
    ../../srt/configure \
        --cmake-osx-architectures=arm64 \
        --cmake-policy-version-minimum=3.5 \
        --cmake-c-flags="-target arm64-apple-ios16.0-macabi" \
        --cmake-cxx-flags="-target arm64-apple-ios16.0-macabi" \
        --OPENSSL_INCLUDE_DIR=$MACOS_OPENSSL/include \
        --OPENSSL_LIBRARIES=$MACOS_OPENSSL/lib/libcrypto.a
    make -j $(sysctl -n hw.ncpu)
    popd

    rm -f build/macos_catalyst/libsrt-lipo.a
    cp build/macos_catalyst/libsrt.a build/macos_catalyst/libsrt-lipo.a
    libtool \
        -static \
        -o build/macos_catalyst/libsrt.a \
        build/macos_catalyst/libsrt-lipo.a \
        OpenSSL/macosx/lib/libcrypto.a \
        OpenSSL/macosx/lib/libssl.a
}

function create_xcframework() {
    rm -rf Includes
    mkdir -p Includes
    cp srt/srtcore/{logging_api,platform_sys,srt}.h Includes
    cp build/OS/arm64/version.h Includes/version.h
    cat <<EOF > Includes/module.modulemap
module libsrt {
    header "srt.h"
    export *
}
EOF
    echo "#define ENABLE_MAXREXMITBW 1" >> Includes/platform_sys.h

    rm -rf libsrt.xcframework
    xcodebuild -create-xcframework \
        -library build/SIMULATOR64/libsrt.a -headers Includes \
        -library build/OS/libsrt.a -headers Includes \
        -library build/macos_catalyst/libsrt.a -headers Includes \
        -output libsrt.xcframework

    zip -r libsrt.xcframework.zip libsrt.xcframework
    swift package compute-checksum libsrt.xcframework.zip
}

clone_and_patch
build
create_xcframework
