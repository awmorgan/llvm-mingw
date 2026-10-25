# Build the Linux-hosted toolchain
LLVM_REPOSITORY=https://github.com/awmorgan/llvm-project \
    LLVM_VERSION=x \
    LLVM_CMAKEFLAGS='-DCMAKE_CXX_FLAGS=-D_WIN32_WINNT=0x0A00 -DLLDB_ENABLE_SWIFT_SUPPORT=OFF' \
    CORES=16 \
    ./build-all.sh --with-clang "$PWD/install/linux-bootstrap"

# Use it as the bootstrap to build tools hosted on Windows.
# LLVM_CMAKEFLAGS='-DCMAKE_CXX_FLAGS=-D_WIN32_WINNT=0x0A00 -DLLDB_ENABLE_SWIFT_SUPPORT=OFF' \
#   ./build-cross-tools.sh \
#   "$PWD/install/linux-bootstrap" \
#   "$PWD/install/windows-x86_64" \
#   x86_64