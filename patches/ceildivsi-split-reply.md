# Reply draft — #214637, answering kuhar's second review

Post as a normal PR comment (not an inline reply). The branch has been
force-pushed (head `a1c2690f7d79`) and the split-out PR is #215696.

---

Split it out, as you suggested. This PR is back to the folder change and its
tests; the branch no longer touches `InferIntRangeCommon.cpp`.

You are right about `index`. Both `calculateCeilDivS` and
`ConvertIndexCeilDivS` compute the mixed-sign case as `-(-n / m)`. The folder
never returns the wrapped value, because `foldBinaryOpChecked` requires the
32-bit and the 64-bit result to agree and for `index.ceildivs(-2147483648, 7)`
they do not, so it does not fold at all on main. The lowering has no such
check.

#215696 fixes those two first and drops the `inferCeilDivS` workarounds on top,
so nothing in tree is inconsistent between its commits. It has the 32-bit
regression in `int-range-inference.mlir` you asked for.
