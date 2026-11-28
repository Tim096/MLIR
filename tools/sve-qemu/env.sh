# Shared paths for setup.sh and s1-backend-check/run.sh. Source, do not run.
#
# Everything lives under $AARCH64_CROSS (default ~/aarch64-cross), no root:
#   debs/      the downloaded .deb files
#   sysroot/   the .deb files extracted (qemu-aarch64-static, AArch64 libc,
#              libstdc++ and libgcc)
#   aarch64-toolchain.cmake   written by `setup.sh deps`
AARCH64_CROSS=${AARCH64_CROSS:-$HOME/aarch64-cross}
SYSROOT=$AARCH64_CROSS/sysroot
# qemu looks for /lib/ld-linux-aarch64.so.1 and the shared libraries here.
QEMU_LIB_PREFIX=$SYSROOT/usr/aarch64-linux-gnu
QEMU=$SYSROOT/usr/bin/qemu-aarch64-static
TOOLCHAIN_FILE=$AARCH64_CROSS/aarch64-toolchain.cmake

# The host clang is the cross compiler: it only needs a target and a sysroot.
aarch64_cc() {
  clang --target=aarch64-linux-gnu --sysroot="$SYSROOT" -fuse-ld=lld "$@"
}
