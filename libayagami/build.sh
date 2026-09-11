#!/bin/bash

set -euo pipefail

TARGETS="aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-ios-macabi x86_64-apple-ios-macabi"

function build() {
    rustup target add $TARGETS
    for target in $TARGETS ; do
        IPHONEOS_DEPLOYMENT_TARGET=16.4 cargo build --release --target $target
    done
    rm -rf build
    mkdir -p build/iphoneos build/iphonesimulator build/macosx_catalyst
    cp target/aarch64-apple-ios/release/libayagami_ffi.a build/iphoneos/libayagami.a
    cp target/aarch64-apple-ios-sim/release/libayagami_ffi.a build/iphonesimulator/libayagami.a
    lipo -create \
        target/aarch64-apple-ios-macabi/release/libayagami_ffi.a \
        target/x86_64-apple-ios-macabi/release/libayagami_ffi.a \
        -output build/macosx_catalyst/libayagami.a
}

function create_xcframework() {
    rm -rf include
    mkdir -p include/libayagami
    cp ayagami.h module.modulemap include/libayagami
    rm -rf libayagami.xcframework
    xcodebuild -create-xcframework \
        -library build/iphoneos/libayagami.a -headers include \
        -library build/iphonesimulator/libayagami.a -headers include \
        -library build/macosx_catalyst/libayagami.a -headers include \
        -output libayagami.xcframework
    rm -f libayagami.xcframework.zip
    zip -r libayagami.xcframework.zip libayagami.xcframework
    if [ -d ../../AyagamiSwift ] ; then
        rm -rf ../../AyagamiSwift/libayagami.xcframework
        cp -R libayagami.xcframework ../../AyagamiSwift/
    fi
}

if [ "${1:-}" != "package" ] ; then
    build
fi
create_xcframework
