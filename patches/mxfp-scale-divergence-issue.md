`arith.scaling_extf` and `arith.scaling_truncf` take a scale of any float type,
but the generic expansion and the AMDGPU lowering interpret a scale that is not
a power of two differently, and I cannot tell from the tree which one is
intended.

### Reproducer

```mlir
// 1.6 lies between 2^0 and 2^1.
func.func @ext(%in: f4E2M1FN) -> f32 {
  %scale = arith.constant 1.600000e+00 : f16
  %r = arith.scaling_extf %in, %scale : f4E2M1FN, f16 to f32
  return %r : f32
}
```

```
$ mlir-opt repro.mlir -arith-expand
  %0 = arith.truncf %cst : f16 to f8E8M0FNU     // scale is quantized here
  %1 = arith.extf %0 : f8E8M0FNU to f32
  %2 = arith.extf %arg0 : f4E2M1FN to f32
  %3 = arith.mulf %2, %1 : f32
```

```
$ mlir-opt repro.mlir --convert-arith-to-amdgpu=chipset=gfx950
  %cst = arith.constant 1.59960938 : f32        // scale is passed through
  %0 = vector.broadcast %arg0 : f4E2M1FN to vector<1xf4E2M1FN>
  %1 = amdgpu.scaled_ext_packed %0[0], %cst : vector<1xf4E2M1FN> to vector<2xf32>
```

`arith.truncf` to `f8E8M0FNU` rounds to nearest, so the first path scales by
`2.0`:

```mlir
%c = arith.constant 1.600000e+00 : f8E8M0FNU
%e = arith.extf %c : f8E8M0FNU to f32     // folds to 2.000000e+00
```

The second path hands the hardware `1.59960938` unrounded. So for the same IR
the two lowerings scale by `2.0` and by `1.59960938` respectively -- or by
`2.0` and `1.0`, if the instruction consumes only the exponent field of its
f32 scale operand, which is what an E8M0 scale would suggest.

### What the documentation says

`ArithOps.td` spells the interpretation out for both ops, and the `truncf` to
`f8E8M0FNU` is part of it:

```mlir
// Cast scale to result type.
%0 = arith.truncf %1 : f32 to f8E8M0FNU
%1 = arith.extf %0 : f8E8M0FNU to f16
```

On the AMDGPU side I could not find the corresponding statement anywhere:
`amdgpu.scaled_ext_packed` says only "extend and scale", the
`llvm.amdgcn.cvt.scalef32.*` intrinsics carry no description, and
`AMDGPUUsage.rst` does not mention them. So there is no way to check the
lowering against a written contract.

### Why it seems worth settling

A scale that is already `f8E8M0FNU` behaves identically on both paths, which is
the case real MXFP code hits, so this is not a bug anyone is likely to trip
over today. But the op accepts 16- and 32-bit scales specifically so that the
exponent can be extracted implicitly, and for those the numerical result
currently depends on which pass the pipeline happens to run. Note also that
`GPUToXeVMPipeline` expands MX scaling ops before conversion (#203632), so the
XeVM path follows the generic interpretation.

### Question

Does `V_CVT_SCALEF32_*` use the whole f32 scale operand, or only its exponent
field? Depending on the answer, one of these seems to be needed:

1. `ArithToAMDGPU` truncates the scale to `f8E8M0FNU` before extending it to
   f32, matching the documented interpretation; or
2. the op documentation is tightened to say that a non-`f8E8M0FNU` scale is
   interpreted by taking its exponent, and the generic expansion is changed to
   match; or
3. non-`f8E8M0FNU` scales are rejected outright, since both readings are
   defensible and neither is currently guaranteed.

Happy to send a patch once it is clear which one is wanted.

cc @tgymnich @krzysz00 @kuhar @umangyadav
