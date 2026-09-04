# `amdgpu-maskedload-to-load` 丟掉 `alignment`

**檔案**：`mlir/lib/Dialect/AMDGPU/Transforms/MaskedloadToLoad.cpp`（`createVectorLoadForMaskedLoad` 第 56 行、`FullMaskedStoreToConditionalStore` 第 227 行）
**測試**：`mlir/test/Dialect/AMDGPU/maskedload-to-load.mlir`
**開工**：2026-09-05
**分支**：`amdgpu-maskedload-keep-alignment`，commit `8378fb4c6fbd`，base `f6a369fa4a57`

---

## 一句話

這個 pass 把 `vector.maskedload` 改寫成 `vector.load`（＋ `arith.select` 或 `scf.if`），把全 mask 的 `vector.maskedstore` 改寫成 `scf.if { vector.store }`。
重建時只傳 base 與 indices，`alignment` 沒帶過去，所以 `convert-vector-to-llvm` 只能退回 element type 的對齊。
**這是效能損失，不是錯誤結果**：f16 向量從 `align 16` 變 `align 2`。

---

## 為什麼 alignment 可以直接轉傳

要能答的是：**改寫後的存取位址和寬度有沒有變？**
- 三個重建點都用 `maskedOp.getBase()`、`maskedOp.getIndices()` 原樣，vector type 也一樣。
- 第 110–130 行算的線性化 index 只餵給 `scf.if` 的條件（判斷是否會越界），存取本身沒有偏移、沒有加寬。
- `vector.load` 與 `vector.maskedload` 的 `alignment` 在 `VectorOps.td` 裡定義一字不差（「存取位址必須對齊到此邊界，違反是 UB」）。同位址、同定義，屬性當然成立。
- `then` 分支是 `builder.clone(*maskedOp)`，本來就保留屬性；只有 `else`／fast path／store 三處掉。

## 為什麼是 `/*nontemporal=*/false, getMaybeAlign()`
- `vector.load`／`vector.store` 的 ODS builder 簽名是 `(..., bool nontemporal = false, llvm::MaybeAlign alignment = {})`。
- `vector.maskedload`／`maskedstore` **沒有** `nontemporal`（ODS 只有 `alignment`），所以 `false` 是既有預設，不是行為改變。
- 兩個 masked op 都實作 `AlignmentAttrOpInterface`，`getMaybeAlign()` 回傳的正是 builder 要的型別。
- in-tree 同款寫法：`AffineToStandard.cpp:369`／`:417`／`:505`／`:528`。

## 為什麼之前沒帶
時間差：pass 2025-07-02 寫的（Zhuoran Yin，#146705；store 部分 Kunwar Grover，#146748），`vector.load/store` 的 `alignment` 2025-07-17（#144344）才加，masked 版 2025-08-08（#151690）。

---

## 驗證

| 項目 | 結果 |
|---|---|
| 重現（舊 binary） | 四個案例改寫後 `alignment` 全掉，只剩 clone 那個 `then` 分支有 |
| 重現（新 binary） | 五處 `alignment = 16` 都在 |
| LLVM 層 | `llvm.load ... {alignment = 16}` vs 沒修時 `{alignment = 2}`；fat_raw_buffer 走 `-convert-gpu-to-rocdl=chipset=gfx942` 也一樣 |
| lit | `Dialect/AMDGPU` 10 個全過，新 3 個 CHECK 在舊 binary 上會失敗 |
| clang-format | 乾淨 |

---

## Reviewer 可能問

- **「in-tree 誰用這個 pass？」** 只有它自己的 lit。使用者是 IREE（作者都是 AMD／IREE 的人），fat buffer 路徑正是需要對齊資訊的地方。誠實講。
- **「`TransferReadToLoad.cpp` 要不要一起？」** 那個 pass 從 `vector.transfer_read` 建 `vector.maskedload`，transfer_read 沒有 `alignment` 可傳，沒東西可帶。
- **「越界那個 `else` 分支？」** fat buffer 的 OOB 語意由硬體處理，alignment 與它正交。
- **Title 用 `[mlir][AMDGPU]`**：該目錄近 30 個 commit 9 個大寫 4 個小寫，跟多數。
- 可能的 reviewer：krzysz00（AMDGPU owner）、Groverkss、kuhar。
