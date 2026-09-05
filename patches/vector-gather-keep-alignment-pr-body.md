`UnrollGatherPattern` rebuilds a `vector.gather` per tile from the same
base and offsets, slicing only the index, mask and pass-through vectors,
and `MaskedGatherOpPattern` rebuilds the gather inside a `vector.mask`
with the mask of the region. Neither forwards the `alignment` attribute:

```mlir
%0 = vector.mask %m { vector.gather %base[%c0] [%idx], %all_true, %pt alignment = 8 : memref<64xf32>, vector<4xindex>, vector<4xi1>, vector<4xf32> into vector<4xf32> } : vector<4xi1> -> vector<4xf32>
// -lower-vector-mask today
%0 = vector.gather %base[%c0] [%idx], %m, %cst : memref<64xf32>, vector<4xindex>, vector<4xi1>, vector<4xf32> into vector<4xf32>
```

The rebuilt gathers access the same addresses, so the alignment still
holds. This passes it through the builder, the same way the gather
unrolling in `LowerVectorGather` already does.

The bufferization of `vector.gather`/`vector.scatter` rebuilds them too,
but the verifier rejects `alignment` on a tensor base, so there is
nothing to forward there.
