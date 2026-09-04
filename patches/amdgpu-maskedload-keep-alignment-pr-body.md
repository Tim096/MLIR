The `amdgpu-maskedload-to-load` patterns rebuild a `vector.maskedload`
as `vector.load` (and a full-mask `vector.maskedstore` as
`vector.store`) from the original base and indices, but do not forward
the `alignment` attribute. The lowered op then falls back to the
element alignment in `convert-vector-to-llvm`:

```mlir
%0 = vector.maskedload %mem[%i, %i], %mask, %pass alignment = 16 : memref<8x8xf16>, vector<4xi1>, vector<4xf16> into vector<4xf16>
```

```
// before: llvm.load %p {alignment = 2 : i64}  : !llvm.ptr -> vector<4xf16>
// after:  llvm.load %p {alignment = 16 : i64} : !llvm.ptr -> vector<4xf16>
```

The rewritten access uses the same base, indices and vector type, so
the alignment the user asserted on the masked op still holds. Pass it
through the `vector.load`/`vector.store` builders, the same way
`AffineToStandard` forwards it.

Tests: one case per creation site (fat raw buffer with an arbitrary
mask, full-mask load, full-mask store).
