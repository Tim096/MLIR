# `tensor.insert_slice` 向量化：stride 與 rank-reducing 的前置條件

**檔案**：`mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp`（`vectorizeInsertSliceOpPrecondition`、`vectorizeAsInsertSliceOp`）
**測試**：`mlir/test/Dialect/Linalg/vectorization/{insert-slice,unsupported}.mlir`
**分支**：`linalg-insert-slice-vectorize-precondition`，base `08d499665a14`
**開工**：2026-09-05

---

## 一句話

`transform.structured.vectorize` 對 `tensor.insert_slice` 的做法是「整個 source 讀成一個 vector，
再用 minor identity map 寫到 dest 的 offset 位置」。這只在 stride 全是 1、而且 source 對到 dest
**最內層**那幾維時才等於 insert_slice 的語意。前置條件兩件事都沒檢查，所以：

| 輸入 | 產生的 IR | 結果 |
|---|---|---|
| `[2,4]` stride `[3,1]` 插進 `8x4` | `transfer_write` 到 `[0,0]`，`in_bounds=[true,true]` | 寫到第 0、1 列，正確是第 0、3 列 |
| `8x4` 插進 `8x1x4`，sizes `[8,1,4]` | `vector<8x4>` 寫到 dest 的 dim 1／2，`in_bounds=[false,true]` | dim 1 只有 1 個元素，只留 source 第 0 列 |
| 同上，offset `[0,3,0]` | 寫到 `dst[0][3+i][j]` | 正確是 `dst[i][3][j]`，純錯值 |

修法是最小的：前置條件加兩個 bail，不改產生的 IR。

---

## 為什麼是「對的」——條件怎麼推

要能答的是：**什麼時候「minor identity 寫到 offset」等於 insert_slice？**

insert_slice 的語意：source 的每個元素 `(i_0..i_{r-1})` 放到 dest 的
`offset + stride * idx`，其中 idx 是把 source 的下標塞進「沒被 drop 的 dest 維度」。

`transfer_write` 用 minor identity map：vector 的第 k 維走 dest 的第 `rankDiff + k` 維，
位址 = `offset + idx`（stride 固定 1）。

兩者相等 ⇔
1. stride 全是 1（`hasUnitStride()`）。
2. 沒被 drop 的 dest 維度正好是最後 r 維 ⇔ 被 drop 的維度全是最前面 `rankDiff` 個。

### `getDroppedDims()` 為什麼可以直接用
`TensorOps.cpp:163` 的實作是**從尾端往前**配對：size 不是靜態 1 就保留、size 是 1 而 source 對應維也是 1 也保留，
其餘 drop。所以「能對到尾端就對到尾端」，判斷 `droppedDims.find_last() < rankDiff` 正好是條件 2。

例子（reviewer 可能拿來問）：
- sizes `[1,1,8,4]`、source `<1x8x4>`：從後配 4、8、1 都保留，剩下的 dim 0 被 drop → 接受。
  寫 `vector<1x8x4>` 到 dest 的 dim 1..3，因為 size-1 維怎麼放都一樣，結果正確。
- sizes `[1,8,1,4]`、source `<1x8x4>`：從後配 4 保留，size 1 對 source 的 8 → drop dim 2 → 拒絕。
  這個若不拒絕，`vector<1x8x4>` 會被寫到 dest 的 `8x1x4`，dim 1 出界。
- 既有測試 `1x2x3` 插進 `9x8x7x1x2x3`，sizes `[1,1,1,1,2,3]`：drop {0,1,2}，rankDiff 3 → 接受，行為不變。

### 為什麼不做「完整修法」
完整修法是用 dropped dims 建 permutation map 交給 `createWriteOrMaskedWrite`。但那個 helper 的
mask 尺寸計算（`VectorUtils.cpp:597` 起）也假設 vector 對到 dest 尾端，要一起改；而且
#221268 正在動同一個 helper 的 `in_bounds` 推導，會撞。先擋掉錯的，之後要支援再開一題。

### 為什麼不順手刪死掉的 `readIndices`
試過。那兩個常數雖然沒人用，但會留在輸出 IR 裡，刪掉會讓 `insert-slice.mlir` 五個既有測試的
SSA 名稱位移，CHECK 全要重寫。bug fix 不帶這種噪音。

---

## 最強論據

同一個檔案裡舊的 `PadOpVectorizationWithInsertSlicePattern`（`Vectorization.cpp:3091`）本來就有：
```cpp
    // Only unit stride supported.
    if (!insertOp.hasUnitStride()) return failure();
    ...
    // Check if sizes match: Insert the entire tensor into most minor dims.
    // (No permutations allowed.)
```
新的 `vectorizeAsInsertSliceOp`（#122927，2025-02）把它一般化時漏掉了這兩條。
FIXME「Using rankDiff implies that the source tensor is inserted at the end of the destination tensor.
However, that's not required.」講的就是同一個假設，這個 patch 讓假設成立，FIXME 改成陳述。

---

## 測試

| 測試 | 檔案 | 內容 |
|---|---|---|
| `insert_slice_non_unit_stride` | unsupported.mlir | stride `[3,1]` → `expected-error {{Attempted to vectorize, but failed}}` |
| `insert_slice_rank_reducing_non_minor_dim` | unsupported.mlir | `8x4` 插進 `8x1x4` → 同上 |
| `insert_slice_rank_reducing_leading_dim` | insert-slice.mlir | `8x4` 插進 `2x8x4`，offset `[%c1,0,0]` → `transfer_write ... [%c1, %c0, %c0_1]` |

unsupported.mlir 既有的 insert_slice 案例用 `CHECK-NOT` 而不是 `expected-error`，是因為它走
`vectorize_children_and_apply_patterns`，沒有診斷；直接用 `transform.structured.vectorize` 就有。

驗證：`Dialect/Linalg` + `Dialect/Tensor` + `Dialect/Vector` 306 個 lit 全過；check-mlir 見 TODO。

---

## Reviewer 可能問

- **「為什麼不直接支援 strided／中間維度？」** 見上面「完整修法」。這是把靜默錯值改成不向量化，先止血。
- **「dynamic size 呢？」** `getDroppedDims` 只把靜態 1 當可 drop 的候選，dynamic size 一律保留並配到 source 維，
  所以 `[%sz, 1, 4]` 插進 `8x1x4`（source `?x4`）drop 的是 dim 1 → 拒絕；`[1, %sz, 4]` 插進 `1x8x4` → 接受。
- **「`find_last()` 沒有 dropped dims 時？」** 回傳 -1，`-1 >= 0` 為假，非 rank-reducing 一律通過。
- **「pack／unpack 的 insert_slice 會不會被擋到？」** `pack-dynamic-inner-tile.mlir`、`mmt4d.mlir` 整合測試在 check-mlir 裡，全過。
