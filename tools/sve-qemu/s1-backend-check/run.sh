#!/usr/bin/env bash
# S-1 backend check: which scalable sub-byte functions does llc accept for SVE,
# and do the accepted ones compute the right values under qemu?
#
#   ./run.sh                      # uses llc / llvm-extract from PATH
#   LLVM_BIN=~/llvm-project/build/bin ./run.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${LLVM_BIN:+$LLVM_BIN/}
sysroot=${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}
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
  aarch64-linux-gnu-gcc -O1 -march=armv8-a+sve "${defs[@]}" "$here/harness.c" \
    "${objs[@]}" -o "$work/t$opt"
  for vq in 1 2 4; do
    printf '  '
    qemu-aarch64 -cpu max,sve-max-vq=$vq -L "$sysroot" "$work/t$opt" || status=1
  done
done
exit $status
