#!/bin/sh
set -e

# Build llvm-mingw for UCRT i686/x86_64 only, without lldb/lldb-mi/clang-tools-extra.
# Installs into ./install/llvm-mingw relative to the repo root.

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
DEST="$REPO_ROOT/install/llvm-mingw"

TOOLCHAIN_ARCHS="i686 x86_64" \
"$REPO_ROOT/build-all.sh" "$DEST" \
  --with-default-msvcrt=ucrt \
  --disable-lldb \
  --disable-lldb-mi \
  --disable-clang-tools-extra
