Taking the naming correction: `toward_zero` it is (MLIR spells it without the
`s` -- `ArithBase.td:186`).

On the substance, this is now a straight disagreement with @tgymnich, who said
in #215123 that the scaling ops can be assumed to take the scale's exponent, per
the OCP MXFP spec. Worth being precise about what the spec does and does not
settle: it defines the scale of an MX format as `E8M0`, so it fixes the case you
two already agree on. It does not say what an `f16` or `f8E5M3FNU` scale means,
because in the spec there is no such thing -- and that is exactly the case you
are objecting about.

Where the tree stands today, for a non-`f8E8M0FNU` scale:

| | |
|---|---|
| `ExpandOps.cpp:675`, `:717` | a scale of 16 bits or wider is truncated to `f8E8M0FNU` first, so the mantissa is dropped. A `f8E5M3FNU` scale is 8 bits and not `f8E8M0FNU`, so it does not match at all -- there is no generic expansion for it |
| `ArithToAMDGPU.cpp:566` | the scale is extended or truncated to `f32` and handed to `amdgpu::PackedScaledTruncOp`. Any scale type is accepted, and the instruction reads the exponent |

So the case you want to expose lowers on AMDGPU today, with the mantissa
dropped by the hardware rather than by the IR, and has no generic lowering at
all. Neither path uses the mantissa.

The decision that unblocks everything else is one sentence:

**does `arith.scaling_truncf(in, scale : f16)` mean `in / scale`, or
`in / 2^exponent(scale)`?**

- `in / scale`: `ExpandOps.cpp` is wrong to truncate the scale, not merely
  wrong about which rounding mode it uses, and `ArithToAMDGPU` can only take
  the instruction's fast path when the scale is already `f8E8M0FNU` or the IR
  contains an explicit `arith.truncf ... toward_zero` for it -- which is your
  point 2, and it is a nicer shape than rejecting scales.
- `in / 2^exponent(scale)`: the expansions should say `toward_zero` explicitly
  rather than relying on the default, which is what @tgymnich proposed, and
  `f8E5M3FNU` scales should be accepted by the expansion instead of rejected.

Either way the `arith.truncf` question stays separate, and I am happy to write
whichever falls out. Meanwhile #215123 folds only scales that already are
`f8E8M0FNU`, which both readings agree on; extending it to other scale types
waits on this.
