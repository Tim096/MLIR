#!/usr/bin/env bash
# S-1 backend check: which scalable sub-byte functions does llc accept for SVE,
# and do the accepted ones compute the right values under qemu?
#
#   ./run.sh                      # uses ~/llvm-project/build/bin
#   LLVM_BIN=/other/build/bin ./run.sh
#
# Needs `../setup.sh deps` (qemu and the sysroot) and an llc that has the
# AArch64 target (`../setup.sh enable` adds it to the host build).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../env.sh"
bin=${LLVM_BIN:-$HOME/llvm-project/build/bin}/
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"${bin}llc" --version | grep -m1 "LLVM version"
status=0
for opt in 0 2; do
  objs=()
  defs=()
  echo "--- llc -O$opt"
  for f in trunc_direct trunc_rewritten sext_direct sext_rewritten; do
    "${bin}llvm-extract" --func="$f" "$here/subbyte.ll" -S -o "$work/$f.ll"
    # The braces keep bash's own "Aborted" message out of the output when llc
    # dies on a fatal backend error.
    if { "${bin}llc" -O$opt -mtriple=aarch64-linux-gnu -mattr=+sve \
        "$work/$f.ll" -filetype=obj -o "$work/$f.$opt.o"; } \
        2>"$work/$f.$opt.err"; then
      echo "  $f: compiles"
      objs+=("$work/$f.$opt.o")
      defs+=("-DHAVE_$f")
    else
      echo "  $f: backend error: $(grep -m1 'LLVM ERROR' "$work/$f.$opt.err")"
    fi
  done
  [ ${#objs[@]} -eq 0 ] && continue
  aarch64_cc -O1 -march=armv8-a+sve "${defs[@]}" "$here/harness.c" \
    "${objs[@]}" -o "$work/t$opt"
  for vq in 1 2 4; do
    printf '  '
    "$QEMU" -cpu max,sve-max-vq=$vq -L "$QEMU_LIB_PREFIX" "$work/t$opt" || status=1
  done
done
exit $status
