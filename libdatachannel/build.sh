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

function build() {
    rm -rf build

    export OPENSSL_ROOT_DIR=$(pwd)/OpenSSL/iphoneos
    BUILD=build/iphoneos
    cmake libdatachannel \
      -B $BUILD \
      -G Xcode \
      -D CMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake \
      -D PLATFORM=OS64 \
      -D BUILD_SHARED_LIBS=OFF \
      -D BUILD_SHARED_DEPS_LIBS=OFF \
      -D NO_WEBSOCKET=YES \
      -D NO_EXAMPLES=YES \
      -D NO_TESTS=YES
    cmake --build $BUILD --config Release
    libtool \
      -static \
      -o $BUILD/libdatachannel.a \
      $BUILD/Release-iphoneos/libdatachannel.a \
      $BUILD/deps/libsrtp/Release-iphoneos/libsrtp2.a \
      $BUILD/deps/usrsctp/usrsctplib/Release-iphoneos/libusrsctp.a \
      $BUILD/deps/libjuice/Release-iphoneos/libjuice.a \
      $OPENSSL_ROOT_DIR/lib/*.a

    export OPENSSL_ROOT_DIR=$(pwd)/OpenSSL/iphonesimulator
    BUILD=build/iphonesimulator
    cmake libdatachannel \
      -B $BUILD \
      -G Xcode \
      -D CMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake \
      -D PLATFORM=SIMULATORARM64 \
      -D BUILD_SHARED_LIBS=OFF \
      -D BUILD_SHARED_DEPS_LIBS=OFF \
      -D NO_WEBSOCKET=YES \
      -D NO_EXAMPLES=YES \
      -D NO_TESTS=YES
    cmake --build $BUILD --config Release
    libtool \
      -static \
      -o $BUILD/libdatachannel.a \
      $BUILD/Release-iphonesimulator/libdatachannel.a \
      $BUILD/deps/libsrtp/Release-iphonesimulator/libsrtp2.a \
      $BUILD/deps/usrsctp/usrsctplib/Release-iphonesimulator/libusrsctp.a \
      $BUILD/deps/libjuice/Release-iphonesimulator/libjuice.a \
      $OPENSSL_ROOT_DIR/lib/*.a

    export OPENSSL_ROOT_DIR=$(pwd)/OpenSSL/macosx_catalyst
    BUILD=build/macosx_catalyst
    cmake libdatachannel \
      -B $BUILD \
      -G Xcode \
      -D CMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake \
      -D PLATFORM=MAC_CATALYST_ARM64 \
      -D BUILD_SHARED_LIBS=OFF \
      -D BUILD_SHARED_DEPS_LIBS=OFF \
      -D NO_WEBSOCKET=YES \
      -D NO_EXAMPLES=YES \
      -D NO_TESTS=YES
    cmake --build $BUILD --config Release
    libtool \
      -static \
      -o $BUILD/libdatachannel.a \
      $BUILD/Release/libdatachannel.a \
      $BUILD/deps/libsrtp/Release/libsrtp2.a \
      $BUILD/deps/usrsctp/usrsctplib/Release/libusrsctp.a \
      $BUILD/deps/libjuice/Release/libjuice.a \
      $OPENSSL_ROOT_DIR/lib/*.a
}

function create_xcframework() {
    rm -rf include
    mkdir -p include/libdatachannel
    cp -r libdatachannel/include/rtc include/libdatachannel
    cp module.modulemap include/libdatachannel/module.modulemap

    rm -rf libdatachannel.xcframework
    xcodebuild \
        -create-xcframework \
        -library build/iphoneos/libdatachannel.a -headers include \
        -library build/iphonesimulator/libdatachannel.a -headers include \
        -library build/macosx_catalyst/libdatachannel.a -headers include \
        -output libdatachannel.xcframework

    zip -r libdatachannel.xcframework.zip libdatachannel.xcframework
    swift package compute-checksum libdatachannel.xcframework.zip
}

clone_and_patch
build
create_xcframework
