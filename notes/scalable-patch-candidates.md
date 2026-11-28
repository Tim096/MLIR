# scalable（SVE／RVV）候選題目（2026-11-28 掃描）

> 被看見線的專門掃描，接在 [`visibility-track-candidates.md`](visibility-track-candidates.md) 之後。
> 範圍：`mlir/lib` 全部（XeGPU 除外）含 `scalab` 且帶限制字眼（TODO／not supported／bail／assert…）的 82 行，
> 加上 `mlir/test/Integration/Dialect/{Linalg,Vector}/CPU/ArmSVE/` 裡上游自己寫的 TODO。
> 判準是 `Goal.md` §8.7 四關。行號對 `origin/main` = `a6321f2d`（2026-11-28）。

## ⚠️ 查證程度（與 `visibility-track-candidates.md` 相同，比 8、9 月兩次掃描低）

- ✅ 行號與原文：讀原始碼確認。
- ❌ **沒有 build、沒有重現。** 每一題的「現況」都是讀 code 的結論。
- ❌ **沒查 open PR 撞車。** 掃描的 session 讀不到 `llvm/llvm-project` 的 PR／issue。
  下面引用的 issue 編號（#159751 等）是從樹裡的註解抄的，**issue 現在的狀態沒看**。
- ⚠️ **scalable 的題目要能實跑才算驗過**（比照 `Goal.md` §2.4 09-04 那條 GPU 的規則）。
  本機沒有 SVE 硬體，要靠 qemu-aarch64 跑 `ArmSVE/` 整合測試——**這個環境還沒建，是所有題目共同的前置成本**。

**先講結論**：82 行裡多數是「本質上做不到」（編譯期無法展開 scalable 維度），不是缺口。
真的是缺口、又過得了第 1、2 關的只有三題，其中一題是別人路線圖上的大題。

---

## 🥇 S-1. 子位元組 ext／trunc 的改寫不收 scalable 向量

`mlir/lib/Dialect/Vector/Transforms/VectorEmulateNarrowType.cpp:1620`

**現況**：`commonConversionPrecondition` 第一行就擋 scalable（`"scalable vector"`）。
這個前置條件被兩組 pattern 共用：

- `BitCastRewriter` 那組（`RewriteBitCastOfTruncI`、`RewriteExtOfBitCast`）用 `vector.shuffle`，
  **本質上只能固定長度**（`:1577`／`:1579` 的 assert）。
- **aligned 那組**（`RewriteAlignedSubByteIntExt` `:2130`、`RewriteAlignedSubByteIntTrunc` `:2195`）
  只用 `vector.bitcast`、`vector.interleave`（`:1908`、`:1941-1943`）、`vector.deinterleave`（`:1956`）
  和 `arith` 的位元運算——**這些 op 全部支援 scalable**，卻被共用的前置條件一起擋掉。

白話：**i4／i2 量化權重在 SVE／RVV 上解不開也包不回去，但擋住它的那一行跟它無關。**

| 關 | 證據 |
|---|---|
| ① AI pipeline | `populateVectorNarrowTypeRewritePatterns` 有兩個 production 呼叫者：`VectorTransformOps.cpp:305`（`transform.apply_patterns.vector.rewrite_narrow_types`）、`XeGPUToXeVM.cpp:2104`。整合測試 `Integration/Dialect/Vector/CPU/rewrite-narrow-types.mlir`（只有固定長度）。scalable 的 interleave／deinterleave 有 SVE 整合測試：`ArmSVE/scalable-interleave.mlir`、`ArmSVE/test-scalable-deinterleave.mlir` |
| ② JD 關鍵字 | **quantization ＋ SVE／RVV**（兩個都有，這次掃描裡最強的組合） |
| ④ 證據 | lit ＋ qemu 下的整合測試；改寫本身與固定長度版相同，i2／i4 可窮舉 |
| ⑤ 撞車 | **沒查** |

**做法**（估 1 個 lib ＋ 2 個測試檔）：

1. 把 scalable 檢查從共用前置條件移到 `BitCastRewriter` 那組自己的入口。
2. `bitcastSubByteVectorToI8`（`:1795-1805`）用 `VectorType::get(vecShape, i8)` 重建型別，
   **會丟掉 scalable 旗標**，要改成帶 `getScalableDims()`。其他幾個 `rewriteI*` 要逐一檢查同樣的毛病。
3. `fitsInMultiByteContainerTy`（`:1276-1290`）只看 `getShape().back() % elemsPerMultiByte`，
   對 `[N]` 仍然成立（N·vscale 可整除），不必改，但要在 PR 裡講清楚。

**為什麼排第一**：

- 就在自己已經熟的函式裡——#221185（i2 trunci）改的正是 `RewriteAlignedSubByteIntTrunc`。
  **等 #221185 進了再開**，否則自己撞自己。
- 缺口一句話講得完，改動小，而且關鍵字是兩條強的疊在一起。

**最大的風險（動手前先驗）**：LLVM 後端吃不吃 `<vscale x N x i4>` 的 bitcast。
MLIR 這層改對了，若 AArch64 後端對子位元組 scalable 型別 legalize 失敗，整合測試會跑不起來。
**第一步是手寫一段 LLVM IR 丟 `llc -mattr=+sve` 試**，不通就把這題降級成「只有 lit、沒有實跑」，或不做。

---

## 🥈 S-2. `vector.vscale`／scalable `vector.step` 沒有範圍（已在另一份清單，這裡補充）

主條目是 [`visibility-track-candidates.md`](visibility-track-candidates.md) 的第 1 題。這次掃描補三點：

- `StepOp::inferResultRanges` 對 scalable 型別直接 `return`（`VectorOps.cpp:8644`）。
  有了 `vscale` 的上界才界定得了，所以**順序是先做 `vscale`，再做這個**。
- `vscale` 的上下界目前是 pass 選項：`Vector/Transforms/Passes.td:33`／`:35` 的 `vscale-min`／`vscale-max`，
  只有 mask elimination 在用（`VectorMaskElimination.cpp:63-69` 的註解明寫「`vscaleRange` is required to
  reason about scalable dimensions」）。
- **這是一個可以寫成 RFC 的問題**：`vscale` 的範圍該放在 IR 上（函式屬性，對應 LLVM 的 `vscale_range`）
  還是繼續當 pass 選項？現在 `IntegerRangeAnalysis` 與 `ValueBounds` 兩套各自為政。
  owner 線的 RFC 從這裡切入，比純講 poison 語意更容易有人在乎。**這是我的判斷，沒有人在上游提過（沒查）。**

---

## 🥉 S-3. scalable 的 `linalg.pack` 向量化（上游點名，但在別人的路線圖上）

`mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp:2424-2428`（Cond 1：非 `LinalgOp` 只放行 `UnPackOp`）

**現況**：上游自己在兩個 SVE 整合測試裡寫了 TODO：

- `Integration/Dialect/Linalg/CPU/ArmSVE/pack-unpack-scalable-inner-tile.mlir:34`
  ——「ATM only linalg.unpack is vectorized. Add linalg.pack vectorization.」
- `Integration/Dialect/Linalg/CPU/ArmSVE/pack-unpack-mmt4d.mlir:46`
  ——「Vectorize linalg.pack + linalg.unpack」，掛 issue **#159751**

| 關 | 證據 |
|---|---|
| ① AI pipeline | 上面兩個整合測試本身；mmt4d 是 data-tiling 矩陣乘法的標準形 |
| ② JD 關鍵字 | **vectorization ＋ tensor layout ＋ SVE**——關鍵字最密的一題 |
| ⑤ 撞車 | **沒查，而且風險是這次最高的**。這是 Arm 團隊的主線，issue 是他們自己開的 |

**性質**：大題、設計題。會碰到 `getCollapsedVecType` 的「Collapsing more than 1 scalable dim is not
supported ATM」（`:1599-1600`）和 scalable 維度的 `shape_cast`／`transpose`。

**怎麼用這一題**：不要直接開 PR。**先去 #159751 看現況、留言問有沒有人在做**。
有人在做 → 改成 review 那個 PR（被看見的效果一樣有，成本低很多）。沒人做 → 問能不能拆一小塊。
這題的價值有一半在「跟 `vector`／`linalg` 的 maintainer 建立工作關係」。

---

## 過了第 2 關、但第 1 關或可行性不夠的

| 位置 | 內容 | 為什麼不排進前面 |
|---|---|---|
| `Vectorization.cpp:2515-2521`（Cond 4） | scalable 向量化只放行 elementwise、matmul 系、`DepthwiseConv1DNwcWc`、mmt4d、有 reduction 的 op；一般 conv、pooling 不行 | 上游註解（`:2446` 附近）寫「Relax these conditions as good motivating examples are identified」——**要先有動機例子**，沒有就是替別人做設計 |
| `Vectorization.cpp:3912-3913` | conv 的 flatten 路徑忽略 scalable 旗標 | 同上，且與上一列綁在一起 |
| `Vectorization.cpp:2476` | matmul 的 reduction 維度不能 scalable | 明確的設計限制，不是漏做 |
| `LinalgTransformOps.cpp:3630`、`:4264` | scalable tile size 不能配 `packed_tile_sizes`／`num_threads` | 關鍵字有（tiling ＋ SVE），但 `packed_tile_sizes` 只在 `transform-op-tile.mlir`、`transform-op-fuse.mlir` 出現，**整合測試沒人用**；第 1 關弱 |
| `LowerVectorScan.cpp:129` | `vector.scan` 不能沿 scalable 維度 reduce | 整合測試只有 `CPU/scan.mlir`（固定長度）；`vector.scan` 的 production 使用者沒找到，第 1 關不過 |

---

## 被刷掉的（避免重掃）

**本質上做不到——編譯期無法展開 scalable 維度**（最大宗，約 25 處）：
`VectorUtils.cpp:285`／`:504`／`:711`／`:731`、`LowerVectorMask.cpp:63`／`:147`、
`LowerVectorContract.cpp:434`／`:650`／`:655`、`VectorToSCF.cpp:339`／`:1340`／`:1488`、
`VectorUnroll.cpp:167`／`:1055`、`VectorEmulateMaskedLoadStore.cpp:61`／`:133`（無法 scalarize scalable mask）、
`VectorLinearize.cpp:39`／`:807`、`AffineExpandIndexOpsAsAffine.cpp:61`／`:122`。

**`vector.shuffle` 表示不了 scalable**：`LowerVectorTranspose.cpp:452`、
`VectorInsertExtractStridedSliceRewritePatterns.cpp:101`／`:193`、`VectorOps.cpp:3586`／`:3691`、
`VectorTransforms.cpp:954`（`BreakDownVectorBitCast`，建在 strided slice 上）。

**LLVM 的限制，不是 MLIR 的**：`VectorToSCF.cpp:736-738`（LLVM 沒有 scalable of scalable）、
`ConvertVectorToLLVM.cpp:2176`（`llvm.matrix.multiply` 只吃固定長度）、`LLVMCommon/Pattern.cpp:420`、
`LLVMConstantOps.cpp:186`、`LLVMMemoryOps.cpp:762`。

**第 2 關（沒有關鍵字，或 scalable 只是順帶）**：`VectorTransforms.cpp:767`（`BubbleUpBitCastForInsert`）、
`:1280`（`ExtractOpFromLoad`）、`:1350`（`StoreOpFromBroadcast`）、`:1557`（`FoldI1Select`）、
`VectorOps.cpp:2194`／`:2574`（`from_elements` 的折疊）、`LowerVectorBroadcast.cpp:128`
（08-21 已刷過一次，理由相同；真正需要它的是 SME 的二維 scalable）。

**設計題，且要動到 LLVM lowering**：`ArithOps.cpp:300`（`arith.constant` 的非 splat scalable 初值），
註解自己寫「would most likely require updating the lowerings to LLVM」。

**不在路線上**：`SPIRVConversion.cpp:55`、`SubgroupReduceLowering.cpp:58`／`:137`（GPU 沒有 scalable）、
`X86/PrepareVectorContractLoops.cpp:446`、`VectorDistribute.cpp:2441`（warp，08-21 第 1 關就刷了）、
`Promotion.cpp:46`、`ModuleImport.cpp:1460`、`VCIXToLLVMIRTranslation.cpp:42`。

**不是限制，是已經支援**：`BlockPackMatmul.cpp:168-352` 的 `scalableBlockFactors`（看起來是近期加的）、
`ArmSVE/LegalizeForLLVMExport.cpp:169`、`VectorToArmSME.cpp:713`（各自只處理自己那種 mask）。

---

## 建議

1. **先建 qemu-aarch64 ＋ SVE 的實跑環境**，並用一段手寫 LLVM IR 驗 S-1 的後端風險。這一步不過，S-1 要降級。
2. **S-1 等 #221185 進了再開。**
3. **S-2 先做 `vscale` 那一半**（另一份清單的第 1 題），不需要 SVE 環境，只要 lit。
4. **S-3 先去 #159751 留言，不寫 code。**

順帶一提：被看見線在 scalable 這個方向的題目**比預期少**。SVE 的支援是 Arm 團隊系統性做的，
剩下的缺口多半是他們判斷過「做不到」或「還沒有動機」的。要在這裡被看見，
review 他們的 PR 可能比找漏洞有效。
