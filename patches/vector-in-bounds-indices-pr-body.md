`createReadOrMaskedRead` and `createWriteOrMaskedWrite` infer `in_bounds`
from the permutation map alone: a vector dimension is in bounds when the
source dimension it maps to is static and divisible by the vector size.
That only holds when the index is a multiple of the vector size, which the
affine super-vectorizer guarantees for an induction variable that starts at
zero and for nothing else. With an offset index or an unaligned lower bound
the last vector runs past the end of the memref while still carrying
`in_bounds = [true]`:

```mlir
affine.for %i = 0 to 15 {
  %v = affine.load %A[%i + 1] : memref<16xf32>
  affine.store %v, %B[%i] : memref<16xf32>
}
```

`-affine-super-vectorize="virtual-vector-size=8"` today:

```mlir
affine.for %arg2 = 0 to 15 step 8 {
  %0 = affine.apply affine_map<(d0) -> (d0 + 1)>(%arg2)
  %2 = vector.transfer_read %arg0[%0], %1 {in_bounds = [true]} : memref<16xf32>, vector<8xf32>
```

The second iteration reads elements 9 to 16, and `-convert-vector-to-llvm`
turns the read into a plain `llvm.load`. The same happens for
`affine.for %i = 4 to 16` with `%A[%i]`.

This requires the index to be a known multiple of the vector size: a
constant, an `affine.for` induction variable whose step and lower bound
are multiples, or an `affine.apply` whose map preserves that. Loop bounds
are followed recursively, so a tiled loop whose lower bound is an outer
induction variable, as in `vectorize_2d_inbounds.mlir`, still qualifies.
The check is a syntactic walk over the defining ops, no constraint sets.

The existing `affine-super-vectorize` tests keep their `in_bounds` except
`vec_affine_apply_2`, whose index `d0 mod 16 + 1` is offset by one. New
tests cover the offset and unaligned-lower-bound cases and their aligned
counterparts.

The `FIXME`s on the no-map branches stay: every in-tree caller reaches
them with zero indices, or with `tensor.insert_slice` offsets that the
verifier already bounds.
