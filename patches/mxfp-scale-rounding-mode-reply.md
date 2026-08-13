That works for me, and it is better than either of the two answers I offered:
carrying the rounding mode in the IR settles the question without anyone having
to declare one reading canonical. Two things to pin down before I write it.

**What is implemented today is one of the two, not both.**
`F8E8M0TruncFOpConverter` shifts right by 23 and truncates to `i8`, so it takes
the exponent field. For the values `f8E8M0FNU` can hold -- positive ones --
that is `downward`, and `toward_zero` coincides with it. `to_nearest_even` is
not implemented at all: allowing it means adding the rounding (half an ulp of
the exponent field before the shift, and a tie rule), not just widening the
predicate.

**What does an absent rounding mode expand to?** That is the part I would like
settled explicitly, because today the pass bails on any attribute and expands
the attribute-free op by exponent extraction. If the default now means
round-to-nearest-even, as `kDefaultRoundingMode` says elsewhere, then every
current user of `--arith-expand=include-f8e8m0` changes behaviour and the
`scaling_*` expansions keep theirs by asking for `downward` explicitly, which is
what your suggestion does. If the default keeps meaning exponent extraction,
then `downward` is just a name for what already happens and nothing else moves.
I would rather write the first, but it is a behaviour change and worth saying
out loud.

**Sign and zero stay undefined under either mode.** `trunci` to `i8` drops the
sign bit, so `-2.0` truncates to `2.0`; and the exponent field of `0.0` is
`0x00`, which `F8E8M0ExtFOpConverter` reads back as `0.0` while `APFloat` reads
it as 2^-127. Neither is a rounding question. #216056 makes `APFloat::convert`
report both as lost, which stops the folder from producing those values, but the
expansion still computes them silently. Worth deciding whether the expansion
should reject a negative or zero operand.

If the direction holds, I am happy to write it as:

1. `F8E8M0TruncFOpConverter` accepts `downward`/`toward_zero` with today's code
   path and implements `to_nearest_even`, rejecting the rest.
2. `ScalingExtFOpConverter` and `ScalingTruncFOpConverter` emit
   `arith.truncf ... downward` for the scale rather than relying on the default.
3. The folder in #215123 mirrors the same rule, which is what you asked for
   there -- fold any scale type, as long as it matches the expansion.

@krzysz00 the piece that needs you: is `downward` the right name for what
`V_CVT_SCALEF32_*` does with a non-E8M0 scale? Your comment says the
instructions read only the exponent bits, which is exactly this, but I would
rather have it from you than infer it.
