#!/usr/bin/env bash
# 在 macOS 上编译 arm64 iOS dylib
# 用法: ./build.sh
set -euo pipefail

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "iOS SDK: $SDK"

clang -dynamiclib \
      -arch arm64 \
      -miphoneos-version-min=16.0 \
      -isysroot "$SDK" \
      -fobjc-arc \
      -O2 \
      -framework Foundation \
      -framework UIKit \
      -o DTPUnlock.dylib \
      DTPUnlock.m

# 未签名 dylib 在注入前先做一次 ad-hoc 签名，避免加载失败
codesign -f -s - DTPUnlock.dylib
echo "built: $(pwd)/DTPUnlock.dylib"
lipo -info DTPUnlock.dylib
