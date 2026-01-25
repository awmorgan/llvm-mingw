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

# Shared build settings for both stages
export TOOLCHAIN_ARCHS="i686 x86_64"
export LLVM_REPOSITORY=https://github.com/swiftlang/llvm-project.git
export LLVM_VERSION=stable/21.x
export CORES=16
# We set _WIN32_WINNT to 0x0A00 (Win10)
# We set NTDDI_VERSION to 0x0A000006 (Win10 1809) to satisfy the >= 0x0A000002 check in minwinbase.h
export CFLAGS="$CFLAGS -D_WIN32_WINNT=0x0A00 -DNTDDI_VERSION=0x0A000006"
export CXXFLAGS="$CXXFLAGS -D_WIN32_WINNT=0x0A00 -DNTDDI_VERSION=0x0A000006"

# Stage 1: Linux-hosted toolchain that targets Windows
NATIVE_PREFIX="$(pwd)/install/llvm-mingw-native"
DEFAULT_MSVCRT=ucrt
"./build-all.sh" "$NATIVE_PREFIX" \
  --with-default-msvcrt=$DEFAULT_MSVCRT \
  --host-clang=clang \
  --with-clang \
  --thinlto

# Stage 2: Windows-hosted toolchain (.exe) bootstrapped from stage 1
CROSS_ARCH="x86_64"
CROSS_PREFIX="$(pwd)/install/llvm-mingw-windows"
"./build-cross-tools.sh" "$NATIVE_PREFIX" "$CROSS_PREFIX" "$CROSS_ARCH" \
  --disable-lldb \
  --with-clang \
  --thinlto