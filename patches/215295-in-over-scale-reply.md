# Issue #215295 — 接受 krzysz00 的 `in / scale` 裁決，並請 tgymnich 表態

送出對象：issue #215295 comment
前提：krzysz00 2026-08-17 18:07 UTC 引 CDNA5 ISA §7.12.6 / §7.6.3 / §15.14，
裁定 `arith.scaling_truncf => in / scale`。這**推翻** tgymnich 2026-08-13 在
#215123 給的答案（scaling ops 取 scale 的 exponent，依 OCP MXFP 規格）。

寫作要點：
- 不寫「你們兩個吵架」，寫「兩個相反的答案都在紀錄上，下游全部取決於哪個是正解」
- 每一條指控都要有檔案:行號，且是實查過的
- 結尾收成「我可以接手寫，順序是這樣，對嗎」

---

Thanks -- §7.12.6 and §7.6.3 are the piece I was missing. The argument I was
weighing was "OCP defines an MX scale as `E8M0`, so the op takes an exponent",
and shipping hardware that consumes an `f8E5M3` scale is exactly the case that
argument does not reach. Taking `in / scale`.

@tgymnich this reverses the answer you gave on #215123 on 2026-08-13, that the
scaling ops can be assumed to take the scale's exponent per the OCP spec. I would
rather have that said out loud than left implicit: two contradicting answers are
on the record, and everything below depends on which one is canonical. If you
still read it the other way, this is the moment.

Under `in / scale`, this is what the tree does today. All of it is independent of
the `arith.truncf` to `f8E8M0FNU` question, which stays separate.

| location | today | consequence under `in / scale` |
|---|---|---|
| `ExpandOps.cpp:674`, `:716` | a scale whose element type is 16 bits or wider is `arith.truncf`'d to `f8E8M0FNU` first; the comment says "allow implicit exponent extraction from 16/32 bits floats" | the expansion computes `in / 2^round(log2 scale)`. This is a wrong value, not a wrong rounding mode: an `f16` scale of `3.0` becomes a power of two before it is ever used |
| `ExpandOps.cpp:682`, `:723` | an 8-bit scale that is not `f8E8M0FNU` -- `f8E5M3FNU` -- fails to match, so there is no generic expansion for it at all | the case you want to expose is the one case that cannot be lowered without a target |
| `ArithOps.td:1480`, `:1672` | the op descriptions spell the lowering out as `%0 = arith.truncf %1 : f32 to f8E8M0FNU` followed by `extf` | the documented semantics state the exponent-only reading. This is a docs change too, not only a code fix |
| `ArithToAMDGPU.cpp:592` | any scale type is `extf`/`truncf`'d to `f32` and handed to `amdgpu::PackedScaledTruncOp` (gated on gfx950) | if `V_CVT_SCALEF32_*` reads only the exponent bits of that `f32`, as you said earlier, then this path also silently drops the mantissa of a non-power-of-two scale. §15.14 presumably settles it, and I would rather have it from you than infer it |

So under this reading the mantissa of a general scale is dropped on both paths
today, one in the IR and one in the hardware, and the `f8E5M3FNU` case has no
generic path at all.

What I would like to write, in this order:

1. `ScalingExtFOpConverter` / `ScalingTruncFOpConverter` multiply and divide by
   the scale value itself, with the existing `f8E8M0FNU` shape kept as the fast
   path for the type that is already exact. `f8E5M3FNU` scales then expand
   instead of failing to legalize.
2. `ArithOps.td` descriptions updated to say `in * scale` / `in / scale`, so the
   next person does not have to read this thread.
3. #215123's folder widened to any scale type, which is what @tgymnich asked for
   there. It deliberately folds only `f8E8M0FNU` scales today, precisely so it
   would not settle this question, so nothing already reviewed has to be redone.

Does that order work, and is step 1 something you want in `arith` or would you
rather the generic expansion keep rejecting what it cannot do exactly?

---

Unrelated, while you are both here: #215696 has an approval from @kuhar since
2026-08-14 and he asked for a second pair of eyes. It is green and unchanged
since. If neither of you has time, saying so is also useful -- I have no commit
access and would otherwise keep waiting.
