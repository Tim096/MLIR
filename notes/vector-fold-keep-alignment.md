# 六個 vector 記憶體 op 的 folder 重建時丟掉 `alignment`

**檔案**：`mlir/lib/Dialect/Vector/IR/VectorOps.cpp`（`MaskedLoadFolder`／`MaskedStoreFolder`／`FoldContiguousGather`／`FoldContiguousScatter`／`ExpandLoadFolder`／`CompressStoreFolder`）
**測試**：`mlir/test/Dialect/Vector/vector-mem-transforms.mlir`（四個 mask folder）、`canonicalize.mlir`（gather／scatter）
**PR**：[#221317](https://github.com/llvm/llvm-project/pull/221317)，分支 `vector-fold-keep-alignment`，head `1b2aca62fe7e`，+98/−8
**開工**：2026-09-05

---

## 一句話

這六個 folder 都是 canonicalization pattern：mask 全 true 時把 `maskedload`／`maskedstore`／`expandload`／`compressstore`
折成 `vector.load`／`store`，index 是 `[0, 1, 2, ...]` 時把 `gather`／`scatter` 折成 `maskedload`／`maskedstore`。
重建只傳 base／indices／mask／value，`alignment` 全掉。這六個 folder 都比 `alignment` 屬性早
（`vector.load/store` 的 alignment 是 #144344，2025-07；masked 系列是 #151690，2025-08）。

## 為什麼重要

這是 `-canonicalize`，幾乎每條 pipeline 都跑。之前四個「屬性丟失」的 PR 都是特定 pass，這個影響面最大。
IREE 等下游把 alignment 標上去之後，只要 mask 被折掉，LLVM 層就退回元素對齊。

## 為什麼轉發是對的

要能答的是：**折疊後的 op 存取的位址和原本一樣嗎？**
- 四個 mask folder：base 與 indices 原封不動，只是拿掉 mask（mask 全 true 時語意等價）。同位址、同寬度。
- gather／scatter 的 contiguous folder：前提 `isZeroBasedContiguousSeq(indices)`，即 index 向量是 `[0, 1, ..., n-1]`。
  折成 `maskedload %base[%offsets]`，起點就是 gather 的第 0 個元素。gather 的 `alignment` 文件寫「the operation must
  access memory at an address aligned to this boundary」，第 0 個元素的位址是它存取的位址之一，所以對齊成立。
- `nontemporal`：來源 op 沒有這個屬性，新 op 用預設 `false`，沒有捏造任何東西。

## 改了什麼

六個 `replaceOpWithNewOp` 各加一個參數：`vector.load/store` 用 `/*nontemporal=*/false, op.getMaybeAlign()`（custom builder），
`maskedload/store` 用 `op.getMaybeAlign()`（custom builder 最後一個參數）。
八個 op 都實作 `AlignmentAttrOpInterface`，所以 `getMaybeAlign()` 一律可用。和 #221308 同寫法。

## 驗證

| 輸入 | 修前 | 修後 |
|---|---|---|
| `maskedload ... alignment = 64`，mask 全 true | `vector.load %base[%c0]` | `vector.load %base[%c0] alignment = 64` |
| `maskedstore`／`expandload`／`compressstore` 同上 | 同 | 同 |
| `gather %base[%c0][0..15] alignment = 64` | `maskedload`，無 alignment | `maskedload ... alignment = 64` |
| `scatter` 同上 | `maskedstore`，無 alignment | `maskedstore ... alignment = 64` |

- 六個新測試，各鏡射既有的 `*_all_true`／`@contiguous_*` 測試，只加 `alignment = 64`。
- check-mlir 4588／16 同基準（canonicalize 動到全樹，所以跑完整套）。

## Reviewer 可能問

- **「AllFalse 分支呢？」** AllFalse 直接換成 pass-through 或刪掉 op，沒有記憶體存取，沒東西可轉。
- **「gather 的 alignment 是指每個元素還是第一個？」** 文件只說「the operation must access memory at an address aligned」，
  不管哪種解讀，第 0 個元素的位址都在集合裡，所以 maskedload 的起點對齊成立。
- **「為什麼放 canonicalize.mlir 和 vector-mem-transforms.mlir 兩個檔？」** 跟既有測試放一起：mask folder 的測試在
  `vector-mem-transforms.mlir`（`-test-vector-to-vector-lowering`），contiguous folder 的在 `canonicalize.mlir`。
