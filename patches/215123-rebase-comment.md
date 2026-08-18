# #215123 — rebase 後的留言（tgymnich 已 approve）

送出對象：PR #215123 top-level comment
前提：tgymnich 2026-08-17 09:41 UTC APPROVED，留言「LGTM. Still needs a rebase on main」
已送出：https://github.com/llvm/llvm-project/pull/215123#issuecomment-5322730819（2026-08-18）

---

Rebased on main. The conflict was with #216056, which landed in the meantime and
put its tests at the same place in `canonicalize.mlir`; resolving it was keeping
both blocks. The folder and the ODS change are byte-identical to what you
approved -- only the hunk offsets moved.

Worth saying explicitly, since #216056 changed `APFloat::convert` to report a
lost sign and a lost zero: that change does not reach this folder. The
conversions here go out of `f8E8M0FNU`, which is lossless in that direction, and
into the result type, and no test changed behaviour. `check-mlir` is 3873 passed
/ 0 failed on the rebased branch, and `git clang-format HEAD~1` is clean.

I have no commit access, so this one still needs someone to land it.
