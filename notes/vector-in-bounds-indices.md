# `in_bounds` 推導要看索引：`createReadOrMaskedRead` / `createWriteOrMaskedWrite`

**檔案**：`mlir/lib/Dialect/Vector/Utils/VectorUtils.cpp`（`computeInBoundsFromPermutationMap`、新 helper `isKnownMultipleOf`）、`VectorUtils.h` 註解
**測試**：`mlir/test/Dialect/Affine/SuperVectorize/vectorize_1d_inbounds.mlir`（新）、`vectorize_affine_apply.mlir`（改一行）
**開工**：2026-09-04（候選清單第 3 名）

---

## 一句話

`affine-super-vectorize` 產生 `transfer_read`／`transfer_write` 時，只要 memref 那一維是靜態且能被向量寬整除，就標 `in_bounds = true`，
完全不看索引。索引有偏移（`%A[%i + 1]`）或迴圈下界沒對齊（`4 to 16`）時，最後一個向量會超出 memref，
而 `in_bounds = true` 讓 `-convert-vector-to-llvm` 直接發無遮罩的 `llvm.load`。這個 patch 補上「索引是向量寬的倍數」這個條件。

---

## 為什麼原本的判斷「差一個條件」——推導

設 memref 那一維大小 D、向量寬 V、某次迭代的索引 idx。要 `in_bounds = true` 必須 `0 <= idx` 且 `idx + V <= D`。

- 原判斷只有 `D % V == 0`。
- 向量迴圈的 IV 只取原純量迴圈 IV 的子集合（lb, lb+V, ...），所以 idx 一定是純量程式用過的索引，純量程式合法 ⟹ `0 <= idx < D`。
- 從 `0 <= idx < D` 加 `D % V == 0`，**還需要 `idx ≡ 0 (mod V)`** 才推得出 `idx + V <= D`。
  反例：D = 16、V = 8、idx = 9 → 9 + 8 = 17 > 16。

所以缺的條件就是「idx 是 V 的倍數」，patch 加的就是這個，不多不少。

### 為什麼不是「trip count 要整除」的契約問題
`SuperVectorize.cpp` 的設計說明講「always full tile」，靠 `vector.transfer` 的越界語意處理尾端；
reduction 路徑的 `createMask` 也明寫是給「unaligned loops 的最後一次迭代」用的。
所以 trip count 不整除是在契約內的，`in_bounds = false` 就是尾端的保護機制。#201180 標 `true` 拿掉了保護，
但只在 idx 對齊時是安全的。

---

## 三個 repro（都在 scratchpad `inb-repro.mlir`，V = 8，memref<16xf32>）

| 函式 | 迴圈與索引 | 向量讀到的元素 | 修前 | 修後 |
|---|---|---|---|---|
| `@offset` | `0 to 15`，`%A[%i + 1]` | 第二次 9..16，**16 越界** | `in_bounds = [true]`，`llvm.load` | 無屬性，`llvm.intr.masked.load` |
| `@lb` | `4 to 16`，`%A[%i]` | 第二次 12..19，**越界** | `in_bounds = [true]` | 無屬性 |
| `@ub_short` | `0 to 12`，`%A[%i]` | 第二次 8..15，在界內 | `in_bounds = [true]` | 不變，仍 `true` |

`@ub_short` 是對照組：trip count 不整除但 idx 對齊，讀超過 trip count 但沒超過 buffer，`true` 是對的。

---

## 改了什麼

1. `computeInBoundsFromPermutationMap` 多收 `ValueRange indices`，`AffineDimExpr` 分支多一個 `isKnownMultipleOf(indices[memDim], vectorSize)`。
2. 新 helper `isKnownMultipleOf(Value, factor)`：
   - 常數：`c % factor == 0`。
   - `affine.for` IV：`step % factor == 0` 且下界 map 每個結果都是倍數。
   - `affine.apply`：map 結果是倍數。
   - 其他：false（保守）。
   map 的判斷是把「已知是倍數」的 operand 換成 `factor * d`，再用現成的 `AffineExpr::isMultipleOf`。
   遞迴走下界的 operand，所以 tiling 後 `affine.for %ii = #map(%i)`、`%i` 是 `step 16` 的外層 IV 也認得出來。
3. read／write 兩條路徑把 indices 的初始化搬到 in_bounds 計算之前（之前是先算 in_bounds 再填 indices）。
4. map 分支的兩行 FIXME 拿掉；**無 map 分支的 FIXME 留著**（見下）。

### 為什麼用語法走訪而不是 `ValueBoundsConstraintSet`
- 要證的是整除性（對齊），不是上下界；value bounds 不算整除。
- #215340 討論串裡 banach-space 對「在 create 時做分析」的顧慮是成本；這裡是 O(巢狀深度) 的走訪，沒有 constraint set。
- `AffineOps.cpp:659` 的 static `getLargestKnownDivisor` 做的是同一件事但只看一層（IV 的下界 map 不遞迴 operand），
  tiled matmul 的 `#map(%i)` 下界會算成 1，會讓 #201180 特地加的 `MATMUL-COUNT-3` 測試退化，所以自己寫一個會遞迴的。

### 為什麼無 map 分支的 FIXME 留著
樹裡走無 map 分支的呼叫者：Linalg pack／unpack（索引全零）、`insert_slice` 向量化（write 索引 = slice offset，
`tensor.insert_slice` 的 verifier `verifyInBoundsSlice` 已保證 offset + size <= dest）。沒有會出錯的呼叫者，就不動。

---

## 測試

`vectorize_1d_inbounds.mlir`（V = 8）：

| 函式 | 形狀 | 期望 |
|---|---|---|
| `offset_index` | `0 to 15`，`%A[%i + 1]`、`%B[%i + 1]` | 兩個都無 `in_bounds` |
| `aligned_offset_index` | `0 to 8`，`%A[%i + 8]` | `true`（偏移是 V 的倍數） |
| `unaligned_lower_bound` | `4 to 16` | 無 |
| `aligned_lower_bound` | `8 to 16` | `true` |
| `lower_bound_from_outer_loop` | `0 to 32 step 16` 包 `#map(%i) to #map1(%i)`，memref<32> | `true`（tiling 形狀） |
| `unaligned_lower_bound_from_outer_loop` | 外層 `step 12`，memref<24> | 無（24 % 8 == 0 但 12 不是 8 的倍數） |

`vectorize_affine_apply.mlir` 的 `vec_affine_apply_2`：索引 `d0 mod 16 + 1`，`%arg4 = 8` 時讀 9..16，原 CHECK 期望 `true` 是錯的，改成無屬性。
同檔的 `vec_affine_apply`（`d0 mod 16`）仍是 `true`：`(d0 * 8) mod 16` 的 `isMultipleOf(8)` 走 gcd(8, 16) = 8。

回歸：`mlir/test/Dialect/{Affine,Linalg,Vector}` 348 個全過；`vectorize_2d_inbounds.mlir` 的 tiled matmul 仍是 4 個 `true`（沒退化）。

---

## 撞車與脈絡（reviewer 會問）

- **#215340（dhairyashilRG，opt-in pass `-vector-infer-in-bounds`）**：那個 pass 只會把 `false` 變 `true`，不會修錯誤的 `true`；
  錯誤的 `true` 只能在產生端修，兩者不重疊。dhairyashilRG 在 08-19 自己說「刪 FIXME 需要在 create 時做 index-aware 計算」，
  但沒認領。
- **#219681（同一人，folder 負索引）**：修的是 `VectorOps.cpp` 的 folder，不是這裡。
- **Discourse RFC「要不要移除 `in_bounds`」（08-25 起，9 篇）**：dcaballe 說 `in_bounds` 推導「quite load bearing」，短期不會拆。
  就算之後拆掉，錯的 `true` 在拆掉前都是錯的。
- **#201180 / #202766（FedericoBruzzone）**：這個判斷是 2026-06 他加的，FIXME 也是他放的，是最該看這個 patch 的人。
- **「為什麼 `vec_affine_apply_2` 的純量程式本來就越界？」** 對，`%arg4 mod 16 + 1` 在 `%arg4 = 15` 時是 16。
  但這不影響結論：patch 是讓判斷在**任何**輸入下都不多說，測試輸入合不合法是另一回事。
