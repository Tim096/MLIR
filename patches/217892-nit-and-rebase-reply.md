# #217892 回覆稿（2026-09-04）：krzysz00 的 nit ＋ 他對 cvt.scalef32 的補充

## inline（回在 3832259652 底下）

Done. The tests this patch touches now capture the arguments with
`SCHECK-SAME` under the label. The `f8E8M0FNU` tests it does not touch still
spell `%arg0`; I left those alone to keep the diff to the patch.

## top-level（回他 5373010733 那則）

Thanks, that settles it for the case this patch adds: an `f8E5M3` scale reaches
the instruction through the `extf` to `f32` in `ArithToAMDGPU`, and bits 31:23
of that `f32` are its sign and exponent, so the mantissa is dropped there while
the generic expansion keeps it. That is a point for option 1 above -- take the
instruction only for an `f8E8M0FNU` scale or an explicit `toward_zero`
truncation, and emit the multiply or divide otherwise. I would do that as the
follow-up rather than here, unless you want it in this PR.

Rebased past #216653, which added its converters at the same spot in
`ExpandOps.cpp`; the resolution is both blocks in sequence. `check-mlir` is
green on the new head.
