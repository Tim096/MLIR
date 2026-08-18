# #215696 留言稿（2026-08-17）：謝 kuhar 的 approve ＋ 給 krzysz00 的 review 導覽

一則 top-level，同時對兩個人。

---

@kuhar thanks for the approval. A status note, since this has been sitting for
a few days: premerge is green on `358a393a`, the branch is still mergeable, and
nothing has changed since you approved. Do you want to keep waiting for a
second look, or is one approval enough here? Either way it needs someone else
to press the button -- I have no commit access.

@krzysz00 a short guide, in case it makes the review cheaper.

The patch makes `ceildivs` agree on `INT_MIN` across the places that compute it
today: the `index.ceildivs` folder, its LLVM and SPIR-V lowerings, the `affine`
`ceildiv` expansion, and the shared range inference in `InferIntRangeCommon`.
They disagree today, and not only after this patch:

- `-int-range-optimizations -canonicalize` folds
  `index.cmp sle(index.ceildivs(-2147483648, 7), 0)` to `true`, while the code
  from `--convert-index-to-llvm=index-bitwidth=32` evaluates it as false at
  runtime (@kuhar's example on this PR).
- `INT64_MIN ceildiv 7` expands to `1317624576693539401` through `affine`,
  where the exact ceiling is `-1317624576693539401`. `affine`'s own constant
  folder uses `divideCeilSigned` and gives the negative one, so the expansion
  has been the odd one out independently of the range inference.

The one behaviour change worth arguing about is `ceildivs(INT_MIN, -1)`: it
used to fold to `2147483648` and now does not fold at all. The exact result is
2^31, which 32 bits cannot hold; the old value was the correction term wrapping
back to `INT_MIN` and happening to match the truncation of the 64-bit result.
The lowering emits `sdiv INT_MIN, -1`, which is poison, and `arith.ceildivsi`
already refuses to fold the same case -- so refusing is the consistent answer.

The commits are ordered so that the tree is never inconsistent at any of them:
each lowering is fixed before the shared inference change lands on top.
`check-mlir` is 3858 passed / 0 failed.
