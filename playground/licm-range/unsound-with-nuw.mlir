// Range analysis says %d is never 0, but only because of the nuw flag:
// for %n = UINT_MAX the add overflows and %d is poison. If the loop runs zero
// times the division is never executed today. Hoisted, it divides by poison.
func.func @f(%x: i32, %n: i32, %lb: index, %ub: index, %m: memref<?xi32>) -> i32 {
  %c1 = arith.constant 1 : i32
  %d = arith.addi %n, %c1 overflow<nuw> : i32
  %r = test.reflect_bounds %d : i32
  %step = arith.constant 1 : index
  scf.for %i = %lb to %ub step %step {
    %q = arith.divui %x, %d : i32
    memref.store %q, %m[%i] : memref<?xi32>
  }
  return %r : i32
}
