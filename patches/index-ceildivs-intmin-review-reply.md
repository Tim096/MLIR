# Reply draft — #215696, answering kuhar's first review

Three inline replies. Post each under the comment it answers, with
`gh api repos/llvm/llvm-project/pulls/215696/comments/<id>/replies`, otherwise
it lands as a separate top-level comment.

| # | Comment id | Anchor |
|---|---|---|
| a | `3766876868` | `mlir/lib/Dialect/Index/IR/IndexOps.cpp:259` |
| b | `3766876874` | `mlir/test/Dialect/Index/index-canonicalize.mlir:190` |
| c | `3766876880` | `mlir/test/Conversion/IndexToLLVM/index-to-llvm.mlir:69` |

The branch is force-pushed; all three changes are amended into the first
commit, so the stack stays at three commits.

---

## (a) `IndexOps.cpp` — use `RoundingSDiv`

Done. `RoundingSDiv` with `Rounding::UP` tests `Rem.isNegative() !=
B.isNegative()`, and `sdivrem` gives the remainder the sign of the dividend, so
that is the same same-sign condition the hand-rolled version tested. Dropping
my `sadd_ov` on the correction is fine for the reason `RoundingSDiv` leaves its
own `Quo + 1` unguarded: a quotient of `INT_MAX` needs `m == +/-1`, and both of
those divide exactly, so the correction never fires on one.

One deviation from what you wrote, now called out in the commit message: I
spelled the rejection as the bit test `sdiv_ov` itself performs rather than
calling `sdiv_ov` and discarding the quotient, since `RoundingSDiv` already
divides internally and the fold has no reason to divide twice. Say the word if
you would rather the guard name the helper it came from.

## (b) `index-canonicalize.mlir` — negative/negative inexact case

Added as a second result in `@ceildivs_neg`: `ceildivs(-5, -2)` folds to `3`.
That function already held the negative dividend case, so it seemed the natural
home, and you are right that nothing else exercised the correction with two
negative operands.

## (c) `index-to-llvm.mlir` — value-based regression

Added, under the existing `INDEX32`/`INDEX64` runs rather than a new one:
`ceildivs(-2147483648, 7)` now checks `llvm.mlir.constant(-306783378 : i32)` and
the `i64` counterpart. The conversion alone already emits the constant, so it
does not need `-canonicalize`; that pass only deletes the two dead operand
constants.

It is worth recording what the check pins, because it is not the emitted
sequence. `ConversionConfig::foldingMode` defaults to `BeforePatterns`, so
`OperationLegalizer` folds an illegal op before it looks for a pattern
(`DialectConversion.cpp:2601`). With constant operands `ConvertIndexCeilDivS`
therefore never runs, and the value comes from `calculateCeilDivS`.

It still fails on main, which is what you asked for: there the fold bails on an
`INT_MIN` dividend, so the pattern does run, and nothing folds its output
afterwards -- `llvm.sdiv`, `llvm.add`, `llvm.mul` and `llvm.select` have no
folders. So the check catches "the fold and the lowering disagree about this
input", which is exactly the bug. What it cannot catch is a lowering that
regresses while the folder stays correct; the operation-sequence checks above it
are still what covers that.

---

## Top-level comment (post after the three replies)

All three addressed, amended into the first commit; the stack is still three
commits and the new head is `7a0d9f0ea804`.

Re-ran the oracle sweep on the folder after the switch to `RoundingSDiv`, over
7140 operand pairs (every pair from -40..40 plus `INT_MAX`, `INT_MIN`,
`1000000007` and `-1000000007`, zero divisors excluded), comparing against exact
ceiling division computed outside LLVM: no mismatches, and the only pair that
does not fold is `(-2147483648, -1)`.

`ninja check-mlir` is 3848 passed / 0 failed and `git clang-format` is clean.
