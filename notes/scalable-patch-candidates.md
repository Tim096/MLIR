# scalable（SVE／RVV）候選題目（2026-11-28 掃描）

> 被看見線的專門掃描，接在 [`visibility-track-candidates.md`](visibility-track-candidates.md) 之後。
> 範圍：`mlir/lib` 全部（XeGPU 除外）含 `scalab` 且帶限制字眼（TODO／not supported／bail／assert…）的 82 行，
> 加上 `mlir/test/Integration/Dialect/{Linalg,Vector}/CPU/ArmSVE/` 裡上游自己寫的 TODO。
> 判準是 `Goal.md` §8.7 四關。行號對 `origin/main` = `a6321f2d`（2026-11-28）。

## ⚠️ 查證程度（與 `visibility-track-candidates.md` 相同，比 8、9 月兩次掃描低）

- ✅ 行號與原文：讀原始碼確認。
- ~~❌ 沒有 build、沒有重現。每一題的「現況」都是讀 code 的結論。~~
  ✅ **11-28 本機補查**：有 build（checkout base `376f04dd8bdb`）、三題的「現況」都重現或對 `origin/main` `f496863dad20` 重驗。
  結果寫在各題底下的「11-28 審查」。**S-1 的「現況」有一處寫錯**（不是全部被擋掉，有兩種輸入是 assert 失敗）。
- ~~❌ 沒查 open PR 撞車。~~ ✅ **11-28 用 `gh pr list --search` 與 GitHub 搜尋 API 查過**，#159751 的現況也看了。
  是關鍵字搜尋，0 筆不等於沒有。
- ✅ **scalable 的題目要能實跑才算驗過**（比照 `Goal.md` §2.4 09-04 那條 GPU 的規則）。
  本機沒有 SVE 硬體，靠 qemu-aarch64 跑 `ArmSVE/` 整合測試——**11-28 環境已建好**，上游 18 個 ArmSVE 整合測試在 qemu 下全過。
  做法與指令見文末〈實跑環境〉。

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

**11-28 實測**（`tools/sve-qemu/s1-backend-check/run.sh`，本機 `llc` 24.0.0git，checkout base `376f04dd8bdb`，`-O0` 與 `-O2` 結果相同）：

| 函式 | 內容 | `llc -mattr=+sve` | qemu 128／256／512 bit |
|---|---|---|---|
| `trunc_direct` | 現在 MLIR 產生的形式：`trunc` 到 `<vscale x 16 x i4>` | `LLVM ERROR: Cannot scalarize scalable vector stores` | — |
| `sext_direct` | 現在的形式：`sext` 自 `<vscale x 16 x i4>` | `LLVM ERROR: Cannot scalarize scalable vector loads` | — |
| `trunc_rewritten` | aligned 改寫會產生的形式（deinterleave ＋ 位元運算） | 編得過 | 值全對 |
| `sext_rewritten` | aligned 改寫會產生的形式（位元運算 ＋ interleave） | 編得過 | 值全對 |

所以後端風險不成立，而且方向相反：**不改寫的形式後端直接報錯，改寫後的形式才編得過**。
這題從「效能改寫」變成「讓 scalable 子位元組向量能通過後端」。

### 11-28 審查：有兩種輸入不是被擋掉，是 assert 失敗（新題 S-1a）

上面「現況」寫的是「`commonConversionPrecondition` 第一行就擋 scalable」。在 MLIR 層實跑
`transform.apply_patterns.vector.rewrite_narrow_types`（會 abort 的兩種輸入存在 [`narrow-types-scalable-assert.mlir`](narrow-types-scalable-assert.mlir)）：

| 輸入 | 結果 |
|---|---|
| 固定長度：`bitcast vector<8xi8> → vector<16xi4>` ＋ `extsi → vector<16xi8>` | 改寫成 `shli`／`shrsi`／`vector.interleave` |
| scalable：只有 `extsi vector<[16]xi4> → vector<[16]xi8>` | 不變（被前置條件擋掉，符合上面的描述） |
| scalable：`bitcast vector<[8]xi8> → vector<[16]xi4>` ＋ `extsi` | **`mlir-opt` abort，rc=134** |
| scalable：`trunci vector<[16]xi8> → vector<[16]xi4>` ＋ `bitcast → vector<[8]xi8>` | **`mlir-opt` abort，rc=134** |

```
VectorEmulateNarrowType.cpp:1576: BitCastBitsEnumerator::BitCastBitsEnumerator(VectorType, VectorType):
Assertion `sourceVectorType.getRank() == 1 && !sourceVectorType.isScalable() && "requires -D non-scalable vector type"' failed.
```

原因：`RewriteExtOfBitCast` 與 `RewriteBitCastOfTruncI` 是**先建 `BitCastRewriter` 再檢查前置條件**
（`origin/main` 的 `:1996-1999`、`:2060-2063`），而 `BitCastRewriter` 的建構子會建 `BitCastBitsEnumerator`，
它一開頭就 assert 非 scalable（`:1577-1580`，2023-09 起就在）。所以這兩種形式輪不到前置條件說「scalable vector」。
沒有 assert 的 build 會怎樣**沒測**。

這兩種正好是實際會出現的形式（子位元組資料以 `i8` 向量載入，`bitcast` 成 `i4` 再擴展；或截斷後 `bitcast` 回 `i8`）。

**這一題拆成兩步**：

- **S-1a（新）：修 assert。** 在建 `BitCastRewriter` 之前先檢查 scalable 並 `notifyMatchFailure`。
  小、獨立、不依賴 #221185 的內容（但同一個檔，rebase 時要注意）。測試加在 `vector-rewrite-narrow-types.mlir`。
- **S-1b：原本的題目。** 讓 aligned 那組改寫收 scalable 向量。

**第 1 關比上表寫的強**：IREE 的 `compiler/src/iree/compiler/Codegen/Common/EmulateNarrowType.cpp` 與
`Codegen/SPIRV/ConvertToSPIRV.cpp` 呼叫 `populateVectorNarrowTypeRewritePatterns`（GitHub code search），
所以下游不只樹內那兩個呼叫者。IREE 在 SVE 目標上會不會真的走到 scalable 子位元組向量，**沒查**。
樹內則是**沒有任何測試**出現 scalable 的 `i2`～`i7` 向量型別（`grep` 0 筆），這個組合目前沒人測。

**原始碼重驗**：`commonConversionPrecondition` 在 `origin/main` 是 `:1617-1621`；aligned 那兩個 pattern 各自呼叫它
（`:2139` 與 `:2205` 附近）；`bitcastSubByteVectorToI8` 用 `VectorType::get(vecShape, i8)`，會丟 scalable 旗標——都與上面寫的一致。

**撞車**：

- S-1a：`BitCastBitsEnumerator`、`rewrite_narrow_types scalable`、`RewriteExtOfBitCast scalable` 的 PR／issue 搜尋，沒有相關的 open 項目。
- 同一個檔另有兩個 open PR：#199243（bjacob，`RewriteExtOfBitCast` 丟掉 sign extension，2026-05-27 後沒動）、
  #208873（qyingwu，Guard transfer read narrow type emulation，11-27 還在動）。
- 鄰近的活動：#245508、#245296 是 XeGPU 的 `i4`（固定長度）。
- **#221185 仍是 OPEN，沒有 approve**（11-28 查，最後更新 11-24）。

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

### 11-28 審查：RFC 的問題要改寫

- `StepOp::inferResultRanges` 對 scalable 直接 `return`：重驗無誤（`origin/main` `VectorOps.cpp:8641-8646`）。
- **上界在 IR 上已經有載體**：`func.func` 可以掛 `llvm.vscale_range`，`convert-func-to-llvm` 會認並轉到 `llvm.func` 的
  `vscale_range`（`Conversion/Passes.td:526-531`、`LLVMOps.td:2155`）。pass 選項是另一條路（`VectorTransforms.h:120` 的 `VscaleRange`）。
  所以問題不是「放 IR 還是 pass 選項」，而是「**`IntegerRangeAnalysis`／`ValueBounds` 要不要讀已經在 IR 上的 `llvm.vscale_range`**」，
  以及 `vector` 的 op 去讀 `llvm.` 開頭的屬性算不算破壞分層。
- 這一題與 `visibility-track-candidates.md` 的第 1 題**合成一題**：那邊實測過，`vscale` 只有下界時 `vscale * 8` 仍推不出非零，要有上界才有效果。
  順序從「先做 `vscale`，再做這個」改成「先定上界從哪裡來，再一起做 `vscale` 與 `step`」。
- 上游有沒有人談過：GitHub 的 PR／issue 搜尋 0 筆；Discourse 沒查到（搜尋被限流）。

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

### 11-28 審查

- **#159751 現況**：OPEN，「[mlir] Vectorize linalg.pack + linalg.unpack in the e2e tests」，
  2025-09-19 由 **banach-space 開、assignee 也是 banach-space**，之後只有一則 bot 留言，沒有人回。
- 兩個 TODO 重驗無誤：`ArmSVE/pack-unpack-scalable-inner-tile.mlir:34`、`ArmSVE/pack-unpack-mmt4d.mlir:46-47`
  （`ArmSME/pack-unpack-mmt4d.mlir:46` 也引用同一個 issue）。Cond 1 在 `Vectorization.cpp:2424-2428`，只放行 `UnPackOp`。
- 撞車：`vectoriz linalg.pack scalable`、`linalg.pack vectorization` 的 open PR 搜尋 0 筆。
- 鄰近的活動：#235596（chenmiaoming，scalable index 與 scalable forall tiling，11-24 merge）帶進一批
  `scalable-pack-*`／`scalable-unpack-*` 測試；pack／unpack 的向量化 11 月有 #239599（FedericoBruzzone）。
- **「去留言問」的對象就是 banach-space**——09-14 承諾的對象，09-13 講過量能不夠。這則留言等手上的 PR 消化掉一些再貼。

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

1. ~~先建 qemu-aarch64 ＋ SVE 的實跑環境，並用一段手寫 LLVM IR 驗 S-1 的後端風險。~~ ✅ 11-28 兩件都做完，S-1 不用降級。
2. **S-1 拆兩步**（11-28 審查）：S-1a 修 assert，小、可獨立送；S-1b 等 #221185 進了再開。#221185 目前 OPEN、沒有 approve。
3. ~~S-2 先做 `vscale` 那一半（另一份清單的第 1 題），不需要 SVE 環境，只要 lit。~~
   **11-28 審查**：`vscale` 只有下界沒有效果，S-2 與那一題合成一題，先回答「分析讀不讀 `llvm.vscale_range`」。
4. **S-3 不寫 code**；#159751 的 assignee 是 banach-space，留言的時機排在手上 PR 消化之後。
5. 以上都受 09-14 的承諾限制，現在不能開新 PR。

順帶一提：被看見線在 scalable 這個方向的題目**比預期少**。SVE 的支援是 Arm 團隊系統性做的，
剩下的缺口多半是他們判斷過「做不到」或「還沒有動機」的。要在這裡被看見，
review 他們的 PR 可能比找漏洞有效。

---

## 實跑環境（2026-11-28 建好）

**結構**：x86 的 `mlir-opt` 做 lowering，AArch64 版的 `mlir-runner` 在 `qemu-aarch64 -cpu max` 裡 JIT 執行。
全部免 root（sudo 要密碼，做法比照 `~/cuda`）。

| 東西 | 位置 |
|---|---|
| qemu 6.2（`qemu-aarch64-static`）＋ AArch64 sysroot | `~/aarch64-cross/sysroot`（`apt-get download` 抓 .deb 再 `dpkg-deb -x`） |
| 交叉編譯器 | 現有的 clang 14：`--target=aarch64-linux-gnu --sysroot=...`，toolchain 檔 `~/aarch64-cross/aarch64-toolchain.cmake` |
| AArch64 版 `mlir-runner`／`lli`／runner 函式庫 | `~/llvm-project/build-aarch64`（1.8G，9 核約 45 分鐘） |
| host build 新增的設定 | `LLVM_TARGETS_TO_BUILD=host;NVPTX;AArch64`、`MLIR_RUN_ARM_SVE_TESTS=ON`、五個 `ARM_EMULATOR_*` |
| 腳本 | `tools/sve-qemu/setup.sh`（`deps`／`smoke`／`cross`／`enable`／`test`），共用路徑在 `env.sh` |

**跑法**：

```bash
cd ~/llvm-project/build
./bin/llvm-lit -v tools/mlir/test/Integration/Dialect/Vector/CPU/ArmSVE tools/mlir/test/Integration/Dialect/Linalg/CPU/ArmSVE
```

**11-28 的結果**（checkout base `376f04dd8bdb`）：

- qemu `-cpu max` 有 SVE、SVE2、I8MM、BF16；smoke 測試在 128／256／512 bit 都過。預設向量長度 512 bit。
- 上游 ArmSVE 整合測試 **18／18 過**。
- 整個 `Integration/`：270 過、16 失敗、145 unsupported。16 個失敗全是 CUDA，和 11-01 記錄的那 16 個相同（WSL2 的 `gpu.host_register`）。
- 打開 SVE 之後，SparseTensor 等 107 個帶 `%mcr_aarch64_cmd`／`%lli_aarch64_cmd` 的測試也會在 qemu 下多跑 SVE 的 RUN 行；整個 `Integration/` 約 3 分鐘。

**要知道的三件事**：

1. **AArch64 的 runner 不用跟著 patch 重編。** 它只負責 JIT 執行 LLVM dialect；改 `mlir/lib` 的 patch 只要重編 host 的 `mlir-opt`。
   只有 LLVM dialect 的語法或 runner 函式庫變了才要 `ninja -C ~/llvm-project/build-aarch64 mlir-runner`。
   host 與 `build-aarch64` 不要同時跑 ninja（後者借用前者的 tblgen）。
2. **上游 7 個 ArmSVE 測試在模擬器下本來跑不起來。** 它們把 `%mlir_runner_utils`（host 的 x86 函式庫）傳給 AArch64 的 runner，
   正確的是 `%native_mlir_runner_utils`；第一次跑是 11 過 7 失敗，錯誤是 `cannot open shared object file`。
   本機的繞法：qemu 會優先開 `<-L 前綴>/<原路徑>`，所以在前綴底下放了指到 AArch64 函式庫的連結（`setup.sh` 的 `link_host_lib_paths`）。
   7 個檔：`Vector/CPU/ArmSVE/` 的 `compress`、`transfer-read-scalable-non-trailing`、`vector-contract-bfmmla`、`vector-contract-i8mm`；
   `Linalg/CPU/ArmSVE/` 的 `pack-scalable-inner-tile`、`pack-unpack-mmt4d`、`pack-unpack-scalable-inner-tile`。
   上游 main `f496863dad20`（11-28）仍是這樣。上游的 buildbot 是原生 SVE 機器，所以不會踩到。
   **這是一個改測試檔的小 patch 候選**（7 個檔各改一行）。撞車只用 `gh pr list --search` 查了兩組關鍵字，都是 0 筆，不算查完。
3. **qemu 6.2 沒有 SME。** `ArmSME/` 測試沒開（`MLIR_RUN_ARM_SME_TESTS=OFF`）。要跑 SME 得換新版 qemu。

