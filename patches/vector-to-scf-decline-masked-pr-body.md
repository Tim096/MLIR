The transfer op patterns in `convert-vector-to-scf` unpack a
`vector.transfer_read`/`vector.transfer_write` into a loop, a buffer and
lower-rank transfer ops, but never check whether the op sits inside a
`vector.mask`. In that case all of it lands in the mask region and the
pass fails:

```mlir
func.func @w(%v: vector<4x8xf32>, %m: vector<4x8xi1>, %mem: memref<?x?xf32>) {
  %c0 = arith.constant 0 : index
  vector.mask %m { vector.transfer_write %v, %mem[%c0, %c0] : vector<4x8xf32>, memref<?x?xf32> } : vector<4x8xi1>
  return
}
```

```
error: 'vector.mask' op expects only one operation to mask
```

The unrolled, 1-D and scalable-transpose paths do the same, and the
transfer ops they emit carry no mask at all, since `getMask()` only sees
the mask operand. This declines masked transfer ops in every pattern;
`-lower-vector-mask` turns the `vector.mask` into a mask operand, which
the patterns already handle, and that is the order the in-tree
integration tests use.

Tests: four negative cases covering the progressive, unrolled, 1-D and
scalable-transpose patterns, checked under all three `RUN` lines.
