`RewriteLoadFromReinterpretCast` rebuilds the load on the source of the
`memref.reinterpret_cast` with the indices remapped to the non-unit
dimensions, but the rebuilt load carries none of `nontemporal`,
`alignment` or `invariant`:

```mlir
%rc = memref.reinterpret_cast %src to offset: [0], sizes: [1, 1, 8], strides: [8, 8, 1] : memref<1x8xf32> to memref<1x1x8xf32>
%0 = memref.load %rc[%c0, %c0, %i] alignment(16) nontemporal(true) invariant(true) : memref<1x1x8xf32>
// -memref-elide-reinterpret-cast today
%0 = memref.load %src[%c0, %i] : memref<1x8xf32>
```

The rewrite only changes how the same element is addressed, so the three
attributes describe the same access. This forwards them. Same shape of
fix as #221312 for `gpu-decompose-memrefs`.
