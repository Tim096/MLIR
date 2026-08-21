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
the input is multiplied or divided by the value of the scale. `ArithToAMDGPU`
already reads it that way in the IR: it casts the scale to `f32` by width and
passes the value on, with no `f8E8M0FNU` check anywhere in the file.

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
it as it is, picking the cast that fits the change in width: `arith.extf` and
`arith.truncf` where the width changes, and `arith.convertf` where it does
not. For a scale that already is `f8E8M0FNU` and arithmetic wider than eight
bits, that cast is the same widening as before, so those expansions are
emitted unchanged.

No cast bridges a scalar scale and a shaped operand, which the op verifier
permits because `ElementwiseMappable` exempts scalars, and `arith` cannot
broadcast one. That combination used to build an `arith.extf` that does not
verify; it is now reported as a match failure.

Eight tests in `expand-ops.mlir` use a scale that is not `f8E8M0FNU` and all
eight change. Six assert the `arith.truncf ... to f8E8M0FNU` step that is
gone. Two assert that a `f8E5M2FNUZ` scale fails to legalize, which it no
longer does, so they become expansion tests. Six are added: an `f8E5M3FNU`
scale and an equal-width scale for each op, a scale narrower than the
arithmetic type, and the scalar-scale case each op now rejects.

The op descriptions carry the same truncation in their example lowerings and
are updated with it.


---

Context: #215295. That thread asks whether `arith.scaling_truncf(in, scale)`
means `in / scale` or `in / 2^exponent(scale)`; this implements the first,
which is the reading @krzysz00 gave with the CDNA5 ISA sections for `f8E5M3`
scales. @tgymnich read it the other way earlier on #215123 and has not said
where he stands since, so this is the patch for one of the two answers rather
than a settled question -- please say so if you still read it as the exponent.

Not closed by this patch: `ArithToAMDGPU` casts any scale type to `f32` and
hands it to `amdgpu::PackedScaledTruncOp`, and `ROCDLOps.td` describes every
`cvt.scalef32` op it becomes as multiplying or dividing by *the exponent part
of* the scale (16 occurrences, e.g. `:2952`, `:2996`). So under this reading
the two lowerings disagree on the value of a non-power-of-two scale, and this
patch widens that gap rather than narrowing it: the generic expansion starts
using the whole scale while the hardware path keeps using its exponent. Closing
it is a separate change, and there is more than one reasonable way -- see the
comments below.

cc @tgymnich @krzysz00 @umangyadav @kuhar
