# Discourse 文稿：範圍＋poison 與 speculation（未發）

貼到：<https://discourse.llvm.org/t/a-new-ub-assume-operation/92834>
（`ub.assume` 討論串。它違反時回傳 poison，並接到 `IntegerRangeAnalysis`，和這點直接相關。）

狀態：**草稿，尚未發出。** Discourse 要本人貼。

---

One constraint worth writing down before ranges start feeding more transforms: a range that holds "unless the value is poison" is enough to rewrite an op in place, but not to speculate it.

```mlir
%d = arith.addi %n, %c1 overflow<nuw> : i32
scf.for %i = %lb to %ub step %c1 {
  %q = arith.divui %x, %d : i32
  ...
}
```

`IntegerRangeAnalysis` reports `umin = 1` for `%d` (checked on `376f04dd8bdb`). That relies on `nuw`: with `%n = UINT_MAX`, `%d` is poison. If the loop runs zero times, the division is never executed. Hoisted, it divides by poison. The same applies to a range that comes from `ub.assume`, since a false predicate gives poison.

Nothing does this today. `getSpeculatability` of the division ops only looks at the op that defines the divisor, with unknown operands (#102494), and `ub.assume` in #242700 is handled inside the analysis, so that matcher does not see it. It becomes a problem as soon as the two are connected, which the division thread already suggested for removing the `remsi` runtime check and for LICM.

In-place uses are fine: if the divisor is poison the op is already UB where it stands. Speculation needs "in range" and "not poison".

As far as I can tell there is no way to ask the second question upstream: no `freeze`, and nothing like `isGuaranteedNotToBePoison`. Before writing one I'd need to know what we assume at the roots:

1. Can a function argument or a block argument be poison?
2. Can a value loaded from memory be poison?

If the answer to 1 is yes, as in LLVM without `noundef`, the analysis can prove very little without an attribute on arguments. I'd like to work on this, and can send a prototype once the roots are settled.

---

## 查證紀錄

- 反例：`playground/licm-range/unsound-with-nuw.mlir`，`-int-range-optimizations` 回報 `umin = 1`。
- `playground/licm-range/div-not-hoisted.mlir`：除數為 `maxsi(%n, 1)` 時 LICM 不搬；換成常數 7 會搬。
- 既有 matcher：`mlir/include/mlir/IR/Matchers.h` 的 `infer_int_range_op_binder`，把定義 op 的運算元全設成 max range。
- #242700 的 `ub.assume`：範圍在 `IntegerRangeAnalysis::visitOperation` 內特判，op 沒實作 `InferIntRangeInterface`（讀 diff，head `b6df45090607`，沒有 build）。
- `ub` dialect 目前只有 `poison`、`unreachable`；`mlir/docs` 沒有提到引數能否為 poison。
- LLVM 對照：`isSafeToSpeculativelyExecute` 對除法只認常數除數（憑記憶，沒有重新查 LLVM 原始碼，文稿裡沒寫這句）。
