#!/usr/bin/env bash
set -euo pipefail

# Pinned Apple Swift LLVM 23 revision (not the moving stable/23.x tip).
LLVM_REPOSITORY="https://github.com/swiftlang/llvm-project.git"
LLVM_VERSION="5de7d6a6d231e388b1914487aab27c6543648901"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$HOME/llvm-mingw-native"
WINDOWS="$HOME/llvm-mingw-windows"
ARCHIVE="$HOME/llvm-mingw-swift-23-windows-x64.tar.gz"
cd "$ROOT"

export LLVM_REPOSITORY LLVM_VERSION
export CORES="${CORES:-6}"
# Use these flags for both LLVM builds; add Windows-specific flags only later.
BASE_LLVM_CMAKEFLAGS="-DCLANG_INCLUDE_TESTS=OFF"
export LLVM_CMAKEFLAGS="$BASE_LLVM_CMAKEFLAGS"

printf '%s\n' '=== Installing build dependencies ==='
sudo apt-get update
sudo apt-get install -y \
    build-essential clang lld cmake ninja-build git curl wget python3 \
    autoconf automake libtool pkg-config texinfo xz-utils zlib1g-dev file

printf '%s\n' '=== Checking Apple LLVM checkout ==='
if [[ -e llvm-project && ! -d llvm-project/.git ]]; then
    echo 'ERROR: llvm-project exists but is not a normal Git checkout' >&2
    exit 1
fi
if [[ -d llvm-project/.git ]]; then
    current_remote="$(git -C llvm-project remote get-url origin)"
    if [[ "$current_remote" != "$LLVM_REPOSITORY" ]]; then
        printf 'ERROR: unexpected llvm-project origin: %s\n' "$current_remote" >&2
        exit 1
    fi
fi

# Fetch/check out LLVM before editing the sources; don't reset existing build output.
export SYNC=1
CHECKOUT_ONLY=1 ./build-llvm.sh

printf '%s\n' '=== Applying Apple LLVM compatibility fixes ==='
EXPORTS="$ROOT/llvm-project/clang/tools/IndexStore/IndexStore.exports"
[[ -f "$EXPORTS" ]] || {
    echo 'ERROR: expected Apple LLVM source files not found' >&2
    exit 1
}

# Apple's export list names IndexStore functions absent from this build.
# Delete exact lines; repeated runs are harmless.
sed -i -E \
    '/^indexstore_(store_units_apply|store_set_unit_event_handler|occurrence_relations_apply|record_reader_search_symbols|record_reader_symbols_apply|record_reader_occurrences_apply|record_reader_occurrences_in_line_range_apply|record_reader_occurrences_of_symbols_apply|unit_reader_dependencies_apply|unit_reader_includes_apply)$/d' \
    "$EXPORTS"

printf '%s\n' '=== Building Linux-hosted toolchain and target runtimes ==='
./build-all.sh "$NATIVE" --disable-lldb

printf '%s\n' '=== Building Windows-native toolchain (Windows 10 API) ==='
# MinGW-w64 defaults to Windows 7 headers. Apple's LLVM uses newer APIs:
# GetCurrentThreadStackLimits and FileRenameInfoEx. FileRenameInfoEx is
# gated by NTDDI_VERSION >= 0x0A000002 (Windows 10 version 1607).
# Scope these flags to the Windows-native tools build.
WINDOWS_CMAKE_CACHE="$ROOT/.swift-llvm-windows-api.cmake"
cat > "$WINDOWS_CMAKE_CACHE" <<'CMAKE'
set(CMAKE_C_FLAGS "-D_WIN32_WINNT=0x0A00 -DNTDDI_VERSION=0x0A000002" CACHE STRING "Windows API target" FORCE)
set(CMAKE_CXX_FLAGS "-D_WIN32_WINNT=0x0A00 -DNTDDI_VERSION=0x0A000002" CACHE STRING "Windows API target" FORCE)
CMAKE
export LLVM_CMAKEFLAGS="$BASE_LLVM_CMAKEFLAGS -C $WINDOWS_CMAKE_CACHE"
./build-cross-tools.sh "$NATIVE" "$WINDOWS" x86_64 --disable-lldb

printf '%s\n' '=== Verifying Windows compiler ==='
[[ -f "$WINDOWS/bin/clang.exe" ]] || {
    echo 'ERROR: clang.exe not installed' >&2
    exit 1
}
file "$WINDOWS/bin/clang.exe"
git -C llvm-project rev-parse HEAD

printf '%s\n' '=== Packaging Windows toolchain ==='
tar -C "$HOME" -czf "$ARCHIVE" "$(basename "$WINDOWS")"
printf 'Windows toolchain: %s\nArchive: %s\n' "$WINDOWS" "$ARCHIVE"
