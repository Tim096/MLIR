Ping on the question above -- it is down to one decision, and I am happy to write
either patch:

**Is `arith.truncf` to `f8E8M0FNU` round-to-nearest-even like every other
`truncf`, or is it exponent extraction?**

- Round-to-nearest: `F8E8M0TruncFOpConverter` in `ExpandOps.cpp` is the one that
  is wrong, and it should round rather than take the exponent.
- Exponent extraction: the op documentation should say so, and the folder should
  stop routing this conversion through `APFloat::convert`.

Everything else follows. Note the pass today also rejects the only rounding mode
anyone can write: `F8E8M0TruncFOpConverter` bails whenever a rounding-mode
attribute is present, so `arith.truncf %x to_nearest_even : f32 to f8E8M0FNU`
fails to legalize under `--arith-expand=include-f8e8m0`, while the same op
without the attribute is expanded as if it meant something else.

@krzysz00 the question in my previous comment still stands: under an
exponent-only reading, is there anything left to reject in `ArithToAMDGPU`, and
what did you mean about `f8E5M3FNU` scales working correctly? Under that reading
an E5M3 scale loses its mantissa on both paths, so I am probably misreading you.

For context on the practical stake: #215123 folds these ops only when the scale
is already `f8E8M0FNU`, deliberately, so that the folder does not settle this
question. Whichever way it goes, that restriction can be revisited afterwards.
