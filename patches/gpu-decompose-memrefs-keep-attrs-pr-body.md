`gpu-decompose-memrefs` rewrites a `memref.load`/`memref.store` inside a
`gpu.launch` into a `reinterpret_cast` to the linearised offset plus a
0-d access, but rebuilds the op from the new memref only. `nontemporal`,
`alignment` and `invariant` are dropped from the load, `nontemporal` and
`alignment` from the store:

```mlir
%res = memref.load %arg0[%tx, %ty, %tz] alignment(16) nontemporal(true) invariant(true) : memref<?x?x?xf32>
// becomes
%1 = memref.load %reinterpret_cast[] : memref<f32, strided<[], offset: ?>>
```

The rewrite accesses the same element with the same type, so all of
them still hold on the new op. Pass them to the builder; the attribute
form is the one that also carries `invariant`.

Tests: a load and a store case next to the existing `@decompose_load`
and `@decompose_store`.
