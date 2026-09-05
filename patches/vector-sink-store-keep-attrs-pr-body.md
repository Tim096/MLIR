`StoreOpFromBroadcast` rebuilds a one-element `vector.store` of a
broadcast as a `vector.store` or `memref.store` of the broadcast source,
at the same base and indices, but does not forward `nontemporal` or
`alignment`:

```mlir
%0 = vector.broadcast %v : f32 to vector<1xf32>
vector.store %0, %mem[%i] alignment = 16 nontemporal = true : memref<?xf32>, vector<1xf32>
// sink patterns today
memref.store %v, %mem[%i] : memref<?xf32>
```

The rebuilt store writes the same address, so both attributes still
hold. This passes them through the builders. Same shape of fix as
#221319 for `vector.linearize`.
