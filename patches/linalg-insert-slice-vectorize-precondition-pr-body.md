`vectorizeAsInsertSliceOp` reads the whole source and writes it back with
a minor identity map at the slice offsets, but its precondition never
looks at the strides or at which dims a rank-reducing insert drops. The
`vector.transfer_write` it produces then stores the source somewhere else
than the `tensor.insert_slice` did:

```mlir
// Rows 0 and 1 of %dst instead of rows 0 and 3.
tensor.insert_slice %src into %dst[0, 0] [2, 4] [3, 1] : tensor<2x4xf32> into tensor<8x4xf32>

// A vector<8x4xf32> along dims 1 and 2 of %dst with in_bounds = [false, true],
// so only row 0 of %src is kept.
tensor.insert_slice %src into %dst[0, 0, 0] [8, 1, 4] [1, 1, 1] : tensor<8x4xf32> into tensor<8x1x4xf32>
```

`PadOpVectorizationWithInsertSlicePattern` rejects both shapes. Do the
same in the precondition: bail unless the strides are 1 and the dropped
dims of a rank-reducing insert are the leading ones, which is the case the
existing tests cover and the case the FIXME on the vector shape
computation assumes.

Tests: the two shapes above in `unsupported.mlir`, plus a rank-reducing
insert that drops the leading dim in `insert-slice.mlir` to pin down that
it still vectorizes.
