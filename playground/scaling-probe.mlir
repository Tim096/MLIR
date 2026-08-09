// Probe: what does upstream fold TODAY for arith.scaling_extf / scaling_truncf?
// Run: mlir-opt scaling-probe.mlir -canonicalize

// 1. Both operands constant, scale already f8E8M0FNU.
func.func @ext_all_const() -> f32 {
  %in = arith.constant 1.5 : f4E2M1FN
  %scale = arith.constant 4.0 : f8E8M0FNU
  %r = arith.scaling_extf %in, %scale : f4E2M1FN, f8E8M0FNU to f32
  return %r : f32
}

// 2. Scale is the identity (2^0 = 1.0). Should degenerate to a plain extf.
func.func @ext_unit_scale(%in: f4E2M1FN) -> f32 {
  %scale = arith.constant 1.0 : f8E8M0FNU
  %r = arith.scaling_extf %in, %scale : f4E2M1FN, f8E8M0FNU to f32
  return %r : f32
}

// 3. Same, vector form (this is the shape real MXFP code has).
func.func @ext_unit_scale_vector(%in: vector<4xf4E2M1FN>) -> vector<4xf32> {
  %scale = arith.constant dense<1.0> : vector<4xf8E8M0FNU>
  %r = arith.scaling_extf %in, %scale : vector<4xf4E2M1FN>, vector<4xf8E8M0FNU> to vector<4xf32>
  return %r : vector<4xf32>
}

// 4. NaN scale: spec says result must be NaN.
func.func @ext_nan_scale(%in: f4E2M1FN) -> f32 {
  %scale = arith.constant 0xFF : f8E8M0FNU
  %r = arith.scaling_extf %in, %scale : f4E2M1FN, f8E8M0FNU to f32
  return %r : f32
}

// 5. truncf side, both constant.
func.func @trunc_all_const() -> f4E2M1FN {
  %in = arith.constant 6.0 : f32
  %scale = arith.constant 2.0 : f8E8M0FNU
  %r = arith.scaling_truncf %in, %scale : f32, f8E8M0FNU to f4E2M1FN
  return %r : f4E2M1FN
}

// 6. truncf with identity scale.
func.func @trunc_unit_scale(%in: f32) -> f4E2M1FN {
  %scale = arith.constant 1.0 : f8E8M0FNU
  %r = arith.scaling_truncf %in, %scale : f32, f8E8M0FNU to f4E2M1FN
  return %r : f4E2M1FN
}

// 7. Non-E8M0 scale (f16). ExpandOps and ArithToAMDGPU disagree here.
func.func @ext_f16_scale(%in: f4E2M1FN) -> f32 {
  %scale = arith.constant 1.0 : f16
  %r = arith.scaling_extf %in, %scale : f4E2M1FN, f16 to f32
  return %r : f32
}
