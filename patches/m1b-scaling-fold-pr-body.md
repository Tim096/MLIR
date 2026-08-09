[mlir][arith] Fold scaling_extf and scaling_truncf with constant operands

Add constant folders for the two MXFP scaling casts, mirroring the expansion
in `ExpandOps.cpp`:

```
scaling_extf(in, scale)   -> mulf(extf(in), extf(scale))
scaling_truncf(in, scale) -> truncf(in / extf(scale))
```

Note the asymmetry the expansion already has: `scaling_extf` widens the scale
to the result type, `scaling_truncf` to the type of `in`.

These were the only two ops in the dialect with neither a folder nor a
canonicalizer, so `-canonicalize` left them alone even with both operands
constant, while `-arith-expand -canonicalize` folded them away. Pipelines that
lower them to hardware instructions rather than expanding them, such as
`ArithToAMDGPU` and `XeGPUToXeVM`, never got the fold.

As in `arith.extf` and `arith.truncf`, the widening and narrowing steps go
through `convertFloatValue` and fold only when lossless, so a `roundingmode`
on `scaling_truncf` never changes a folded result. Poison propagates and
shaped results are guarded with a static-shape check, as in the generic
folders.

Scales that are not already `f8E8M0FNU` are left alone: `-arith-expand`
truncates wider scales to `f8E8M0FNU` first while `ArithToAMDGPU` reads their
exponent field, and for `scale = 1.6 : f16` the two disagree (2.0 vs 1.0).

A NaN scale is built directly rather than by widening it, which for
`f8E8M0FNU` yields a value encoded as an infinity: that format has no
significand bits to hold the quiet bit. It stays unfolded when the result type
is finite-only, such as `f4E2M1FN`, which cannot represent a NaN at all.

The input space of these types is small enough to enumerate, so every
combination was checked against `-arith-expand -canonicalize`, against the OCP
MXFP semantics computed independently of LLVM, and -- for the decision to fold
or not -- against the losslessness rule above:

| sweep | cases | folded | disagreements |
| :--- | ---: | ---: | ---: |
| `scaling_extf` f4E2M1FN x f8E8M0FNU -> f16 | 4096 | 656 | 0 |
| `scaling_extf` f4E2M1FN x f8E8M0FNU -> f32 | 4096 | 4096 | 0 |
| `scaling_truncf` f16 x f8E8M0FNU -> f4E2M1FN | 16777216 | 33390 | 0 |
