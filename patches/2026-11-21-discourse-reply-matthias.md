# Discourse 文稿：回 matthias-springer 第 12、18 則（已貼，等版主審核）

貼到：<https://discourse.llvm.org/t/a-new-ub-assume-operation/92834>（回覆第 12 則）

狀態：**本人 2026-11-21 貼出，顯示 AWAITING APPROVAL，審核通過前別人看不到。** 下面是實際貼出的版本。前兩次貼的第一段 `>` 引用沒有變成引用框，刪掉後改成句內引用。

---

On "if we were able to infer an integer range that's not [-inf; +inf] [...] we can always interpret that as not poisoned": that does not hold for the example above. `%d = arith.addi %n, %c1 overflow<nuw>` gets `umin = 1`, which is not the full range, and it is poison for `%n = UINT_MAX`. The range is derived from the flag, so it means "in [1, UINT_MAX], or poison". The result of `ub.assume` is the same case. A narrow range and "not poison" are two separate facts.

> One solution could be to add attributes to these ops to indicate that there's no div-by-zero etc. [...] and then add a new pass that runs a range analysis and infers such attributes.

I like that, it keeps `getSpeculatability` cheap. The inference pass is then the one place that needs both facts: the divisor range excludes zero, and the divisor is not poison. For the second, one "may be poison" bit next to the range in the lattice would do: set by `ub.poison`, by `ub.assume`, and by ops whose flags can produce poison, and joined like the range.

With arguments allowed to be poison, that bit is set almost everywhere, so the pass needs a root that clears it. The `ub.assert` from your last post would be one: after `ub.assert(%d != 0)` the value is both non-zero and not poison. So I'd read the `divui` example as an argument for having both ops rather than for one over the other.

I'd assume the answer to (2), values loaded from memory, is also "yes" unless someone says otherwise.

---

## 查證紀錄

- 反例 11-21 重跑：`playground/licm-range/unsound-with-nuw.mlir`，`-int-range-optimizations` 在 `376f04dd8bdb` 仍回報 `umin = 1`。
- 「一個 may-be-poison bit」是提案，沒有 prototype；`IntegerValueRange` 目前只有 uninitialized／range 兩種狀態（沒有重新讀原始碼確認，文稿沒寫這句）。
- `ub.assert` 只存在於 matthias 第 18 則的提議，樹裡沒有。
- 沒寫 `freeze`：freeze 過的 poison 可以是 0，對除數範圍沒有幫助。
