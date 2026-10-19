
#!/usr/bin/env bash
set -euo pipefail

# Apple Swift LLVM source
LLVM_REPOSITORY="https://github.com/swiftlang/llvm-project.git"
LLVM_VERSION="5de7d6a6d231e388b1914487aab27c6543648901"

# Paths
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$HOME/llvm-mingw-native"
WINDOWS="$HOME/llvm-mingw-windows"
ARCHIVE="$HOME/llvm-mingw-swift-23-windows-x64.tar.gz"

cd "$ROOT"

# Build settings
export LLVM_REPOSITORY LLVM_VERSION
export LLVM_CMAKEFLAGS="-DCLANG_INCLUDE_TESTS=OFF"
export CORES="${CORES:-8}"

echo "=== Installing build dependencies ==="

sudo apt-get update
sudo apt-get install -y \
    build-essential \
    clang \
    lld \
    cmake \
    ninja-build \
    git \
    curl \
    wget \
    python3 \
    autoconf \
    automake \
    libtool \
    pkg-config \
    texinfo \
    xz-utils \
    zlib1g-dev

echo "=== Preparing Apple LLVM sources ==="

if [[ -d llvm-project ]]; then
    if [[ ! -d llvm-project/.git ]]; then
        echo "ERROR: llvm-project exists but is not a Git checkout"
        exit 1
    fi

    CURRENT_REMOTE="$(git -C llvm-project remote get-url origin)"
    if [[ "$CURRENT_REMOTE" != "$LLVM_REPOSITORY" ]]; then
        echo "ERROR: llvm-project has a different origin:"
        echo "  $CURRENT_REMOTE"
        echo "Expected:"
        echo "  $LLVM_REPOSITORY"
        echo "Move the existing checkout or change its remote."
        exit 1
    fi
fi

# Forces build-llvm.sh to select the requested commit.
export SYNC=1

echo "=== Patching Apple IndexStore exports ==="

EXPORTS="$ROOT/llvm-project/clang/tools/IndexStore/IndexStore.exports"

# Fetch/check out the requested LLVM commit before patching.
(
    cd "$ROOT"
    CHECKOUT_ONLY=1 SYNC=1 ./build-llvm.sh
)

# Remove the ten unavailable symbols.
sed -i -E \
    '/^indexstore_(store_units_apply|store_set_unit_event_handler|occurrence_relations_apply|record_reader_search_symbols|record_reader_symbols_apply|record_reader_occurrences_apply|record_reader_occurrences_in_line_range_apply|record_reader_occurrences_of_symbols_apply|unit_reader_dependencies_apply|unit_reader_includes_apply)$/d' \
    "$EXPORTS"

echo "=== Building Linux-hosted toolchain ==="
./build-all.sh "$NATIVE" --disable-lldb

echo "=== Building Windows-native toolchain ==="
./build-cross-tools.sh \
    "$NATIVE" \
    "$WINDOWS" \
    x86_64 \
    --disable-lldb

echo "=== Verifying Windows compiler ==="

test -f "$WINDOWS/bin/clang.exe"

file "$WINDOWS/bin/clang.exe" 2>/dev/null || true
git -C llvm-project rev-parse HEAD

echo "=== Packaging toolchain ==="

tar -C "$HOME" -czf "$ARCHIVE" \
    "$(basename "$WINDOWS")"

echo "=== Build complete ==="
echo "Windows toolchain: $WINDOWS"
echo "Archive: $ARCHIVE"
