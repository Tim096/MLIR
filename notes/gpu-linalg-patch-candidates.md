# GPU 轉換層 ＋ Linalg 向量化候選題目（2026-09-05 掃描）

> `notes/vector-patch-candidates.md` 前三名都送出後的第二次掃描。範圍往路線下一站走：
> `Conversion/GPUToNVVM`、`GPUToSPIRV`（WMMA 部分）、`NVGPU`、`GPU/Transforms`、`AMDGPU`，以及 `Linalg/Transforms`（向量化、pack/unpack）。
> 判準仍是 `Goal.md` §8.7 四關 ＋ 撞車查證，行號對 `origin/main` = `26d3c25b8184`。
> **每一條都在本機 `mlir-opt` 重現過，不是推論。**

---

## ✅ 已送出

### GPU-1. `subgroup_mma_elementwise` 降 NVVM：15 種運算 10 種 `llvm_unreachable`

> ✅ **2026-09-05 已送出 [#221288](https://github.com/llvm/llvm-project/pull/221288)**（分支 `gpu-wmma-elementwise-nvvm`，筆記 `notes/gpu-wmma-elementwise-nvvm.md`）。

`WmmaOpsToNvvm.cpp:365`。`convert-vector-to-gpu` 的 `arith.subf`／`negf`／`truncf`… 都轉成這個 op，接 `-gpu-lower-to-nvvm-pipeline` 直接 abort。
SPIR-V 側 12 種都有。`extf`／`truncf` 依 PTX ISA 不可能做（f16↔f32 累加器轉換未定義），改成明確拒收；s8／tf32 的 packed fragment 也擋。

---

## 候選（依價值排序）

### L-1. `tensor.insert_slice` 向量化：rank-reducing 與非單位 stride 產生錯的 IR 🥇 → ✅ 已送出 [#221293](https://github.com/llvm/llvm-project/pull/221293)（2026-09-05，最小修法）

`Linalg/Transforms/Vectorization.cpp:1984`（`vectorizeInsertSliceOpPrecondition`）、`:3034`（FIXME `rankDiff`）、`:3049`（建了 `readIndices` 卻沒傳）

前置條件**完全沒檢查** `hasUnitStride()` 與 source／dest rank 是否相等。三種錯法都重現了（`transform.structured.vectorize`）：
1. `tensor<8x4>` 插進 `tensor<8x1x4>`（丟掉中間的 dim）→ 寫進 dest 的 dim 1／2，`in_bounds = [false, true]` 悄悄丟掉 7 列。
2. 同上但 offset `[0, 3, 0]` → 寫到 `dst[0][3+i][j]`，正確是 `dst[i][3][j]`，純錯值。
3. stride `[3, 1]` → stride 直接消失，連續寫第 0／1 列。
**但 dropped dims 全在最前面時（source 插在 dest 尾端）目前是對的**，這就是 FIXME 講的那個假設；`unsupported.mlir:398` 與 `insert-slice-with-patterns.mlir` 的案例都是這一種，不能一律拒收 rank-reducing。

| 關 | 證據 |
|---|---|
| ① | `LinalgTransformOps.cpp` 的 `transform.structured.vectorize`；整合測試 `Integration/Dialect/Linalg/CPU/pack-dynamic-inner-tile.mlir`、`mmt4d.mlir` 跑 vectorizer（沒有專門跑 insert_slice 的） |
| ② | **vectorization**（＋ tensor layout） |
| ⑤ | 乾淨。#205493（scalable precondition）、#97297（stale）都不碰這兩個函式。近半年 7 人動過檔案，無人佔這段 |

**兩種做法**：
- 最小：前置條件加 `!hasUnitStride()` bail ＋ 非「尾端插入」的 rank-reducing bail（用 `getDroppedDims()` 判斷 dropped dims 是否全為 leading）；順手刪死掉的 `readIndices`。~30 行，零設計爭論。
- 完整：write 用 `getDroppedDims()` 建 permutation map（`createWriteOrMaskedWrite` 已有收 map 的版本），vecShape 的 dynamic 分支改查對應的 dest dim，FIXME 真的消掉。~60 行，既有測試輸出不變。
作者 Andrzej Warzyński（banach-space，#122927，2025-02），他也是 #221268 的 reviewer。

### V-1. `FoldArithExtIntoContractionOp` 兩側 ext 來源型別不同時產生過不了 verifier 的 `vector.contract` 🥈 → ✅ 已送出 [#221298](https://github.com/llvm/llvm-project/pull/221298)（2026-09-05）

`Vector/Transforms/VectorTransforms.cpp:1913`。只檢查 `lhsDefOp`／`rhsDefOp` 存在，沒比較它們 operand 的型別。
`extsi i8→i32` 配 `extsi i16→i32` 餵進去 → `'vector.contract' op failed to verify that lhs and rhs have same element type`（重現：`--test-fold-arith-extf-into-vector-contract-patterns`）。

| 關 | 證據 |
|---|---|
| ① | `VectorTransformOps.cpp:58`（`transform.apply_patterns.vector.fold_arith_extension`）、`LinalgTransformOps.cpp:4305`；**沒有整合測試**，這是弱項 |
| ② | **mixed precision**（pattern 存在的理由就是 tensor core 的 `mma.sync.f32.f16.f16.f32`） |
| ⑤ | 乾淨；近半年改動集中在 broadcast／elementwise reorder |

做法：加一個型別比較 `notifyMatchFailure`，1 檔 ＋ 1 lit，~12 行。**適合當 #221288 review 期間的填充 PR。**

### GPU-2. SPIR-V 靜默丟掉 `subgroup_mma_compute` 的 `a_transpose`／`b_transpose`

`GPUToSPIRV/WmmaOpsToSPIRV.cpp:397-430`。NVVM 側用它選 intrinsic（`WmmaOpsToNvvm.cpp:256`），SPIR-V 側整個 pattern 沒讀它，load／store 卻有處理 `transpose`。
`SPV_KHR_cooperative_matrix` 的 operands 沒有 transpose 位，所以正確做法是 `notifyMatchFailure` 拒收。
⚠️ `GPUOps.td:2016` 的 op 文件自己寫「transpose 屬性似乎不影響正確性」，review 會有來回；論點是「兩個後端對同一屬性語意不一致本身就是問題，靜默丟棄是最差選項」。
② GPU codegen ＋ tensor layout；⑤ 乾淨，近期作者 fabrizio-indirli、Dhruv Chauhan 都不碰 compute。~10 行。

### L-2. `DecomposeOuterUnitDimsPackOpPattern` 對「padding ＋ 非單位 un-tiled outer dim」bail

`Linalg/Transforms/Transforms.cpp:1175`。FIXME 是 #218141（prometheusfma-llvm，08-25）把 assertion crash 換成 bail 時留的，明寫「應該支援」。負向測試 `decompose-pack.mlir:365` 現成。
② tensor layout ＋ tiling；⑤ 乾淨，但**先 @ #218141 作者**。中等設計風險（padded pack 的 `tensor.pad` high pad 怎麼算）。~40-60 行。

### GPU-3／GPU-4. 兩個「重建 op 時丟屬性」的小題

- `GPU/Transforms/DecomposeMemRefs.cpp:145`／`:168`：`memref.load`／`store` 的 `nontemporal`／`alignment`／`invariant` 丟掉。
- `AMDGPU/Transforms/MaskedloadToLoad.cpp:56`／`:227`：`vector.maskedload`／`maskedstore` 的 `alignment` 丟掉（實測只是變保守，**不是錯誤**）。
兩個都 ~6 行 ＋ lit，零爭論，但**第 1 關弱**：樹裡沒有 pipeline 引用、沒有整合測試。當 commit 數填充用。

### V-2. `ContractionOpToDotLowering`／`ContractOpToElementwise` 建構子丟掉 `constraint` 參數

`LowerVectorContract.cpp:304`／`:775`，對照 `:257`／`:347` 是 `filter(std::move(constraint))`。2 行修，但樹裡沒有人傳非預設 constraint，**寫不出會失敗的測試**；且 #196642（composable contract lowering，停滯 4 個月）碰同一檔。價值最低。

---

## 被刷掉的（避免重掃）

**verifier／TableGen 已擋死（不可達）**：`NVGPUToNVVM.cpp:350` 的 `getMatrixA()` 複製貼上（`matrixA and matrixB have same element type` 約束擋住）；`WmmaOpsToNvvm.cpp:52`／`:70` 的 `llvm_unreachable`（`MMAMatrixType` verifier 限定）；`GPU/Utils/Utils.cpp:41`。
**查過不是 bug**：`SubgroupReduceLowering.cpp` DPP 路徑的 `clusterStride`（`:537` 已拒收）；`NVGPUToNVVM.cpp` tf32 檢查兩側對稱；`LowerVectorMask.cpp:233` write 側不查 passthru（verifier 保證只有 read 有）；`FlattenContiguousRowMajorTransfer*` 的 scalable（`isContiguousSlice` 先擋）；`vectorizeAsTensorPackOp` 省略 `useInBoundsInsteadOfMasking`（語意等價）。
**硬體不可達（sm_90）**：`NVGPUToNVVM.cpp:965`／`:980`／`:1007` TMA、`NVGPUTransformOps.cpp` 全部 TODO。
**設計題不是小 patch**：`VectorToGPU.cpp:545` 抽象 layout、`:92` `fpExtend/fpTruncSupportsMMAMatrixType` 無條件 true、`NVGPUToNVVM.cpp:373`／`:606` satfinite 屬性、`DataLayoutPropagation.cpp` 各 TODO、`LowerVectorContract.cpp:640`／`:783` mask 支援、`VectorDropLeadUnitDim.cpp:229`／`:283`（剛 revert 過一輪）。
**撞車**：`VectorToGPU.cpp:354` 與 #218226 同區；XeGPU 全部。
**第 1 關失敗**：`PackAndUnpackPatterns.cpp:135` `isPackOnInnerMostDim` 缺 `hasStaticShape()`（只有 test/lib 呼叫）。
**域外**：`-convert-vector-to-scf` 對 `vector.mask` 包的 `transfer_write` 報 `expects only one operation to mask`——是 VectorToSCF 的缺陷，`LowerVectorTransfer.cpp:264` 的 TODO 只是伴生現象，之後可以另開一題。
