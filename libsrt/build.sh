#!/bin/bash

set -euo pipefail

function clone_and_patch() {
    if [ ! -d OpenSSL ] ; then
        git clone --depth 1 --branch 3.3.3001 https://github.com/krzyzanowskim/OpenSSL
    fi
    if [ ! -d srt ] ; then
        git clone --depth 1 --branch moblin-0.1.0 https://github.com/eerimoq/srt
    fi
    if [ ! -d ios-cmake ] ; then
      git clone --depth 1 --branch 4.5.0 https://github.com/leetal/ios-cmake
    fi
}

function build_platform() {
    export OPENSSL_ROOT_DIR=$(pwd)/OpenSSL/$1
    BUILD=build/$1
    cmake srt \
      -B $BUILD \
      -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -D ENABLE_APPS=OFF \
      -D ENABLE_SHARED=OFF \
      -D ENABLE_MAXREXMITBW=ON \
      -D ENABLE_LOGGING=OFF \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake \
      -D PLATFORM=$2
    make -C $BUILD -j $(nproc)
}

function build() {
    rm -rf build
    build_platform iphoneos OS64
    build_platform iphonesimulator SIMULATORARM64
    build_platform macosx_catalyst MAC_CATALYST_ARM64
}

function create_xcframework() {
    rm -rf include
    mkdir -p include
    cp srt/srtcore/{logging_api,platform_sys,srt}.h include
    cp build/iphoneos/version.h include/version.h
    cp module.modulemap include/module.modulemap
    echo "#define ENABLE_MAXREXMITBW 1" >> include/platform_sys.h
    rm -rf libsrt.xcframework
    xcodebuild -create-xcframework \
        -library build/iphoneos/libsrt.a \
        -headers include \
        -library build/iphonesimulator/libsrt.a \
        -headers include \
        -library build/macosx_catalyst/libsrt.a \
        -headers include \
        -output libsrt.xcframework
    zip -r libsrt.xcframework.zip libsrt.xcframework
    swift package compute-checksum libsrt.xcframework.zip
}

clone_and_patch
build
create_xcframework
