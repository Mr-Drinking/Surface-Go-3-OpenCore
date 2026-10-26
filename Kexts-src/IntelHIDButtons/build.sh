#!/bin/bash
# Build IntelHIDButtons.kext (x86_64) with the Xcode Command Line Tools and acidanthera's
# MacKernelSDK; Xcode itself is not needed. Output: build/IntelHIDButtons.kext
# Usage: ./build.sh            (set MACKERNELSDK to use an existing MacKernelSDK checkout)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=IntelHIDButtons
SDK="${MACKERNELSDK:-$HERE/MacKernelSDK}"
OUT="$HERE/build"

[ -d "$SDK/Headers" ] || git clone --depth 1 https://github.com/acidanthera/MacKernelSDK.git "$SDK"

RT="$(clang -print-resource-dir)"
CC_KEXT="$RT/lib/darwin/libclang_rt.cc_kext.a"
[ -f "$CC_KEXT" ] || { echo "Error: $CC_KEXT not found (install the Xcode Command Line Tools)" >&2; exit 1; }

COMMON=(
    -arch x86_64 -mmacosx-version-min=10.13 -Os -Wall -Wno-unused-parameter
    -mkernel -nostdinc -fno-builtin -fno-common
    -DKERNEL -DDRIVER_PRIVATE -DAPPLE -DNeXT
    -isystem "$SDK/Headers" -isystem "$RT/include"
)

rm -rf "$OUT"
mkdir -p "$OUT/$NAME.kext/Contents/MacOS"

clang -x c -std=gnu11 "${COMMON[@]}" -c "$HERE/${NAME}_info.c" -o "$OUT/${NAME}_info.o"
clang++ -x c++ -std=gnu++17 -fapple-kext -fno-rtti -fno-exceptions -nostdinc++ "${COMMON[@]}" \
    -c "$HERE/$NAME.cpp" -o "$OUT/$NAME.o"
clang++ -arch x86_64 -mmacosx-version-min=10.13 -nostdlib -Xlinker -kext \
    "$OUT/${NAME}_info.o" "$OUT/$NAME.o" -L"$SDK/Library/x86_64" -lkmod "$CC_KEXT" \
    -o "$OUT/$NAME.kext/Contents/MacOS/$NAME"

cp "$HERE/Info.plist" "$OUT/$NAME.kext/Contents/Info.plist"
plutil -lint -s "$OUT/$NAME.kext/Contents/Info.plist"
echo "Built $OUT/$NAME.kext"
