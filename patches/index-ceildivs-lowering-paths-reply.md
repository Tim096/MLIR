# #215696 — reply to kuhar's second review (2026-08-13)

Top-level comment on the PR.

---

Both ported, each before the inference change, so no commit leaves the tree
inconsistent. The stack is now:

| commit | contents |
|---|---|
| 1 | `index` folder + IndexToLLVM + **IndexToSPIRV** |
| 2 | **affine `ceildiv` expansion** |
| 3 | drop the `inferCeilDivS` workarounds |
| 4 | 32-bit range-inference regression |

**IndexToSPIRV** got the same sequence as IndexToLLVM: one `SDiv`, then `+1`
when `q * m != n` and the operands share a sign. Both sequences evaluated at
i32 for `(-2147483648, 7)`:

    old: 306783378        new: -306783378

The op-sequence checks in `index-to-spirv.mlir` are updated, and there is a
value regression under the existing `INDEX32`/`INDEX64` runs, matching the one
you asked for in `index-to-llvm.mlir`.

**Affine** is the one place I did not copy the sequence verbatim. Affine
`ceildiv` requires a strictly positive divisor -- `visitCeilDivExpr` already
rejects a non-positive constant one, and the old expansion relied on it too --
so the sign comparison collapses and one compare is enough:

    a ceildiv b = let q = a / b in a > q * b ? q + 1 : q

`q * b` is `a` minus the remainder, so with `b > 0` the comparison holds exactly
when the division is inexact and the exact quotient is positive. Say the word if
you would rather have the sign test in there anyway for uniformity.

Measured on `INT64_MIN ceildiv 7`, same input both times:

    old: 1317624576693539401     new: -1317624576693539401

which is the number in your comment. Worth noting the expansion was the only one
of the three out of step: the affine constant folder goes through
`divideCeilSigned`, which returns the exact negative quotient for an `INT_MIN`
dividend, so the folder already disagreed with the lowering before
`inferCeilDivS` came into it.

The regression in `lower-affine.mlir` runs `-lower-affine -canonicalize` (new
`FOLDED` prefix) and hides the dividend behind an `arith.addi`, because
`affine.apply` folds before the conversion looks for a pattern -- a plain
constant operand never reaches the expansion, so a test written that way would
pass with the negation still in place. Checked by reverting the expansion and
rerunning: the test fails and prints `1317624576693539401`.

`@lowered_affine_ceildiv` in `Transforms/canonicalize.mlir` is a hand-copy of
what this lowering emits, so it changes with it; the note above it says as much.

`check-mlir` is 3848 passed / 0 failed and `git clang-format` is clean.
