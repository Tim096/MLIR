# `FoldArithExtIntoContractionOp` 兩側 ext 來源型別要一樣

**檔案**：`mlir/lib/Dialect/Vector/Transforms/VectorTransforms.cpp`（`FoldArithExtIntoContractionOp`）
**測試**：`mlir/test/Dialect/Vector/fold-arith-extf-into-vector-contract.mlir`
**PR**：[#221298](https://github.com/llvm/llvm-project/pull/221298)，2026-09-05 送出
**開工**：2026-09-05

---

## 一句話

這個 pattern 把 `vector.contract` 兩個 operand 上的 `arith.extf`／`arith.extsi` 折進 contract，
讓 tensor core 可以直接吃 `mma.sync.f32.f16.f16.f32` 這種混合精度指令。
它只檢查兩邊「都是同一種 ext op」，沒檢查兩個 ext **從什麼型別**延伸出來。
`extsi i8→i32` 配 `extsi i16→i32` 餵進去，改寫後的 contract 直接拿 i8 和 i16 當 lhs／rhs，過不了 verifier：

```
'vector.contract' op failed to verify that lhs and rhs have same element type
```

`extf f16→f32` 配 `extf bf16→f32` 一樣。修法是比較兩個來源的 element type，不一樣就 `notifyMatchFailure`。

---

## 為什麼是「對的」

要能答的是：**為什麼只比 element type，不比整個 vector type？**

- `vector.contract` 的 verifier 對 lhs／rhs 的要求是 `TCopVTEtIsSameAs<0, 1>`（`VectorOps.td:52`）：只有 element type 要一樣。
  shape 本來就可以不同（lhs `<M×K>`、rhs `<K×N>`），scalable 也可以只有一邊有（既有測試 `fold_arith_extf_into_contract_scalable`）。
- 所以用 `getElementTypeOrSelf` 比 element type 就恰好等於 verifier 的條件，多比 shape 會誤擋合法案例。

**為什麼 ext 的結果型別不用比？** ext 的結果就是 contract 原本的 operand，原本的 contract 已經過了 verifier，兩邊結果型別一定相同。

**為什麼混 `extsi`／`extui` 不用管？** pattern 是 template，`ExtOp` 固定一種，`getDefiningOp<ExtOp>()` 另一種直接回 null，本來就不匹配。
`extsi i8` 配 `extui i8` 這種語意不同的組合也因此不會被折——這是既有行為，不是這個 patch 的範圍。

**`lhsDefOp.getIn()`**：`arith.extf`／`extsi` 都是 `Arith_CastOp`，operand 叫 `in`，`getIn()` 是 ODS 產生的 accessor。
原本程式用 `lhsDefOp->getOperand(0)`，兩者同一個值；比較那行用 `getIn()` 是為了讀起來知道在比什麼。

---

## 改了什麼

`VectorTransforms.cpp` 的 `matchAndRewrite`，在「兩邊都有 ext」的檢查之後、`replaceOpWithNewOp` 之前加：

```cpp
// The contraction requires lhs and rhs to have the same element type, so
// the two extensions must also start from the same one.
if (getElementTypeOrSelf(lhsDefOp.getIn().getType()) !=
    getElementTypeOrSelf(rhsDefOp.getIn().getType())) {
  return rewriter.notifyMatchFailure(
      contractOp, "lhs and rhs are extended from different element types");
}
```

8 行程式、47 行測試，沒有其他改動。

---

## 測試

| 測試 | 輸入 | 期望 |
|---|---|---|
| `no_fold_arith_extf_from_different_types` | `extf f16→f32` ＋ `extf bf16→f32` | 兩個 `arith.extf` 留著，contract 仍吃 `f32` |
| `no_fold_arith_extsi_from_different_types` | `extsi i8→i32` ＋ `extsi i16→i32` | 兩個 `arith.extsi` 留著，contract 仍吃 `i32` |

既有三個正向測試（f16／scalable f16／i8）不動。
`Dialect/Vector` ＋ `Conversion/VectorToGPU` ＋ `transform-op-vectorize` 105 個 lit 全過；check-mlir 4218 過／16 失敗，與基準同一組環境失敗。

---

## 誰會踩到

- `transform.apply_patterns.vector.fold_arith_extension`（`VectorTransformOps.cpp:58`）與 Linalg transform 的 vectorize 選項都會裝這組 pattern。
- 混合來源型別的 contract 在真實 pipeline 裡不常見，但 pattern 一旦命中就是 verifier 失敗、整個 pass 掛掉，不是靜默錯值。
- 修正後這種 contract 只是不折，走原本的 `f32`／`i32` 路徑，語意不變。

---

## Reviewer 可能問

- **「要不要順便支援混合來源？」** 不行，`vector.contract` 的 verifier 就不允許 lhs／rhs element type 不同，沒有合法的目標 IR。
- **「為什麼不在 verifier 那邊放寬？」** 混合精度 MMA 指令本來就要求 A／B 同型別（`mma.sync.f32.f16.f16.f32`），放寬 verifier 沒有對應的硬體語意。
- **「歷史」**：pattern 是 `9a795f0c59b1` 加的（只做 `extf`），#96593（raikonenfnu，MaheshRavishankar approve）把它 template 化成也吃 `extsi`，
  那次沒加來源型別的檢查。`3960ff6ca03b`（kuhar）只是 NFC 的建構子整理。
