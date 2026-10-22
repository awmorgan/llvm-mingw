#!/usr/bin/env bash
# Build Windows-hosted LLVM tools using a prebuilt Linux cross compiler.
# Usage:
#   ./build-windows-from-prebuilt.sh [extra build-cross-tools.sh options...]
#
# Customize the settings in the block below. To use another release, update
# PREBUILT_RELEASE and PREBUILT_SHA256 together. Get the SHA256 from that
# release's matching Linux archive asset.
#
# Examples:
#   ./build-windows-from-prebuilt.sh --disable-lldb --disable-lldb-mi
#
# Uses the local LLVM revision without fetching or checking out LLVM sources.
# Creates build files inside that checkout and may download other components.
# Copies headers and runtime libraries from the pinned prebuilt release.
# Creates a Windows-hosted release ZIP in the repository root when the build completes.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
ROOT=$PWD

# Configuration: change these values to customize the inputs, output package,
# or build. PREBUILT_RELEASE and PREBUILT_SHA256 must refer to the same release.
PREBUILT_RELEASE=20261020
PREBUILT_SHA256=55064b60b991a1e1e8090b8c2f84e82b22cfe5903d12c159d65064cf5e8ae335
PREBUILT_CRT=ucrt
PREBUILT_PLATFORM=ubuntu-22.04
PREBUILT_ARCH=x86_64 # Architecture of Linux machine running the prebuilt compiler.

LLVM_SOURCE_DIR=$HOME/llvm-project
WINDOWS_ARCH=x86_64 # Architecture of the Windows-hosted tools to build.
PACKAGE_TAG=20261021 # Version label used in the output ZIP filename; defaults to the prebuilt release.
PACKAGE_NAME=llvm-mingw-$PACKAGE_TAG-$PREBUILT_CRT-$WINDOWS_ARCH
WINDOWS_PREFIX=$ROOT/install/$PACKAGE_NAME
CORES=${CORES:-8}
ZIP_FILE=$ROOT/$PACKAGE_NAME.zip

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
if [[ ! $PREBUILT_SHA256 =~ ^[[:xdigit:]]{64}$ ]]; then
    echo 'PREBUILT_SHA256 must be the 64-digit SHA256 for the selected archive.' >&2
    exit 1
fi

check_dependencies() {
    local missing=0
    for dep in curl sha256sum tar xz git cmake ninja make gcc g++ python3 \
               autoconf automake libtoolize pkg-config gettext autopoint bzip2 unzip file zip; do
        if ! command -v "$dep" >/dev/null; then
            echo "Missing dependency: $dep" >&2
            missing=1
        fi
    done
    return "$missing"
}

if ! check_dependencies; then
    if ! command -v apt-get >/dev/null; then
        echo 'Automatic dependency installation requires apt-get (Ubuntu/Debian).' >&2
        exit 1
    fi

    if (( EUID == 0 )); then
        SUDO=()
    elif command -v sudo >/dev/null; then
        SUDO=(sudo)
    else
        echo 'Missing dependencies; install them as root or make sudo available.' >&2
        exit 1
    fi

    echo 'Installing build dependencies with apt-get...'
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y build-essential cmake ninja-build git curl \
        ca-certificates xz-utils bzip2 unzip file zip python3 autoconf automake \
        libtool libltdl-dev pkg-config gettext autopoint

    if ! check_dependencies; then
        echo 'Dependency installation completed, but required commands are still missing.' >&2
        exit 1
    fi
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

PACKAGE="llvm-mingw-$PREBUILT_RELEASE-$PREBUILT_CRT-$PREBUILT_PLATFORM-$PREBUILT_ARCH"
ARCHIVE="$ROOT/prebuilt/$PACKAGE.tar.xz"
NATIVE="$ROOT/prebuilt/$PACKAGE"
mkdir -p "$ROOT/prebuilt"
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fL --retry 3 \
        -o "$ARCHIVE.part" \
        "https://github.com/mstorsjo/llvm-mingw/releases/download/$PREBUILT_RELEASE/$PACKAGE.tar.xz"
    printf '%s  %s\n' "$PREBUILT_SHA256" "$ARCHIVE.part" | sha256sum -c -
    mv -- "$ARCHIVE.part" "$ARCHIVE"
fi
printf '%s  %s\n' "$PREBUILT_SHA256" "$ARCHIVE" | sha256sum -c -
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

rm -f -- "$ZIP_FILE"
(cd -- "$ROOT/install" && zip -9rq "$ZIP_FILE" "$PACKAGE_NAME")

printf '\nFinished. Windows toolchain directory:\n%s\nRelease ZIP:\n%s\n' \
    "$WINDOWS_PREFIX" "$ZIP_FILE"
