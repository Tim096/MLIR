func.func @sub_larger_exp() -> f8E5M3FNU {
  %a = arith.constant 4.0 : f8E5M3FNU
  %b = arith.constant 8.0 : f8E5M3FNU
  %c = arith.subf %a, %b : f8E5M3FNU
  return %c : f8E5M3FNU
}
