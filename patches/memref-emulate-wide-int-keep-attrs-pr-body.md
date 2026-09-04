`ConvertMemRefLoad` and `ConvertMemRefStore` forward `nontemporal` to the
rebuilt op but not `alignment`, nor `invariant` on the load; both
attributes were added after the pass:

```mlir
%v = memref.load %m[%c0] alignment(16) nontemporal(true) invariant(true) : memref<4xi64, 1>
// -memref-emulate-wide-int today
%v = memref.load %m[%c0] nontemporal(true) : memref<4xvector<2xi32>, 1>
```

The emulated memref has the same byte layout as the original (`iN` becomes
`vector<2xiN/2>`), so the same index names the same address and the
attributes still describe the access. This forwards all of them through
the attribute builder, next to the existing `nontemporal`.

Tests: one load/store case with all attributes, mirroring the existing
`@alloc_load_store_i64_nontemporal`.
