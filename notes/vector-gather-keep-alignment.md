# #221382：gather 的 `alignment` 在 unroll 與 `-lower-vector-mask` 被丟掉

分支 `vector-gather-keep-alignment`，base `f6a369fa4a57`，head `72a673f8a046`，4 個檔案 +29/−2。

## 兩處

| 位置 | pattern | 重建方式 |
|---|---|---|
| `Vector/VectorUnroll.cpp:694` | `UnrollGatherPattern` | 同 base／offsets，只切 index／mask／passthru 成 tile |
| `Vector/LowerVectorMask.cpp:270` | `MaskedGatherOpPattern` | `vector.mask { gather }` 拆成裸 gather，mask 換成 region 的 mask，passthru 換成 region 的（沒有就補零） |

兩處都是 `gatherOp.getMaybeAlign()` 補進 builder 最後一個參數。`LowerVectorGather.cpp:72` 的 unroll 早就有轉，這兩處是漏掉的。

## 為什麼 bufferization 那處不算

`BufferizableOpInterfaceImpl.cpp` 的 gather／scatter 也重建 op，但 verifier 說 `alignment is only supported for memref bases, not tensor bases`——tensor 上根本帶不了這個屬性，所以沒東西可轉。我一開始寫了測試才被 verifier 擋下來，PR body 有寫這句，reviewer 不會再問。

## gather 的 alignment 語意（順便解決反向疑慮）

`VectorOps.td:2171`：「The operation must access memory at an address aligned to this boundary」。gather 每個元素位址不同，這句只能解讀成每個元素都對齊——和 LLVM `masked.gather` 的 alignment 是 per-element 一致。所以 `LowerVectorGather.cpp:297` 把 gather 的 alignment 抄到每一個 scalar load 上是對的，不是「多抄」，掃描筆記裡那條反向疑慮撤掉。

## 測試

- `vector-transfer-unroll.mlir` `@vector_gather_unroll_alignment`：`2x4` 切成兩個 `2x2`，兩個 gather 都要有 `alignment = 8`，後面 `ALL-NOT: vector.gather`。
- `lower-vector-mask.mlir` `@vector_gather_alignment`：memref base。passthru 是 pattern 補的零常數（不是內層 gather 的），CHECK 用 `%{{.*}}`。

## 驗證

沒 patch 時兩個新測試都失敗（輸出沒有 alignment），patch 後 `Dialect/Vector` 101 個全過。

## 答辯

- 為什麼安全：base 與 offsets 完全沒動，index 向量只是切片，每個元素的位址集合是原來的子集合。
- 為什麼 unroll 不用重算：gather 沒有「起點加 offset」這件事，每個元素位址由 index 向量決定，切片不改任何元素的位址。
