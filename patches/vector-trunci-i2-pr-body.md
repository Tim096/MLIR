`RewriteAlignedSubByteIntTrunc` handles `arith.trunci` to `i4` and bails on
`i2`, while the extension side of the same file has handled both widths since
#121298 (whose author left the truncation for whoever needed it):

```mlir
// Rewritten: deinterleave, mask, shift, or, bitcast.
%0 = arith.trunci %a : vector<8xi8> to vector<8xi4>

// Left alone, so LLVM gets the sub-byte trunc.
%1 = arith.trunci %a : vector<8xi8> to vector<8xi2>
```

This adds the `i8 -> i2` half. The bytes are deinterleaved twice to group
them by their position in the destination byte, masked to their low two bits,
shifted into place and merged, then bitcast to `i2`. The `i8` truncation of a
wider source and the alignment preconditions are unchanged, so an `i2` result
whose trailing dimension is not a multiple of four still goes through the
old path.

Tests: the existing `aligned_trunci_i8_to_i2_no_match` becomes a positive
test, plus `i32` source, 2-D, and unaligned cases. The integration test gets
an `i2` truncation printed as bits. Locally, all 256 byte values through the
rewritten and the unrewritten path print the same 512 bits with `mlir-runner`,
for a 1-D `i8` source, a 2-D `i8` source, and an `i32` source.
