`ExtractOpFromLoad` rebuilds a `vector.load` as a narrower load at the
extract position, and `UnrollLoadPattern`/`UnrollStorePattern` rebuild a
`vector.load`/`vector.store` per tile at the tile offset. All of them
drop `nontemporal` and `alignment`:

```mlir
%0 = vector.load %mem[%c0, %c0] alignment = 16 nontemporal = true : memref<4x4xf16>, vector<4x4xf16>
// unrolled to 2x2 today
%1 = vector.load %mem[%c0, %c0] : memref<4x4xf16>, vector<2x2xf16>
%2 = vector.load %mem[%c0, %c2] : memref<4x4xf16>, vector<2x2xf16>
...
```

`nontemporal` still describes the access. The alignment does not carry
over as is: the new access is at a byte offset from the old one, and
only the alignment that both the old access and the offset satisfy holds
for it (`[%c0, %c2]` above is 4 bytes in, so it is 4-byte aligned, while
`[%c2, %c0]` is 16 bytes in and keeps the 16).

This adds `vector::getAlignmentAfterOffset`, which turns the element
offsets on the trailing dimensions into a byte offset through the static
strides of the memref and returns `llvm::commonAlignment` of the two, or
nothing when the strides or the offset are not static (a dynamic extract
position, a `memref<?x?xf32>` row stride, an `index` element type), and
uses it in the three patterns, forwarding `nontemporal` next to it.

Tests: for the sink pattern, a zero offset, a static offset in the
innermost dimension, a dynamic offset, and a static and a dynamic row
stride; for unrolling, a 2-D load and store where the tiles alternate
between the original and the reduced alignment.

The forwarding-only cases, where the address does not move, are
#221317, #221319, #221382 and #221383.
