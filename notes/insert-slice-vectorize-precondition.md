# #221293：`insert_slice` 向量化與 09-05 landed 的 #219192 對撞（2026-09-11／12）

## 發生什麼

- #221293（09-04 送）在 `vectorizeInsertSliceOpPrecondition` 加兩個 bail：stride 不是 1、rank-reducing 丟掉的維度不是最前面的。理由：寫回用的是 minor identity 的 `transfer_write`，向量維度只能對到目的地**最後幾維**。
- 09-05 FedericoBruzzone 的 #219192 merge（`314fef96ab59`）：「Support non-trailing dropped dims when vectorizing rank-reducing InsertSliceOp」。他修的是 **vector shape 推導**（動態 source 維度要對到哪個 result 維度），用 `getDroppedDims()` 做映射，新增測試 `insert_slice_dynamic_src_dim_non_leading_unit_dim_dropped`（`tensor<?x4xi32>` insert 進 `tensor<8x1x4xi32>`，中間那維被丟掉）。
- 結果 #221293 與 main 衝突（`mergeable_state: dirty`），而且它的 negative test `insert_slice_rank_reducing_non_minor_dim` 就是 #219192 說「支援了」的形狀。

## 09-12 實測：#219192 的 case 在 main 上算錯

寫回還是沒有 permutation map（`vectorizeAsInsertSliceOp` 呼叫 `createWriteOrMaskedWrite(rewriter, loc, read, dest, writeIndices, inputVectorSizes.empty())`，沒傳 map）：

```mlir
%3 = vector.transfer_write %2, %1[%c0, %c0, %c0] {in_bounds = [false, true]} : vector<8x4xi32>, tensor<8x1x4xi32>
```

`vector<8x4>` 的第 0 維對到 `tensor<8x1x4>` 的第 1 維（大小 1），`in_bounds = false` 表示越界的部分不寫。用 `mlir-runner` 跑靜態版本（source 是 1～32 逐列，dest 先填 0）：

```
不向量化：      [[[1,2,3,4]], [[5,6,7,8]], [[9,10,11,12]], ..., [[29,30,31,32]]]
向量化（main）： [[[1,2,3,4]], [[0,0,0,0]], [[0,0,0,0]],    ..., [[0,0,0,0]]]
```

只有第 0 列落到 `[0,0,:]`，其他七列被丟掉。#219192 把 vector shape 修對了，但寫回的位置沒修。

重現：`scratchpad` 裡的 `insert_slice_main.mlir` ＋ `insert_slice_lib.mlir`（transform sequence 拆到另一個檔用 `-transform-preload-library`，不然 transform module 會留在 IR 裡讓 runner 讀不懂）；pipeline `-one-shot-bufferize=bufferize-function-boundaries -convert-linalg-to-loops -test-lower-to-llvm`。注意：**只重建 `mlir-opt` 之後 `mlir-runner` 會對不上新的 shared lib，任何程式都 "out of memory"**，要 `ninja mlir-runner mlir_runner_utils mlir_c_runner_utils`。

## 兩條路（09-12 留言 5637441586 問 FedericoBruzzone 與 banach-space）

1. **保守**：#221293 rebase 後照舊 bail，#219192 的新測試搬去 `unsupported.mlir`。小、立刻能 merge，但等於把他的 patch 意圖收回。
2. **建設**：寫回帶 permutation map，每個向量維度對到自己沒被丟掉的目的維度（這例是 `(d0, d1, d2) -> (d0, d2)`）。要一起改 `createWriteOrMaskedWrite`：
   - `useInBoundsInsteadOfMasking` 路徑有 map 時走 `computeInBoundsFromPermutationMap`（整除規則），跟現在無 map 的「dest ≥ vec」規則不同，既有測試的 `in_bounds` 可能變；
   - masked 路徑的 mask 尺寸用 `destSizes[diff + idx]`，寫死「對到最後幾維」，要改成照 map 取維度。
   這條跟 #221268（`in_bounds` 推導要看索引）碰同一個 helper，先後順序要排。

`vector.transfer_write` 的 permutation map 允許 projection（每個 result 是不同的 dim，不能 broadcast），`verifyPermutationMap`（VectorOps.cpp:5108）只要求 dim 不重複，所以 `(d0,d1,d2)->(d0,d2)` 合法。

## 答辯

- 「#219192 不是已經支援了嗎」：它改的是 vecShape 那段（Vectorization.cpp `resultDimsForSourceDims`），寫回那行沒動；上面的執行結果就是證據。
- 「為什麼不直接做建設版」：跟 #221268 撞同一個 helper，而且 `in_bounds` 旗標本身在 RFC 要不要拿掉（Discourse 91649）；先問 reviewer 要哪條，免得白做。
- 「stride 那半」：跟 #219192 無關，rebase 後照舊成立。
