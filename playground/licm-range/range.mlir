func.func @g(%n: i32) -> i32 {
  %c1 = arith.constant 1 : i32
  %d = arith.maxsi %n, %c1 : i32
  %r = test.reflect_bounds %d : i32
  return %r : i32
}
