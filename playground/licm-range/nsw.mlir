func.func @g(%a: i8) -> i32 {
  %z = arith.extui %a : i8 to i32
  %c = arith.constant 2147483647 : i32
  %s = arith.addi %z, %c overflow<nsw> : i32
  %c1 = arith.constant 1 : i32
  %d = arith.addi %s, %c1 overflow<nsw> : i32
  %r = test.reflect_bounds %d : i32
  return %r : i32
}
