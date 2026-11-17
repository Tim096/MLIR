// The divisor is at least 1, so the division can never trap. It is loop
// invariant, but LICM leaves it in the loop: speculatability only looks for a
// constant divisor.
func.func @f(%x: i32, %n: i32, %lb: index, %ub: index, %m: memref<?xi32>) {
  %c1 = arith.constant 1 : i32
  %d = arith.maxsi %n, %c1 : i32
  %step = arith.constant 1 : index
  scf.for %i = %lb to %ub step %step {
    %q = arith.divsi %x, %d : i32
    memref.store %q, %m[%i] : memref<?xi32>
  }
  return
}
