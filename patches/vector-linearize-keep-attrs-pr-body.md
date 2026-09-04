`LinearizeVectorLoad` and `LinearizeVectorStore` rebuild the op with the
flattened vector type but leave out `alignment` and `nontemporal`:

```mlir
%0 = vector.load %m[%c0, %c0] alignment = 16 nontemporal = true : memref<2x8xf32>, vector<1x4xf32>
// -test-vector-linearize today
%0 = vector.load %m[%c0, %c0] : memref<2x8xf32>, vector<4xf32>
```

Only the vector type changes; the base, the indices and the bytes accessed
are the same, so this forwards both attributes through the builder.

Tests: one load and one store case with both attributes in `linearize.mlir`.
