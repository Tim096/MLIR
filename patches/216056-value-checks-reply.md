# #216056 回覆稿（2026-08-17）

新 head：`aa2025befe32`（force-push，只差 `APFloatTest.cpp`）。

---

## 1. inline reply → comment `3788955957`（`APFloatTest.cpp`，負值那段）

Done. Every conversion in the test now asserts the value it produced, and the
loop is split so that each case can state its own expectation.

For `-2.0` into either format the magnitude is exact, so the sign is the whole
of what is being reported: the result asserts `isNegative()` and
`convertToDouble() == -2.0`.

Zero moved out of the loop, because the two formats answer differently:
`Float8E8M0FNU` has no zero and substitutes 2^-127 for either sign
(`isSmallestNormalized()`, bit pattern `0x00`), while `Float8E5M3FNU` does have
one and keeps `-0.0` as `-0.0`, reporting only the sign.

I used `convertToDouble()` rather than `bitcastToAPInt()` for the signed cases:
these formats have no sign bit, so the encoding cannot show the sign that was
carried through, which is the thing under test.

---

## 2. inline reply → comment `3788956195`（`APFloatTest.cpp`，exact 那段）

Same here: the exact case now asserts `convertToDouble() == 2.0` next to
`isNegative()` being false, so it pins that nothing but the status differs
between it and the case above.

---

## 3. top-level 留言（請求代 merge）

Thanks both for the reviews. The requested value checks are in, force-pushed as
`aa2025befe32`; the only difference from the version you approved is the
`ConvertLosesUnrepresentableSignAndZero` test.

`ADTTests` is 2188 passed / 0 failed and `git clang-format` is clean. With the
new `convert` checks reverted the test fails, so it still pins the fix rather
than the current behaviour.

I do not have commit access -- @matthias-springer @tgymnich, could one of you
land this? The author line is `Hung-Kuan Tseng <tseng.tim096@gmail.com>`, the
same person as the `曾鈜寬 Tseng Hung Kuan <P76091014@gs.ncku.edu.tw>` on my
first two commits.
