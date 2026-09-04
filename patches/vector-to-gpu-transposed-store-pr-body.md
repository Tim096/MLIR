`convert-vector-to-gpu` lowers a `vector.transfer_read` whose permutation
map puts the most minor dimension first to a `transpose` MMA load since
18ecdbfe6c74, but still rejects the same shape of `vector.transfer_write`:

```mlir
// Lowered to gpu.subgroup_mma_load_matrix ... leadDimension 3 transpose
%0 = vector.transfer_read %a[%c0, %c0], %f {in_bounds = [true, true], permutation_map = affine_map<(d0, d1) -> (d1, d0)>} : memref<5x3xf16>, vector<3x5xf16>

// Left alone
vector.transfer_write %1, %b[%c0, %c0] {in_bounds = [true, true], permutation_map = affine_map<(d0, d1) -> (d1, d0)>} : vector<3x5xf16>, memref<5x3xf16>
```

The TODO in `transferWriteSupportsMMAMatrixType` waits for a transpose
attribute on the GPU dialect op. `gpu.subgroup_mma_store_matrix` has had
one since 3d35546cd168, and both the NVVM and the SPIR-V lowerings honour
it, so this classifies the write the same way as the read and sets the
attribute. `leadDimension` already comes from the position of the map
dimensions, so the stride helper is unchanged.

Tests: the existing `no_convert_write_transpose` becomes a positive test,
plus the 3-D and 4-D strided cases and a not-last-dim negative case,
mirroring the read side.
