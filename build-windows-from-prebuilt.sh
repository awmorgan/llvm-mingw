#!/usr/bin/env bash
# Build Windows-hosted LLVM tools using a prebuilt Linux cross compiler.
# Usage:
#   ./build-windows-from-prebuilt.sh [extra build-cross-tools.sh options...]
#
# Environment overrides (defaults):
#   LLVM_SOURCE_DIR  Local LLVM monorepo ($HOME/llvm-project).
#   WINDOWS_ARCH     Architecture running the Windows tools (x86_64).
#                    Supported: i686, x86_64, aarch64, armv7.
#   WINDOWS_PREFIX   Output directory (<script-dir>/install/llvm-mingw-windows-$WINDOWS_ARCH).
#   CORES            Parallel build jobs (8).
#
# Examples:
#   CORES=4 ./build-windows-from-prebuilt.sh
#   ./build-windows-from-prebuilt.sh --disable-lldb --disable-lldb-mi
#   WINDOWS_ARCH=aarch64 ./build-windows-from-prebuilt.sh
#
# Uses the local LLVM revision without fetching or checking out LLVM sources.
# Creates build files inside that checkout and may download other components.
# Copies headers and runtime libraries from the pinned prebuilt release.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
ROOT=$PWD
LLVM_SOURCE_DIR=${LLVM_SOURCE_DIR:-$HOME/llvm-project}
WINDOWS_ARCH=${WINDOWS_ARCH:-x86_64}
WINDOWS_PREFIX=${WINDOWS_PREFIX:-$ROOT/install/llvm-mingw-windows-$WINDOWS_ARCH}
CORES=${CORES:-8}

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    echo 'This script requires x86_64 Linux (including WSL).' >&2
    exit 1
fi
case "$WINDOWS_ARCH" in
    i686|x86_64|aarch64|armv7) ;;
    *) echo "Unsupported Windows host architecture: $WINDOWS_ARCH" >&2; exit 1 ;;
esac
if [[ ! $CORES =~ ^[1-9][0-9]*$ ]]; then
    echo 'CORES must be a positive integer.' >&2
    exit 1
fi

missing=0
for dep in curl sha256sum tar xz git cmake ninja make gcc g++ python3 \
           autoconf automake libtoolize pkg-config gettext autopoint bzip2 unzip file; do
    if ! command -v "$dep" >/dev/null; then
        echo "Missing dependency: $dep" >&2
        missing=1
    fi
done
if (( missing )); then
    cat >&2 <<'EOF'
On Ubuntu, install dependencies with:
  sudo apt-get update
  sudo apt-get install -y build-essential cmake ninja-build git curl ca-certificates xz-utils bzip2 unzip file python3 autoconf automake libtool libltdl-dev pkg-config gettext autopoint
EOF
    exit 1
fi

if [[ ! -f "$LLVM_SOURCE_DIR/llvm/CMakeLists.txt" || ! -d "$LLVM_SOURCE_DIR/clang" ]]; then
    echo "LLVM_SOURCE_DIR must point to an LLVM monorepo: $LLVM_SOURCE_DIR" >&2
    exit 1
fi
LLVM_SOURCE_DIR=$(cd -- "$LLVM_SOURCE_DIR" && pwd -P)
if [[ -e llvm-project || -L llvm-project ]]; then
    if [[ ! -d llvm-project ]] || [[ $(cd llvm-project && pwd -P) != "$LLVM_SOURCE_DIR" ]]; then
        echo "Existing $ROOT/llvm-project does not resolve to $LLVM_SOURCE_DIR; leaving it untouched." >&2
        exit 1
    fi
else
    ln -s -- "$LLVM_SOURCE_DIR" llvm-project
fi

# Never let inherited checkout settings change the local LLVM revision.
unset SYNC CHECKOUT CHECKOUT_ONLY
export CORES

PACKAGE=llvm-mingw-20261020-ucrt-ubuntu-22.04-x86_64
ARCHIVE="$ROOT/prebuilt/$PACKAGE.tar.xz"
NATIVE="$ROOT/prebuilt/$PACKAGE"
SHA256=55064b60b991a1e1e8090b8c2f84e82b22cfe5903d12c159d65064cf5e8ae335
mkdir -p "$ROOT/prebuilt"
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fL --retry 3 \
        -o "$ARCHIVE.part" \
        "https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/$PACKAGE.tar.xz"
    printf '%s  %s\n' "$SHA256" "$ARCHIVE.part" | sha256sum -c -
    mv -- "$ARCHIVE.part" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | sha256sum -c -
if [[ ! -f "$NATIVE/.custom-build-extracted" ]]; then
    tar -xJf "$ARCHIVE" -C "$ROOT/prebuilt"
    touch "$NATIVE/.custom-build-extracted"
fi
"$NATIVE/bin/clang" --version

# These scripts do not consistently support whitespace in paths.
mkdir -p -- "$WINDOWS_PREFIX"
WINDOWS_PREFIX=$(cd -- "$WINDOWS_PREFIX" && pwd -P)
for path in "$ROOT" "$LLVM_SOURCE_DIR" "$WINDOWS_PREFIX"; do
    if [[ $path =~ [[:space:]] ]]; then
        echo "Build scripts require paths without whitespace: $path" >&2
        exit 1
    fi
done

printf 'LLVM source: %s\nWindows output: %s\nParallel jobs: %s\n' \
    "$LLVM_SOURCE_DIR" "$WINDOWS_PREFIX" "$CORES"
echo 'Windows tools will be rebuilt; headers and runtime libraries come from the prebuilt release.'
echo 'Build files will be created inside your local LLVM checkout; other component sources may be downloaded.'
./build-cross-tools.sh "$NATIVE" "$WINDOWS_PREFIX" "$WINDOWS_ARCH" \
    --no-llvm-tool-reuse "$@"

printf '\nFinished. Copy this entire directory to Windows:\n%s\n' "$WINDOWS_PREFIX"
