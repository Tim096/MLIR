Split out of #214637, where @kuhar pointed out that changing the shared
`intrange::inferCeilDivS` would put it at odds with `index::CeilDivSOp`, whose
folder and lowering are unchanged.

Five places in tree compute signed ceiling division, and four of them do it by
negating an operand:

- `index::calculateCeilDivS`, `ConvertIndexCeilDivS` (LLVM) and
  `ConvertIndexCeilDivSPattern` (SPIR-V) compute the mixed-sign case as
  `-(-n / m)`.
- `expandAffineExpr` lowers affine `ceildiv` as
  `a <= 0 ? -(-a / b) : (a - 1) / b + 1`.
- `intrange::inferCeilDivS` negates the quotient of `MININT / [positive
  number]`, with a second workaround unioning in `[MININT + 1, smax]` to cover
  the discontinuity that introduces.

Negating `INT_MIN` wraps, so all of them report a positive value where the
mathematical result is negative. The expansion in `ExpandOps.cpp` does not
negate anything and has computed the mathematical ceiling since #133774
(2025-04); the workarounds in the inference were written for the expansion that
preceded it. Affine's own constant folder, `divideCeilSigned`, does not negate
either.

The commits are ordered so that nothing in tree is inconsistent in between:

1. The `index` folder and both `index` lowerings compute the ceiling without
   negating an operand.
2. The affine `ceildiv` expansion does the same.
3. The `inferCeilDivS` workarounds are dropped.
4. A 32-bit regression for the inference, in `int-range-inference.mlir`.

### What changes for `index`

The folder never returned the wrong value, because `foldBinaryOpChecked`
requires the 32-bit and the 64-bit result to agree, and for
`index.ceildivs(-2147483648, 7)` they do not (`306783378` against
`-306783378`). It simply did not fold. It folds to `-306783378` now.

The lowerings have no such check.
`-convert-index-to-llvm=index-bitwidth=32` and
`-convert-index-to-spirv=use-64bit-index=false` emitted the wrapped
computation, so the same op evaluated to `306783378` at run time.

One fold is lost: `ceildivs(INT_MIN, -1)`. Its exact result, `2^31`, is not
representable on 32-bit; the old computation passed the consistency check there
only because the correction wrapped back to `INT_MIN`, and the lowering emits
`sdiv INT_MIN, -1`, which is poison. `arith.ceildivsi` does not fold this case
either.

### What changes for affine

Affine `ceildiv` requires a strictly positive divisor -- `visitCeilDivExpr`
rejects a non-positive constant one, and the old expansion relied on that too --
so the correction needs neither a negation nor a sign test:

    a ceildiv b = let q = a / b in a > q * b ? q + 1 : q

`q * b` is `a` minus the remainder, so with `b > 0` the comparison holds exactly
when the division is inexact and the exact quotient is positive. For
`INT64_MIN ceildiv 7` the lowered arithmetic went from `1317624576693539401` to
`-1317624576693539401`, which is what the affine constant folder already
returned.

`@lowered_affine_ceildiv` in `Transforms/canonicalize.mlir` is a hand-copy of
what this lowering emits, so it changes with it.

### Verification

`check-mlir`: 3848 passed, 0 failed (611 unsupported, 1 expectedly failed).
`git clang-format` clean.

Measured before and after, on `a558267da71f`:

| | before | after |
|---|---|---|
| `-canonicalize` on `index.ceildivs(-2147483648, 7)` | does not fold | `-306783378` |
| `-canonicalize` on `index.ceildivs(-2147483648, -1)` | `2147483648` | does not fold |
| `-int-range-optimizations` on `index.cmp sle(index.ceildivs(-2147483648, 7), 0)` | unresolved | `true` |
| `-lower-affine -canonicalize` on `INT64_MIN ceildiv 7` | `1317624576693539401` | `-1317624576693539401` |
| the SPIR-V sequence evaluated at i32 for `(-2147483648, 7)` | `306783378` | `-306783378` |

Each new regression was checked against a build without the change it covers:
the `int-range-inference.mlir` one fails with only the first commit applied, so
it pins the inference rather than the folder, and the affine one fails with the
old expansion restored, printing the positive value.

The affine regression hides its dividend behind an `arith.addi` on purpose:
`affine.apply` folds before the conversion looks for a pattern, so a plain
constant operand never reaches the expansion under test.
