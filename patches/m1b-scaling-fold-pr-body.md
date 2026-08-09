`arith.scaling_extf` and `arith.scaling_truncf` are the only two ops in the
dialect with neither a folder nor a canonicalizer, and neither
`canonicalize.mlir` nor `constant-fold.mlir` covers them today.

The gap shows up in a single run. For

```mlir
%in    = arith.constant 1.5 : f4E2M1FN
%scale = arith.constant 4.0 : f8E8M0FNU
%r     = arith.scaling_extf %in, %scale : f4E2M1FN, f8E8M0FNU to f32
```

`-arith-expand -canonicalize` produces `6.0 : f32`, while `-canonicalize`
alone leaves the op untouched. Pipelines that lower these ops to hardware
instructions rather than expanding them -- `ArithToAMDGPU`, `XeGPUToXeVM` --
never get the fold.

This adds a folder to both ops that computes exactly what the expansion in
`ExpandOps.cpp` computes:

    scaling_extf(in, scale)   -> mulf(extf(in), extf(scale))
    scaling_truncf(in, scale) -> truncf(in / extf(scale))

including its asymmetry: `scaling_extf` widens the scale to the result type,
`scaling_truncf` widens it to the type of `in`.

As with `arith.extf` and `arith.truncf`, the widening and narrowing steps go
through `convertFloatValue` and so only fold when they are lossless. A
`roundingmode` on `scaling_truncf` therefore never changes a folded result,
which is equally true of the existing `@truncFP*Constant` tests.

Two cases are deliberately left alone:

- Scales whose element type is not already `f8E8M0FNU`. `-arith-expand`
  accepts 16/32-bit scales by truncating them to `f8E8M0FNU` first, whereas
  `ArithToAMDGPU` reads their exponent field instead; for `scale = 1.6 : f16`
  the two disagree (2.0 vs 1.0). A folder should not have to pick a side.

- A NaN scale when the result type is finite-only, such as `f4E2M1FN`: no
  value there can carry the NaN the op documents propagating.

A NaN scale is otherwise handled directly rather than by widening it. That
lets the fold succeed even when widening `in` is lossy, which a NaN scale
makes irrelevant, and it keeps the result from depending on widening a
`f8E8M0FNU` NaN -- which produces a value that is a NaN but is encoded as an
infinity, since the format has no significand bits to hold the quiet bit
(#214919). Arithmetic on such a value quiets it and repairs the encoding,
which is why the expansion still ends up with a NaN, but the repair is
incidental.

### Verification

Beyond the added lit tests, these types have a small enough input space to
enumerate completely, so every combination was swept and each result checked
three ways: against `-arith-expand -canonicalize`, against the OCP MXFP
semantics computed without LLVM in the loop, and -- for the decision to fold
or not -- against the losslessness rule above, which catches missed folds and
not just wrong ones.

| sweep | cases | folded | disagreements |
|---|---|---|---|
| `scaling_extf` f4E2M1FN x f8E8M0FNU -> f16 | 4096 | 656 | 0 |
| `scaling_extf` f4E2M1FN x f8E8M0FNU -> f32 | 4096 | 4096 | 0 |
| `scaling_truncf` f16 x f8E8M0FNU -> f4E2M1FN | 16777216 | 33390 | 0 |

The folded counts are low where the losslessness rule bites, and the sweep
confirms each of those decisions rather than assuming them. `f16` can only
represent `2^e` exactly for `e` in [-24, 15], which is why 656 of the 4096
`-> f16` cases fold and all 4096 `-> f32` ones do. `f4E2M1FN` holds only
eight non-negative values, so most quotients are not representable in it and
`scaling_truncf` correctly declines.

`check-mlir`: 3838 passed, 0 failed (611 unsupported, 1 expectedly failed).
