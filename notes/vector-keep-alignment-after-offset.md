# #221385：索引會移的三個 pattern，alignment 要重算

分支 `vector-keep-alignment-after-offset`，base `f6a369fa4a57`，head `c2086dd854a5`，6 個檔案 +168/−6。第一個不是「照抄屬性」而是「算屬性」的 patch。

## 三處

| 位置 | pattern | 索引怎麼動 |
|---|---|---|
| `VectorTransforms.cpp:1298` | `ExtractOpFromLoad` | `vector.load` + `vector.extract [pos]` → 在 `indices[i] += pos` 的位置重建窄的 load（或 `memref.load`）；pos 可能是動態 SSA 值 |
| `VectorUnroll.cpp:740` | `UnrollLoadPattern` | 每個 tile 在 `StaticTileOffsetRange` 的靜態 offset 上重建，作用在尾端的 vecRank 個維度 |
| `VectorUnroll.cpp:783` | `UnrollStorePattern` | 同上 |

`nontemporal` 直接轉。`alignment` 不能：原本說「起點對齊 A」，新存取在起點加 D bytes 處，只能保證對齊 `commonAlignment(A, D)`＝A 與 D 的最大公因 2 冪（`llvm/Support/Alignment.h:199`，`MinAlign`）。D 算不出來就丟掉。

## helper：`vector::getAlignmentAfterOffset(MaybeAlign, MemRefType, ArrayRef<int64_t> offsets)`

放在 `Vector/Utils/VectorUtils.{h,cpp}`（兩個 .cpp 都在 `MLIRVectorTransforms`，都已連 `MLIRVectorUtils`）。

1. 沒有 alignment → 回空。
2. offsets 全零 → 原樣回（位址沒動）。
3. 元素型別不是 int/float 或不是整 byte（`index`、`memref<..xvector<..>>`、`i1`、`i4`）→ 回空：算不出 byte 數。
4. `getStridesAndOffset` 失敗（非 strided layout）→ 回空。
5. 每個非零 offset 對應的 stride 必須靜態，`memref<?x?xf32>` 的 identity layout 是 `[?, 1]`，只有最內維能算。
6. `byteOffset = |Σ offset_i × stride_i| × elemBytes`，回 `commonAlignment(A, byteOffset)`。

樹裡沒有任何地方用過 `commonAlignment`／`MinAlign`，這是第一個。ping 時主動說名字與位置可以討論。

## `ExtractOpFromLoad` 的細節

pos 是 `OpFoldResult`，`getConstantIntValue` 拿得到就填進 offsets，拿不到就標 `hasDynamicOffset`，alignment 整個丟掉但 `nontemporal` 照轉。offsets 向量是全 rank 長度、只填 `[rankOffset, rank − finalRank)` 那段，其餘零——helper 吃「尾端維度」所以直接傳全長。

## 測試（算給 reviewer 看的數字）

| 測試 | 設定 | 結果 |
|---|---|---|
| sink `@extract_load_scalar_attrs` | pos 0 | 16 與 nontemporal 都留 |
| sink `@..._non_zero_off_alignment` | `vector<4xf32>` align 16 取第 1 個 | 4 bytes → `alignment(4)` |
| sink `@..._dyn_off_alignment` | pos 動態 | 只剩 `nontemporal(true)` |
| sink `@..._vec_static_stride_alignment` | `memref<8x8xf32>` 取第 1 列 | 32 bytes → 16 保留 |
| sink `@..._vec_dynamic_stride_alignment` | `memref<?x?xf32>` 取第 1 列 | stride 動態 → 丟 |
| unroll load／store `@vector_..._2D_alignment` | `memref<4x4xf16>` align 16 切 2x2 | tile `[0,2]`＝4 bytes → 4；`[2,0]`＝16 bytes → 16；`[2,2]`＝20 bytes → 4 |

全樹 check-mlir 4588／16，與基準相同。

## 答辯

- 為什麼不乾脆丟掉：unroll 是 GPU／CPU pipeline 的常客，第一個 tile 與整列開頭的 tile 都保得住原對齊，丟掉等於把 `alignment` 這個屬性做成一次性的。
- 為什麼要 `|Σ|`：strided layout 允許負 stride（`hasNegativeStaticStride` 就在 MemRefUtils），對齊只看距離。
- 為什麼 stride 0 沒問題：Σ 得 0，`commonAlignment(A, 0) = A`，位址真的沒動。
- 為什麼 `index` 型別丟掉：byte 寬要 DataLayout，pattern 裡拿不到；`isSupportedMemSinkElementType` 明確放行 `index`，所以這條分支會走到。
