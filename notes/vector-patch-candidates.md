# `vector` 候選題目（2026-08-21 掃描，全部過第 1、2 關 + 撞車查證）

> 掃描範圍：`mlir/lib/Dialect/Vector/` ＋ `mlir/lib/Conversion/VectorTo*/` 的全部 TODO/FIXME。
> 判準是 `Goal.md` §8.7 的四關，行號對 `origin/main` = `bd9990e127e1`。
> **每一條的第 1 關證據都是實查的檔案路徑，不是推論。**

---

## 🥇 1. 子位元組 `arith.trunci` 到 `i2`

`mlir/lib/Dialect/Vector/Transforms/VectorEmulateNarrowType.cpp:2208`

**缺口是不對稱**：`RewriteAlignedSubByteIntExt`（放大方向）**i4 與 i2 都支援**
（`rewriteI2ToI8Ext`，註冊在 `:2317-2324`）；`RewriteAlignedSubByteIntTrunc`（縮小方向）
**只有 `rewriteI8ToI4Trunc`，碰到 i2 直接 bail**。
白話：**i2 權重解得開，包不回去。**

| 關 | 證據 |
|---|---|
| ① AI pipeline | 跑得起來的整合測試 `mlir/test/Integration/Dialect/Vector/CPU/rewrite-narrow-types.mlir`（走 `transform.apply_patterns.vector.rewrite_narrow_types` ＋ `mlir-runner`） |
| ② JD 關鍵字 | **quantization**（＋ mixed precision） |
| ⑤ 撞車 | **乾淨**。無相關 open PR；該檔近半年 3 人動過，都不碰這個 pattern |

**上游自己留了一個負向測試指名這個缺口**：
`mlir/test/Dialect/Vector/vector-rewrite-subbyte-ext-and-trunci.mlir:206`
`@aligned_trunci_i8_to_i2_no_match` —— **把這個測試從 no_match 翻成正向，就是這個 patch 的核心證據。**

**做法**：不是 `fold()`，是擴充既有的 `OpRewritePattern`。仿 `rewriteI8ToI4Trunc` 寫
`rewriteI8ToI2Trunc`（deinterleave 兩次 → 4 條 i8 → `andi 0x03` → `shli 0/2/4/6` → `ori` → `bitcast`），
拿掉 bail。**約 2~3 個檔案。**

> 💡 為什麼排第一：缺口對稱性一眼看得懂、上游自己標記了、撞車乾淨、
> 關鍵字是最強的 quantization，而且**改動範圍小到可以做到完全正確**。

---

## 🥈 2. 轉置的 `gpu.subgroup_mma_store_matrix`

`mlir/lib/Conversion/VectorToGPU/VectorToGPU.cpp:213`（＋ `:642`）

MMA 的 **load** 路徑會算 `isTranspose` 並發出 `subgroup_mma_load_matrix ... transpose`
（`:591`、`:612`）；**store** 路徑在 `:213` 拒收任何非最內層的 permutation map，
並在 `:642` 硬寫 `/*transpose=*/UnitAttr()`。

**TODO 自己寫的擋路理由（「等 GPU dialect 加上這個屬性」）已經不成立**：
`GPUOps.td:1985` 已有 `OptionalAttr<UnitAttr>:$transpose`，而且兩個後端都已經在讀它
（`WmmaOpsToNvvm.cpp:165` → `NVVM::MMALayout`、`WmmaOpsToSPIRV.cpp:385` → `isColMajor`）。
**只剩 VectorToGPU 不肯產生它。**

| 關 | 證據 |
|---|---|
| ① AI pipeline | 在 `mlir/lib/Conversion/`，掛在 `-convert-vector-to-gpu`；lit 測試 `vector-to-mma-ops.mlir` 有 `@matmul_transposed` 等，**全是 load 側，轉置 store 零測試** |
| ② JD 關鍵字 | **GPU codegen**（＋ tensor layout） |
| ⑤ 撞車 | **乾淨**。近半年只有 1 人動過。**前例**：`18ecdbfe6c74`（2026-02）做完 read 側就停了，write 側是沒人認領的自然續作 |

**做法**：下游全都就緒，風險極低。重用 `isFirstResultLastMapDimension`，
把 flag 串進 `convertTransferWriteOp`。**約 2 個檔案。**

---

## 🥉 3. `in_bounds` 沒看 indices 就算出來

`mlir/lib/Dialect/Vector/Utils/VectorUtils.cpp:479`、`:484`（write 端 `:547`、`:552`）

`useInBoundsInsteadOfMasking` 時，`in_bounds` 純粹從 shape 推：
有 map 的分支只檢查 `sourceDim % vectorDim == 0`，無 map 的只檢查 `sourceShape[i] == vecShape[i]`，
**兩邊都不看 `customIndices`**。從非零、非對齊 offset 起讀的 transfer 會被蓋上 `in_bounds = true`。

危險的呼叫者：`mlir/lib/Dialect/Affine/Transforms/SuperVectorize.cpp:1268`
——樹裡唯一同時傳 `useInBoundsInsteadOfMasking=true`、真實 `indices` 與 `permutationMap` 的地方。

| 關 | 證據 |
|---|---|
| ① AI pipeline | `mlir/test/Integration/Dialect/Linalg/CPU/pack-unpack-mmt4d.mlir`、`pack-dynamic-inner-tile.mlir`（linalg.pack/unpack 向量化） |
| ② JD 關鍵字 | **vectorization**（＋ tensor layout） |
| ⑤ 撞車 | ⚠️ **軟撞車**：#215340（@dhairyashilRG，08-19 更新）折的是既有 op 的 `in_bounds`，這題修的是**第一次設定**的地方。重疊到需要先去留言協調 |

**做法**：四處都要把 index 的 `OpFoldResult` 納入判斷。**影響面最大**——
`in_bounds` 出現在 `mlir/test/Dialect/Linalg/vectorization/*` 與 `SuperVectorize/*` 一堆 CHECK 行，
估 1 個 lib ＋ 3~8 個測試檔。

---

## 4. `transfer_read/write` 的 drop-unit-dims 對 tensor 直接放棄

`mlir/lib/Dialect/Vector/Transforms/VectorTransferOpTransforms.cpp:485`、`:605`

兩個 pattern `dyn_cast<MemRefType>` 失敗就放棄，所以 tensor 上的 `vector.transfer_read`
永遠不會被降維。降維本身用 `memref.subview` 做，tensor 版要改用 `tensor.extract_slice`。

- ① `mlir/test/Integration/Dialect/Linalg/CPU/ArmSME/pack-unpack-mmt4d.mlir` 等兩個整合測試
- ② **tensor layout**（＋ vectorization）
- ⑤ 乾淨，但近半年 4 人在動這個檔案（含 kuhar）

> ⚠️ **誠實的但書**：「rank reduction 該不該在 bufferization 之前發生在 tensor 上」
> 是設計問題不是機械修補，**預期會有 review 辯論**，不是能快速 merge 的題目。因此排在 1、2 之後。

---

## 5. strided gather 的 rewrite 限制太多

`mlir/lib/Dialect/Vector/Transforms/LowerVectorGather.cpp:121`、`:131`、`:139`、`:147`

`RemoveStrideFromGatherSource` 只在「rank-2 ＋ 單一 stride ＋ stride 剛好等於尾維 ＋ 靜態 offset」
四個條件全中時才動作，其餘全部退回差很多的 conditional-load 展開。

- ① `mlir/lib/Dialect/XeGPU/Transforms/XeGPUVectorLinearize.cpp:45` 真的呼叫它；整合測試 `CPU/gather.mlir`
- ② **GPU codegen**（經由 XeGPU）—— **五題裡第 2 關最弱的**，不要硬拗成 tensor layout
- ⑤ 這個 pattern 乾淨，但周邊 XeGPU/gather 很擠

---

## ⛔ 不要單獨開的：mixed-mode `vector.contract`

`LowerVectorContract.cpp:907`。**兩關都輕鬆過**，而且 mixed precision 是最強的關鍵字——
**但 PR #117753（@Groverkss）open、非 draft、正是這個 TODO。**
`updated_at` 停在 2026-03-26，但那個日期被幾十個無關 PR 共用（看起來是批次觸碰而非真活動），
所以判定為**停滯但仍活著**。要做就去 #117753 留言表達接手意願，**不要開競爭 PR**。

---

## 被刷掉的，以及各自的理由

| 被刷掉的 | 數量 | 為什麼 |
|---|---|---|
| 「support 0-d corner case」 | ~20 處 | **第 2 關**。rank-0 退化處理不帶任何 AI 關鍵字 |
| 「Canonicalization for dynamic position」 | 10 處 | **第 2 關**。純 vector canonicalization 明文不過關（與 08-21 自己的判斷一致） |
| `populateVectorNarrowTypeEmulationPatterns` 全系列 | ~8 處 | **第 1 關**。雖然有量化味，但樹裡唯一呼叫者是 `test/lib/`，沒有 production pass 註冊、沒有整合測試跑它。**候選 1 是 rewrite 那組，不是 emulation 這組——不同的 populate 函式** |
| `ChainedReduction` 其他 combining kind | 2 處 | **第 1 關**。只有 `TestVectorTransforms.cpp` 呼叫 |
| warp distribution 的 1-D 分佈型別 | 4 處 | **第 1 關**。populate 函式在 `test/lib/` 外零呼叫者；唯一的 CUDA 整合測試裡 `strided_slice` 出現 0 次 |
| `VectorToXeGPU.cpp` 的 uArch 檢查 | 4 處 | **撞車**。#217179 直接認領，且 XeGPU 一週內有 6 個以上活躍 PR |
| shuffle-tree mask 壓縮 | 3 處 | 第 2 關，無 AI 關鍵字 |
| `VectorMaskElimination.cpp:97` | 1 處 | 第 2 關，**且上游在 TODO 裡自己反對**（"less likely to be useful"） |
| `LowerVectorBroadcast.cpp:129` | 1 處 | 第 2 關，scalable broadcast 機制，無關鍵字 |
| `inferFragType` 佈局抽象 | 1 處 | 兩關紙面上都過，但那是「改 GPU dialect 抽象佈局」的**重新設計**，不是一個 patch。**可行性刷掉** |

> 📌 掃描過程中有一條誤報已自行更正：「unsigned 子位元組 ext 沒註冊」是**錯的**，
> `VectorEmulateNarrowType.cpp:2323-2324` 兩個都註冊了（PR #89131 加的）。
> 記在這裡是提醒：**候選清單裡的每一條，動手前都要再驗一次行號還在不在。**
