#!/usr/bin/env bash
# Run MLIR's ArmSVE integration tests on an x86-64 machine under qemu-aarch64.
#
#   ./setup.sh deps     install qemu-user and the AArch64 cross toolchain (sudo)
#   ./setup.sh smoke    run a tiny SVE program under qemu at 128/256/512 bits
#   ./setup.sh cross    cross-build an AArch64 mlir-runner + runner libraries
#   ./setup.sh enable   reconfigure the host build to run SVE tests emulated
#   ./setup.sh test     run the upstream ArmSVE integration tests
#   ./setup.sh all      deps + smoke + cross + enable + test
#
# Paths (override with environment variables):
#   LLVM_SRC      llvm-project checkout            default: ~/llvm-project
#   HOST_BUILD    existing x86-64 build directory  default: $LLVM_SRC/build
#   CROSS_BUILD   AArch64 build directory (new)    default: $LLVM_SRC/build-aarch64
#
# The host build must already contain llvm-tblgen, mlir-tblgen, mlir-pdll and
# mlir-linalg-ods-yaml-gen: the cross build runs them instead of building its
# own. Do not run ninja in HOST_BUILD and CROSS_BUILD at the same time.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
LLVM_SRC=${LLVM_SRC:-$HOME/llvm-project}
HOST_BUILD=${HOST_BUILD:-$LLVM_SRC/build}
CROSS_BUILD=${CROSS_BUILD:-$LLVM_SRC/build-aarch64}
SYSROOT=${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}
# -L tells qemu where the AArch64 dynamic loader and libc live.
EMULATOR_OPTIONS="-cpu max -L $SYSROOT"

say() { printf '\n== %s\n' "$*"; }

deps() {
  say "Installing qemu-user and the AArch64 cross toolchain"
  sudo apt-get update -qq
  sudo apt-get install -y qemu-user gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
}

smoke() {
  say "SVE smoke test under qemu"
  local tmp
  tmp=$(mktemp -d)
  aarch64-linux-gnu-gcc -O2 -march=armv8-a+sve "$here/hello_sve.c" -o "$tmp/hello_sve"
  for vq in 1 2 4; do
    qemu-aarch64 -cpu max,sve-max-vq=$vq -L "$SYSROOT" "$tmp/hello_sve"
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
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DLLVM_HOST_TRIPLE=aarch64-unknown-linux-gnu \
    -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-gnu \
    -DLLVM_TARGETS_TO_BUILD=AArch64 \
    -DLLVM_ENABLE_PROJECTS=mlir \
    -DLLVM_NATIVE_TOOL_DIR="$HOST_BUILD/bin" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_TERMINFO=OFF
  ninja -C "$CROSS_BUILD" mlir-runner mlir_c_runner_utils mlir_runner_utils \
    mlir_arm_runner_utils
  file "$CROSS_BUILD/bin/mlir-runner"
}

enable() {
  say "Reconfiguring $HOST_BUILD to run ArmSVE tests under qemu"
  cmake -S "$LLVM_SRC/llvm" -B "$HOST_BUILD" \
    -DMLIR_INCLUDE_INTEGRATION_TESTS=ON \
    -DMLIR_RUN_ARM_SVE_TESTS=ON \
    -DARM_EMULATOR_EXECUTABLE="$(command -v qemu-aarch64)" \
    -DARM_EMULATOR_OPTIONS="$EMULATOR_OPTIONS" \
    -DARM_EMULATOR_MLIR_RUNNER_EXECUTABLE="$CROSS_BUILD/bin/mlir-runner" \
    -DARM_EMULATOR_UTILS_LIB_DIR="$CROSS_BUILD/lib"
}

run_tests() {
  say "Running the upstream ArmSVE integration tests"
  "$HOST_BUILD/bin/llvm-lit" -v \
    "$LLVM_SRC/mlir/test/Integration/Dialect/Vector/CPU/ArmSVE" \
    "$LLVM_SRC/mlir/test/Integration/Dialect/Linalg/CPU/ArmSVE"
}

case "${1:-}" in
  deps) deps ;;
  smoke) smoke ;;
  cross) cross ;;
  enable) enable ;;
  test) run_tests ;;
  all) deps; smoke; cross; enable; run_tests ;;
  *) sed -n '2,19p' "$0"; exit 2 ;;
esac
