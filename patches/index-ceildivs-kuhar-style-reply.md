# #215696 — reply to kuhar's third round (2026-08-14)

## Inline reply to r3777102307 (`Affine/Utils/Utils.cpp:156`)

Trimmed to the invariant: the divisor is positive, so unlike the
`arith.ceildivsi` expansion no sign comparison is needed. The change-history
paragraph and the two cross-references are gone -- you are right that they can
go stale independently of this file, and the PR description is the place for
them.

## Top-level

Both points taken, thanks.

The description no longer counts implementations. It is bounded to the
arith / index / affine path and lists each one with its status, so there is
nothing to be wrong about beyond that boundary.

On `arith::CeilDivSIOp::fold` specifically: that is the folder #214637
replaced, and the TODO went with it. This branch was based on `a558267da71f`
(2026-08-11), which is a day older than that merge (`2a0c335d4538`,
2026-08-12), so the tree you opened still had the negating version. Rebased
onto `5f33e4f07a67`, where it reads

```cpp
        APInt quotient = a.sdiv_ov(b, overflowDiv);
        ...
        if (a.isNegative() != b.isNegative() || quotient * b == a)
          return quotient;
```

and the description's first row says so rather than claiming a count.

`check-mlir` is 3858 passed / 0 failed and `git clang-format` is clean.
