# 轉置的 `vector.transfer_write` → `gpu.subgroup_mma_store_matrix ... transpose`

**檔案**：`mlir/lib/Conversion/VectorToGPU/VectorToGPU.cpp`（`transferWriteSupportsMMAMatrixType`、`convertTransferWriteOp`）
**測試**：`mlir/test/Conversion/VectorToGPU/vector-to-mma-ops.mlir`
**開工**：2026-09-04

---

## 一句話

`convert-vector-to-gpu` 的 load 側 2026-02 起就會把 permutation map 第一個結果是最內層維度的
`transfer_read` 轉成 `subgroup_mma_load_matrix ... transpose`；store 側一直拒收同樣形狀的
`transfer_write`，理由是一行 TODO：「等 GPU dialect 加上 transpose 屬性」。
那個屬性早就在了，NVVM 和 SPIR-V 兩個後端也都會讀。這個 patch 讓 store 側跟 load 側走一樣的判斷，並把屬性設上去。

---

## 為什麼是「對的」——語意對齊

要能答的是：**transfer_write 的轉置 map 和 store op 的 `transpose` 是同一件事嗎？**

### `vector.transfer_write` 的 permutation map
map 的第 i 個結果 = vector 第 i 維走的是 memref 哪一維。
- `(d0, d1) -> (d0, d1)`：`vector[i][j]` 寫到 `memref[i][j]`。
- `(d0, d1) -> (d1, d0)`：vector 第 0 維走 memref 的 d1，第 1 維走 d0，所以 `vector[i][j]` 寫到 `memref[j][i]`。
  位址 = `base + j * stride[0] + i`。

### `gpu.subgroup_mma_store_matrix` 的 `transpose`
- NVVM：`WmmaOpsToNvvm.cpp:172` 有 `transpose` 就用 `MMALayout::col`。column-major 的意思是矩陣元素 `(i, j)` 放在 `base + j * ld + i`。
- SPIR-V：`WmmaOpsToSPIRV.cpp:385` 有 `transpose` 就用 `CooperativeMatrixLayoutKHR::ColumnMajor`，同一個定義。

兩邊都是「`(i, j)` 放在 `base + j * ld + i`」，和 `transfer_write` 的 `(d1, d0)` 完全一樣，
只要 `ld` = memref 第 0 維（也就是 map 裡最外層那個 dim）的 stride。

### `leadDimension` 怎麼來
`getStaticallyKnownRowStride` 取 map 兩個結果裡**位置最小的 dim** 的 stride。
- `(d0, d1) -> (d1, d0)` on `memref<5x3>`：min dim = d0，stride = 3。
- `(d0, d1, d2) -> (d2, d0)` on `memref<5x7x3>`：min dim = d0，stride = 21。
- `(d0, d1, d2) -> (d2, d1)` on `memref<2x5x3>`：min dim = d1，stride = 3。

這個 helper 是 read 側 2026-02 重寫的，它已經不管 map 是不是轉置，只看 dim 位置。
所以 write 側**不用動它**，這也是為什麼 patch 只有十行。

---

## 改了什麼

1. `transferWriteSupportsMMAMatrixType`：
   - 舊：`permutationMap.getResult(1) == innerDim`（只收「第二個結果是最內層」）。
   - 新：`llvm::is_contained(permutationMap.getResults(), innerDim)`（任一個結果是最內層），和 read 側同一行。
   - broadcast（常數 0）在前面已經被 `stride == 0` 擋掉，transfer_write 的 verifier 本來也不准 broadcast。
2. `convertTransferWriteOp`：`isTranspose = isFirstResultLastMapDimension(map)`，
   `transpose` 屬性照 read 側的寫法 `isTranspose ? rewriter.getUnitAttr() : UnitAttr()`。

### 為什麼 `isFirstResultLastMapDimension` 可以直接重用
它的註解說：「在只收『最內層維度恰好是兩個結果之一』的 context 裡，看第一個結果是不是最內層就足以判斷是否轉置。」
write 側改成 `is_contained` 之後，就正好是這種 context。

### 什麼還是不轉
- map 沒有包含最內層維度，例如 `(d0, d1, d2) -> (d1, d0)`：`is_contained` 失敗，整條鏈不轉（測試 `no_convert_write_transpose_not_last_dim`）。
  這和 read 側 `no_convert_read_transpose_not_last_dim` 對稱。
- mask、out-of-bounds、非 2-D vector、動態 stride：前面的檢查沒動。
- mma.sync 路徑（`useNvGpu`）走 `nvgpu::canLowerToWarpMatrixOperation`，這個 patch 碰不到它。

---

## 測試

鏡射 read 側 `18ecdbfe6c74` 加的四個：

| 測試 | map | memref | 期望 |
|---|---|---|---|
| `write_transpose` | `(d1, d0)` | `5x3` | `leadDimension 3 transpose` |
| `write_transpose_with_strides_3d` | `(d2, d0)` / `(d2, d1)` | `5x7x3` / `2x5x3` | `21` / `3` |
| `write_transpose_with_strides_4d` | `(d3, d0)` / `(d3, d1)` | `5x7x11x3` / `2x5x11x3` | `231` / `33` |
| `no_convert_write_transpose_not_last_dim` | `(d1, d0)` on 3-D | `2x2x2` | `CHECK-NOT: gpu` |

原本的 `no_convert_write_transpose`（負面測試）被 `write_transpose` 取代。

本機沒有 GPU，所以沒有跑 integration。可以做的驗證：把轉出來的 `gpu.subgroup_mma_store_matrix ... transpose`
再丟過 `-convert-gpu-to-nvvm`，看 `nvvm.wmma.store` 帶 `layout = #nvvm.mma_layout<col>`，證明屬性有一路流到後端。

---

## Reviewer 可能問

- **「為什麼之前不做？」** TODO 寫的是等屬性，屬性和兩個後端的支援都早於 read 側的重寫；read 側作者（mplatings）2026-02 只做了 read。
- **「stride 對嗎？」** 見上面三個例子，和 read 側同一個 helper、同一組數字（21 / 3 / 231 / 33）。
- **「有沒有可能 map 兩個結果都不含最內層卻通過？」** 不會，`is_contained` 就是擋這個。
- **「SPIR-V 那邊 ColumnMajor 對 store 的定義和 load 一樣嗎？」** 同一個 enum、同一個 layout 參數，`WmmaOpsToSPIRV.cpp:353`（load）和 `:385`（store）寫法一模一樣。
