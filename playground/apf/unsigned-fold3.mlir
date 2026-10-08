func.func @trunc_neg_nan() -> f8E5M3FNU {
  %a = arith.constant 0xFFC00000 : f32
  %c = arith.truncf %a : f32 to f8E5M3FNU
  return %c : f8E5M3FNU
}
