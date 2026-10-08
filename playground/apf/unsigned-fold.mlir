func.func @sub_same_exp() -> f8E5M3FNU {
  %a = arith.constant 1.0 : f8E5M3FNU
  %b = arith.constant 1.5 : f8E5M3FNU
  %c = arith.subf %a, %b : f8E5M3FNU
  return %c : f8E5M3FNU
}
