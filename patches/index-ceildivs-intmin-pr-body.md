# PR body — index/arith ceildivs INT_MIN (split out of #214637)

Title: `[mlir] Compute ceildivs consistently for INT_MIN operands`

---

Split out of #214637, where @kuhar pointed out that changing the shared
`intrange::inferCeilDivS` would put it at odds with `index::CeilDivSOp`, whose
folder and lowering are unchanged.

Three places in tree compute signed ceiling division, and two of them do it by
negating an operand:

- `index::calculateCeilDivS` and `ConvertIndexCeilDivS` compute the mixed-sign
  case as `-(-n / m)`.
- `intrange::inferCeilDivS` negates the quotient of `MININT / [positive
  number]`, with a second workaround unioning in `[MININT + 1, smax]` to cover
  the discontinuity that introduces.

Negating `INT_MIN` wraps, so all three report a positive value where the
mathematical result is negative. The expansion in `ExpandOps.cpp` does not
negate anything and has computed the mathematical ceiling since #133774
(2025-04); the workarounds in the inference were written for the expansion that
preceded it.

The commits are ordered so that nothing in tree is inconsistent in between:

1. `index` folder and lowering compute the ceiling without negating an operand.
2. The `inferCeilDivS` workarounds are dropped.
3. A 32-bit regression for the inference, in `int-range-inference.mlir`.

### What changes for `index`

The folder never returned the wrong value, because `foldBinaryOpChecked`
requires the 32-bit and the 64-bit result to agree, and for
`index.ceildivs(-2147483648, 7)` they do not (`306783378` against
`-306783378`). It simply did not fold. It folds to `-306783378` now.

The lowering has no such check. `-convert-index-to-llvm=index-bitwidth=32`
emitted the wrapped computation, so the same op evaluated to `306783378` at run
time.

One fold is lost: `ceildivs(INT_MIN, -1)`. Its exact result, `2^31`, is not
representable on 32-bit; the old computation passed the consistency check there
only because the correction wrapped back to `INT_MIN`, and the lowering emits
`sdiv INT_MIN, -1`, which is poison. `arith.ceildivsi` does not fold this case
either.

### Verification

`check-mlir`: 3848 passed, 0 failed (611 unsupported, 1 expectedly failed).
`git clang-format` clean.

Measured before and after, on `a558267da71f`:

| | before | after |
|---|---|---|
| `-canonicalize` on `index.ceildivs(-2147483648, 7)` | does not fold | `-306783378` |
| `-canonicalize` on `index.ceildivs(-2147483648, -1)` | `2147483648` | does not fold |
| `-int-range-optimizations` on `index.cmp sle(index.ceildivs(-2147483648, 7), 0)` | unresolved | `true` |

The new regression in `int-range-inference.mlir` was checked against a build
with only the first commit applied: it fails there, so it pins the inference
change rather than the folder one.
