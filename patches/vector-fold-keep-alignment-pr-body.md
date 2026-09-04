The all-true mask folders for `vector.maskedload`, `maskedstore`,
`expandload` and `compressstore`, and the contiguous-indices folders for
`vector.gather` and `scatter`, rebuild the op without its `alignment`:

```mlir
%0 = vector.maskedload %base[%c0], %mask, %pt alignment = 64 : memref<16xf32>, vector<16xi1>, vector<16xf32> into vector<16xf32>
// -canonicalize today
%0 = vector.load %base[%c0] : memref<16xf32>, vector<16xf32>
```

The folded op touches the same address as the original: the mask folders
keep the base and indices, and the contiguous folders keep the base and
offsets, which is where the contiguous run starts. This forwards the
attribute through the builders. The folders predate the `alignment`
attribute on these ops (#144344, #151690), which is why it was never
copied.

Tests: one `alignment = 64` case per folder in `vector-mem-transforms.mlir`
and `canonicalize.mlir`.
