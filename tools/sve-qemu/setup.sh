#!/usr/bin/env bash
# Run MLIR's ArmSVE integration tests on an x86-64 machine under qemu-aarch64.
# Nothing here needs root: the packages are downloaded and unpacked under
# ~/aarch64-cross, and the host clang is used as the cross compiler.
#
#   ./setup.sh deps     download and unpack qemu-user-static and the AArch64 sysroot
#   ./setup.sh smoke    run a tiny SVE program under qemu at 128/256/512 bits
#   ./setup.sh cross    cross-build an AArch64 mlir-runner, lli and runner libraries
#   ./setup.sh enable   reconfigure the host build to run SVE tests emulated
#   ./setup.sh test     run the upstream ArmSVE integration tests
#   ./setup.sh all      deps + smoke + cross + enable + test
#
# Paths (override with environment variables):
#   LLVM_SRC       llvm-project checkout            default: ~/llvm-project
#   HOST_BUILD     existing x86-64 build directory  default: $LLVM_SRC/build
#   CROSS_BUILD    AArch64 build directory (new)    default: $LLVM_SRC/build-aarch64
#   AARCH64_CROSS  where qemu and the sysroot go    default: ~/aarch64-cross
#
# The host build must already contain llvm-tblgen, mlir-tblgen, mlir-pdll and
# mlir-linalg-ods-yaml-gen: the cross build runs them instead of building its
# own. Do not run ninja in HOST_BUILD and CROSS_BUILD at the same time.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/env.sh"
LLVM_SRC=${LLVM_SRC:-$HOME/llvm-project}
HOST_BUILD=${HOST_BUILD:-$LLVM_SRC/build}
CROSS_BUILD=${CROSS_BUILD:-$LLVM_SRC/build-aarch64}
# -L tells qemu where the AArch64 dynamic loader and libc live.
EMULATOR_OPTIONS="-cpu max -L $QEMU_LIB_PREFIX"

say() { printf '\n== %s\n' "$*"; }

deps() {
  say "Downloading qemu-user-static and the AArch64 sysroot into $AARCH64_CROSS"
  mkdir -p "$AARCH64_CROSS/debs" "$SYSROOT"
  (cd "$AARCH64_CROSS/debs" && apt-get download \
    qemu-user-static \
    libc6-arm64-cross libc6-dev-arm64-cross linux-libc-dev-arm64-cross \
    libgcc-s1-arm64-cross libgcc-11-dev-arm64-cross \
    libstdc++6-arm64-cross libstdc++-11-dev-arm64-cross libatomic1-arm64-cross)
  for deb in "$AARCH64_CROSS"/debs/*.deb; do
    dpkg-deb -x "$deb" "$SYSROOT"
  done
  cat >"$TOOLCHAIN_FILE" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT $SYSROOT)

set(CMAKE_C_COMPILER $(command -v clang))
set(CMAKE_CXX_COMPILER $(command -v clang++))
set(CMAKE_C_COMPILER_TARGET aarch64-linux-gnu)
set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-gnu)

set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
  "$QEMU" --version | head -1
}

smoke() {
  say "SVE smoke test under qemu"
  local tmp
  tmp=$(mktemp -d)
  aarch64_cc -O2 -march=armv8-a+sve "$here/hello_sve.c" -o "$tmp/hello_sve"
  for vq in 1 2 4; do
    "$QEMU" -cpu max,sve-max-vq=$vq -L "$QEMU_LIB_PREFIX" "$tmp/hello_sve"
  done
  rm -rf "$tmp"
}

cross() {
  say "Cross-building AArch64 mlir-runner into $CROSS_BUILD"
  for tool in llvm-tblgen mlir-tblgen mlir-pdll mlir-linalg-ods-yaml-gen; do
    [ -x "$HOST_BUILD/bin/$tool" ] || {
      echo "missing $HOST_BUILD/bin/$tool - build it in the host build first:" >&2
      echo "  ninja -C $HOST_BUILD llvm-tblgen mlir-tblgen mlir-pdll mlir-linalg-ods-yaml-gen" >&2
      exit 1
    }
  done
  cmake -G Ninja -S "$LLVM_SRC/llvm" -B "$CROSS_BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DLLVM_HOST_TRIPLE=aarch64-linux-gnu \
    -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-linux-gnu \
    -DLLVM_TARGETS_TO_BUILD=AArch64 \
    -DLLVM_ENABLE_PROJECTS=mlir \
    -DLLVM_NATIVE_TOOL_DIR="$HOST_BUILD/bin" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_CCACHE_BUILD=ON \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF -DMLIR_INCLUDE_TESTS=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF
  ninja -C "$CROSS_BUILD" mlir-runner lli mlir_c_runner_utils mlir_runner_utils \
    mlir_arm_runner_utils
  file "$CROSS_BUILD/bin/mlir-runner"
}

enable() {
  say "Reconfiguring $HOST_BUILD to run ArmSVE tests under qemu"
  # Keep the targets the host build already has and add AArch64, so that the
  # host llc can compile for SVE (s1-backend-check/run.sh needs it).
  local targets
  targets=$(sed -n 's/^LLVM_TARGETS_TO_BUILD:STRING=//p' "$HOST_BUILD/CMakeCache.txt")
  case ";$targets;" in
    *";AArch64;"* | *";all;"*) ;;
    *) targets="$targets;AArch64" ;;
  esac
  cmake -S "$LLVM_SRC/llvm" -B "$HOST_BUILD" \
    -DLLVM_TARGETS_TO_BUILD="$targets" \
    -DMLIR_INCLUDE_INTEGRATION_TESTS=ON \
    -DMLIR_RUN_ARM_SVE_TESTS=ON \
    -DARM_EMULATOR_EXECUTABLE="$QEMU" \
    -DARM_EMULATOR_OPTIONS="$EMULATOR_OPTIONS" \
    -DARM_EMULATOR_MLIR_RUNNER_EXECUTABLE="$CROSS_BUILD/bin/mlir-runner" \
    -DARM_EMULATOR_LLI_EXECUTABLE="$CROSS_BUILD/bin/lli" \
    -DARM_EMULATOR_UTILS_LIB_DIR="$CROSS_BUILD/lib"
  ninja -C "$HOST_BUILD" check-mlir-build-only llc llvm-extract
  link_host_lib_paths
}

# 7 of the 18 upstream ArmSVE tests pass %mlir_runner_utils (the host x86-64
# library in $HOST_BUILD/lib) to the emulated runner instead of
# %native_mlir_runner_utils, so the AArch64 runner cannot load it. qemu opens
# <-L prefix>/<path> in place of <path> when the former exists, so put links
# to the AArch64 libraries there under the host library's path.
link_host_lib_paths() {
  local dir="$QEMU_LIB_PREFIX$HOST_BUILD/lib"
  mkdir -p "$dir"
  for lib in "$CROSS_BUILD"/lib/libmlir_*.so*; do
    ln -sfn "$lib" "$dir/$(basename "$lib")"
  done
}

run_tests() {
  say "Running the upstream ArmSVE integration tests"
  "$HOST_BUILD/bin/llvm-lit" -v \
    "$HOST_BUILD/tools/mlir/test/Integration/Dialect/Vector/CPU/ArmSVE" \
    "$HOST_BUILD/tools/mlir/test/Integration/Dialect/Linalg/CPU/ArmSVE"
}

case "${1:-}" in
  deps) deps ;;
  smoke) smoke ;;
  cross) cross ;;
  enable) enable ;;
  test) run_tests ;;
  all) deps; smoke; cross; enable; run_tests ;;
  *) sed -n '2,21p' "$0"; exit 2 ;;
esac
