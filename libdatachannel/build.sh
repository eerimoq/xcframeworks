#!/bin/bash

# Copyright (c) shogo4405 and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD 3-Clause License found in the
# LICENSE file in the root directory of this source tree.

set -euo pipefail

function clone_and_patch() {
    if [ ! -d libdatachannel ] ; then
      git clone --depth 1 --branch v0.27.0 --recurse-submodules https://github.com/eerimoq/libdatachannel
      pushd libdatachannel/deps/libsrtp
      git apply ../../../libsrtp.patch
      popd
    fi
    if [ ! -d OpenSSL ] ; then
      git clone --depth 1 --branch 3.3.3001 https://github.com/krzyzanowskim/OpenSSL
    fi
    if [ ! -d ios-cmake ] ; then
      git clone --depth 1 --branch 4.5.0 https://github.com/leetal/ios-cmake
    fi
}

function build_platform() {
    export OPENSSL_ROOT_DIR=$(pwd)/OpenSSL/$1
    BUILD=build/$1
    cmake libdatachannel \
      -B $BUILD \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake \
      -D PLATFORM=$2 \
      -D BUILD_SHARED_LIBS=OFF \
      -D BUILD_SHARED_DEPS_LIBS=OFF \
      -D NO_WEBSOCKET=YES \
      -D NO_EXAMPLES=YES \
      -D NO_TESTS=YES
    make -C $BUILD -j $(nproc)
    libtool -static -o $BUILD/libdatachannel.a \
      $BUILD/libdatachannel.a \
      $BUILD/deps/libsrtp/libsrtp2.a \
      $BUILD/deps/usrsctp/usrsctplib/libusrsctp.a \
      $BUILD/deps/libjuice/libjuice.a \
      $OPENSSL_ROOT_DIR/lib/*.a
}

function build() {
    rm -rf build
    build_platform iphoneos OS64
    build_platform iphonesimulator SIMULATORARM64
    build_platform macosx_catalyst MAC_CATALYST_ARM64
}

function create_xcframework() {
    rm -rf include
    mkdir -p include/libdatachannel
    cp -r libdatachannel/include/rtc include/libdatachannel
    cp module.modulemap include/libdatachannel/module.modulemap

    rm -rf libdatachannel.xcframework
    xcodebuild -create-xcframework  \
        -library ./build/iphoneos/libdatachannel.a -headers include  \
        -library ./build/iphonesimulator/libdatachannel.a -headers include  \
        -library ./build/macosx_catalyst/libdatachannel.a -headers include  \
        -output libdatachannel.xcframework

    zip -r libdatachannel.xcframework.zip libdatachannel.xcframework
    swift package compute-checksum libdatachannel.xcframework.zip
}

clone_and_patch
build
create_xcframework
