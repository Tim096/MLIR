`ScalingExtFOpConverter` and `ScalingTruncFOpConverter` truncate a scale of
16 bits or wider to `f8E8M0FNU` before using it, and reject an 8-bit scale
that is not already `f8E8M0FNU`:

```mlir
// The scale is rounded to a power of two before it is ever used.
%0 = arith.scaling_truncf %in, %scale : f16, f16 to f4E2M1FN

// No generic expansion exists; this fails to legalize.
%1 = arith.scaling_truncf %in, %e5m3 : f16, f8E5M3FNU to f4E2M1FN
```

Both follow from reading the scale as an exponent. The OCP MXFP spec fixes
that reading only for the `E8M0` scale of an MX format, and hardware that
consumes an `f8E5M3` scale uses its mantissa, so the general reading is that
the input is multiplied or divided by the value of the scale.

The truncation is a wrong value rather than a wrong rounding mode. Constant
folding the IR the expansion emits for the scale gives the divisor it
actually uses:

| scale | divisor used | exact |
|---|---|---|
| `3.0` | `2.0` | `3.0` |
| `1.6` | `1.0` | `1.6` |
| `7.0` | `4.0` | `7.0` |

The error approaches a factor of two just below a power of two.

## Change

Both converters cast the scale to the type the arithmetic happens in and use
it as it is. For a scale that already is `f8E8M0FNU` that cast is the same
widening as before, so those expansions are emitted unchanged.

`arith.extf` and `arith.truncf` each require a strict change in width, so a
scale as wide as the operand but of a different type has no conversion to
spell. The previous code did not check for that and built an op that does not
verify; this reports a match failure instead.

Eight tests in `expand-ops.mlir` use a scale that is not `f8E8M0FNU` and all
eight change. Six assert the `arith.truncf ... to f8E8M0FNU` step that is
gone. Two assert that a `f8E5M2FNUZ` scale fails to legalize, which it no
longer does, so they become expansion tests. Four are added: an `f8E5M3FNU`
scale for each op, and the equal-width case each op now rejects.

The op descriptions carry the same truncation in their example lowerings and
are updated with it.


---

Context: #215295. That thread asks whether `arith.scaling_truncf(in, scale)`
means `in / scale` or `in / 2^exponent(scale)`; this implements the first,
which is the reading @krzysz00 gave with the CDNA5 ISA sections for `f8E5M3`
scales. @tgymnich read it the other way earlier on #215123 and has not said
where he stands since, so this is the patch for one of the two answers rather
than a settled question -- please say so if you still read it as the exponent.

Not in this patch: `ArithToAMDGPU` casts any scale type to `f32` and hands it
to `amdgpu::PackedScaledTruncOp`. If that instruction reads only the exponent
bits, that path drops the mantissa under this reading too, but the answer is
in hardware documentation rather than in the tree, so it is a separate change.

cc @tgymnich @krzysz00 @umangyadav @kuhar
