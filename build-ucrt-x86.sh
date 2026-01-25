#!/bin/bash
set -e

# Setup rolling log files
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
MAX_LOGS=10

# Rotate existing logs
for i in $(seq $((MAX_LOGS-1)) -1 1); do
    [ -f "$LOG_DIR/build-ucrt-x86.$i.log" ] && mv "$LOG_DIR/build-ucrt-x86.$i.log" "$LOG_DIR/build-ucrt-x86.$((i+1)).log"
done
[ -f "$LOG_DIR/build-ucrt-x86.log" ] && mv "$LOG_DIR/build-ucrt-x86.log" "$LOG_DIR/build-ucrt-x86.1.log"

# Redirect all output to both console and log file
exec > >(tee "$LOG_DIR/build-ucrt-x86.log") 2>&1

NATIVE_PREFIX="./install/llvm-mingw-native"
CROSS_PREFIX="./install/llvm-mingw-windows"
NATIVE_ARCHS="i686 x86_64"

LLVM_REPOSITORY=https://github.com/swiftlang/llvm-project.git \
LLVM_VERSION=stable/21.x \
CORES=16 \
TOOLCHAIN_ARCHS="$NATIVE_ARCHS" \
"./build-all.sh" "$NATIVE_PREFIX" \
  --with-default-msvcrt=ucrt \
  --host-clang=clang \
  --with-clang \
  --thinlto \

# Build a Windows-hosted toolchain (binaries with .exe and unprefixed tools)
TOOLCHAIN_ARCHS="$NATIVE_ARCHS" \
"./build-cross-tools.sh" "$NATIVE_PREFIX" "$CROSS_PREFIX" x86_64 \
  --with-clang \
  --thinlto 
