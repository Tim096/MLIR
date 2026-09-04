# TODO / 現況快照

> **這份文件的用途**：接續工作用的交接文件。
> 換一個 session、換一台機器、或隔了一個月回來，讀這份就能接上，不必翻聊天紀錄。
>
> 分工：
> - **`Goal.md`** = 為什麼這樣做（策略、決策、MLIR 背景知識、貢獻 SOP）——**改動頻率低**
> - **`TODO.md`**（本檔） = 現在在哪、下一步做什麼、有什麼還沒確認——**每次有進展就更新**
>
> 新 session 開場建議直接說：「讀 Goal.md 和 TODO.md，然後接續」。

最後更新：2026-09-05

---

## 一句話現況

**六個 commit 已進 upstream（#215123 09-04 中午 merge）。十五個 open PR：#215696 與 #221248 已 approve 等人按 merge，#217892 在 review，#221185（i2 trunci）09-04 送、#221268（`in_bounds` 要看索引）、#221288（WMMA elementwise 降 NVVM 崩潰）、#221293（`insert_slice` 向量化前置條件）、#221298（ext 折進 `vector.contract` 要同來源型別）、#221307（`convert-vector-to-scf` 拒收 `vector.mask` 裡的 transfer op）、#221308（AMDGPU maskedload 保留 `alignment`）、#221312（`gpu-decompose-memrefs` 保留 load／store 屬性）、#221314（`memref-elide-reinterpret-cast` 保留 load 屬性）、#221317（六個 vector folder 保留 `alignment`）、#221319（vector linearize 保留 load／store 屬性）與 #221320（`memref-emulate-wide-int` 補 `alignment`／`invariant`）09-05 送。**
**08-21 → 09-04 兩週三個 PR 都沒人回，09-04 全部 rebase 到當天 main、回掉 krzysz00 的 nit，再各 ping 一次；#215123 當天就進了，#221248 送出當天就被 approve。**
**⚠️ 原則不變：已 approve 未 merge 就禮貌 ping，每次都要帶新資訊。**

| PR | 內容 | 狀態（2026-09-04 實查） | CI |
|---|---|---|---|
| [#214622](https://github.com/llvm/llvm-project/pull/214622) | M0：`AtomicRMWKind` switch 窮盡（NFC） | ✅ **已 MERGE**（2026-08-09 15:03，merge commit `78e17e70bd52`） | — |
| [#214919](https://github.com/llvm/llvm-project/pull/214919) | M1-b0：`f8E8M0FNU` NaN 被折成 Inf | ✅ **已 MERGE**（2026-08-10 11:09 UTC，merge commit `794aa0fd923a`） | 全綠 |
| [#214637](https://github.com/llvm/llvm-project/pull/214637) | M1-a：`ceildivsi` MININT 折疊 | ✅ **已 MERGE**（2026-08-12 13:39 UTC，`kuhar` 代 merge，squash commit `2a0c335d4538`） | 全綠 |
| [#215123](https://github.com/llvm/llvm-project/pull/215123) | M1-b：`scaling_extf`/`scaling_truncf` 常數折疊 | ✅ **已 MERGE**（2026-09-04 12:01 UTC，`tgymnich` 代 merge，squash commit `57807585a6ae`）。09-04 上午 rebase ＋ ping，同日中午就進了。**第六個 commit** | 全綠 |
| [#215318](https://github.com/llvm/llvm-project/pull/215318) | M1-d：transfer permutation lowering 支援 masked op | ✅ **已 MERGE**（2026-08-13 16:20 UTC，`banach-space` 代 merge，squash commit `1ccdf48548ed`）。**第一個 vector commit** | 全綠 |
| [#215696](https://github.com/llvm/llvm-project/pull/215696) | 從 #214637 拆出：`ceildivs` INT_MIN 在 fold／兩個 index lowering／affine 展開／inference 全部一致 | ✅ **`kuhar` 08-14 APPROVED**，第二人（點名 `krzysz00`）三週未出現。09-04 純 rebase 到 `eac210e8d174`，head **`b55fb1c4d53b`**，approve 未消失 | 全綠 |
| [#216056](https://github.com/llvm/llvm-project/pull/216056) | 🆕 `APFloat::convert` 不回報 sign／zero 失真（含 crash） | ✅ **已 MERGE**（2026-08-17 09:21 UTC，`tgymnich` 代 merge，squash commit `898b0188d901`）。**第五個 commit，也是第一個不在 MLIR 而在 `llvm/lib/Support` 的**。issue #215445 同時自動關閉 | 全綠 |
| [#217892](https://github.com/llvm/llvm-project/pull/217892) | M1-e：`scaling_extf`／`scaling_truncf` 展開改用 scale 的值（`in / scale`） | 🔄 **review 中**。krzysz00 08-21 一個 nit ＋ 一則硬體補充，09-04 已回；head **`f2ab962761d9`**（base `eac210e8d174`，rebase 過 #216653） | 全綠 |
| [#221185](https://github.com/llvm/llvm-project/pull/221185) | M2-a：`arith.trunci` 到 `i2` 的 sub-byte 重寫（第二個 vector patch） | 🆕 **2026-09-04 送出**，head `a00b482bb9bc`，reviewer `dcaballe` | 跑中 |
| [#221248](https://github.com/llvm/llvm-project/pull/221248) | M2-b：轉置的 `transfer_write` → `subgroup_mma_store_matrix ... transpose`（第一個 GPU codegen patch） | ✅ **`mplatings` 09-04 15:54 APPROVED**（"LGTM"，送出當天、ping 後一小時內）。head `d3103c5cda5e`。沒 commit 權限，等人按 merge | 全綠 |
| [#221268](https://github.com/llvm/llvm-project/pull/221268) | M2-c：`createReadOrMaskedRead`／`Write` 推導 `in_bounds` 要看索引（修 `affine-super-vectorize` 標錯 `true`） | 🆕 **2026-09-05 送出**，head `9dbb2ccb28a9`（base `e33e88551902`），4 個檔案 +189/−35。CODEOWNERS 自動指派 `banach-space`、`nicolasvasilache`、`dcaballe`、`Groverkss`；留言（5543300681）另點名 `FedericoBruzzone`（#201180 作者） | 跑中 |
| [#221288](https://github.com/llvm/llvm-project/pull/221288) | M2-d：`gpu.subgroup_mma_elementwise` 降 NVVM——15 種運算 10 種 `llvm_unreachable`，補 8 種、依 PTX ISA 拒收 `extf`／`truncf`、擋 packed fragment（第二個 GPU codegen patch） | 🆕 **2026-09-05 送出**，head `704d5b9c54b2`（base `c7ba46e37d78`），4 個檔案 +233/−12。自動指派 `fabianmcg`；留言（5543974824）另點名 `grypp`、`kuhar`、`simpel01`（#182499 作者） | 全綠 |
| [#221293](https://github.com/llvm/llvm-project/pull/221293) | L-1：`tensor.insert_slice` 向量化——前置條件沒查 stride 與 rank-reducing 丟掉哪一維，strided／中間維度的 insert 被寫到錯的位置；加兩個 bail（第一個 Linalg patch） | 🆕 **2026-09-05 送出**，head `ae1f85cbb9d0`（base `08d499665a14`），3 個檔案 +88/−4。CODEOWNERS 自動指派 `banach-space`、`nicolasvasilache`、`dcaballe`、`Groverkss`；留言（5544240776）點名 `banach-space`（#122927 作者）、`hanhanW` | Linux／Windows 過，AArch64 跑中 |
| [#221298](https://github.com/llvm/llvm-project/pull/221298) | V-1：`FoldArithExtIntoContractionOp` 只查兩邊都是 ext、沒查來源型別，`extsi i8`＋`extsi i16`（或 `extf f16`＋`bf16`）折出過不了 verifier 的 `vector.contract`；補一個來源 element type 比較（第三個 vector patch） | 🆕 **2026-09-05 送出**，head `922af2916947`（base `f6a369fa4a57`），2 個檔案 +55/−0。CODEOWNERS 自動指派 `banach-space`、`nicolasvasilache`、`dcaballe`；留言（5544373520）點名 `raikonenfnu`（#96593 作者）、`banach-space`、`dcaballe` | 跑中 |
| [#221307](https://github.com/llvm/llvm-project/pull/221307) | VS-1：`convert-vector-to-scf` 的五個 transfer pattern 沒查自己是不是在 `vector.mask` 裡，展開的 loop／buffer 全塞進 mask region，`'vector.mask' op expects only one operation to mask`；每個 pattern 入口加 `isMasked()` 拒收（第二個 VectorToSCF patch） | 🆕 **2026-09-05 送出**，head `af0e5de00d82`（base `f6a369fa4a57`），2 個檔案 +87/−0。CODEOWNERS 自動指派 `matthias-springer`、`banach-space`、`nicolasvasilache`、`dcaballe`；留言（5544686298）點名 `banach-space`、`dcaballe`、`matthias-springer` | 跑中 |
| [#221308](https://github.com/llvm/llvm-project/pull/221308) | GPU-4：`amdgpu-maskedload-to-load` 重建 `vector.load`／`store` 時丟掉 `alignment`，LLVM 層退回 element 對齊（f16 從 `align 16` 變 `align 2`）；透過 builder 轉傳（第一個 AMDGPU patch，效能不是正確性） | 🆕 **2026-09-05 送出**，head `8378fb4c6fbd`（base `f6a369fa4a57`），2 個檔案 +48/−2。自動指派 `krzysz00`、`kuhar`；留言（5544719647）點名 `krzysz00`、`Groverkss`、`kuhar` | 跑中 |
| [#221312](https://github.com/llvm/llvm-project/pull/221312) | GPU-3：`gpu-decompose-memrefs` 重建 `memref.load`／`store` 時丟掉 `nontemporal`／`alignment`／`invariant`；改用帶三個屬性的 builder（第三個 GPU dialect patch） | 🆕 **2026-09-05 送出**，head `292a8a8cb25a`（base `f6a369fa4a57`），2 個檔案 +60/−2。自動指派 `fabianmcg`；留言（5544811835）點名 `Hardcode84`（pass 作者）、`kuhar`、`krzysz00` | 跑中 |
| [#221314](https://github.com/llvm/llvm-project/pull/221314) | M-1：`memref-elide-reinterpret-cast` 的 `RewriteLoadFromReinterpretCast` 重建 `memref.load` 時丟掉 `nontemporal`／`alignment`／`invariant`；改用帶三個屬性的 builder（#221312 同款） | 🆕 **2026-09-05 送出**，head `c63ecc0da80d`（base `f6a369fa4a57`），2 個檔案 +18/−1。留言（5544900426）點名 `ioghiban`（檔案作者）、`banach-space`（三個前 PR 的 approver） | 跑中 |
| [#221317](https://github.com/llvm/llvm-project/pull/221317) | VF-1：`VectorOps.cpp` 六個 canonicalization folder（maskedload／maskedstore／expandload／compressstore 全 true、gather／scatter contiguous）重建時丟 `alignment`；六處各加 `getMaybeAlign()` | 🆕 **2026-09-05 送出**，head `1b2aca62fe7e`（base `f6a369fa4a57`），3 個檔案 +98/−8。自動指派 banach-space／nicolasvasilache／dcaballe／Groverkss；留言（5545072108）點名 banach-space、dcaballe、kuhar。check-mlir 4588／16 同基準 | 跑中 |
| [#221319](https://github.com/llvm/llvm-project/pull/221319) | VL-1：`VectorLinearize.cpp` 的 `LinearizeVectorLoad`／`Store` 丟 `alignment`＋`nontemporal`；兩處轉發 | 🆕 **2026-09-05 送出**，head `2bb26b72e617`，2 個檔案 +28/−4。留言（5545099840）點名 nbpatel（pattern 作者）、newling（approver）、banach-space | 跑中 |
| [#221320](https://github.com/llvm/llvm-project/pull/221320) | M-2：`EmulateWideInt.cpp` 只轉 `nontemporal`，漏 `alignment`／`invariant`；改用 attr builder 全轉 | 🆕 **2026-09-05 送出**，head `7b2fa9a73327`，2 個檔案 +19/−2。留言（5545103709）點名 kuhar（pass 作者）、banach-space | 跑中 |

### 🔧 2026-09-05：第十～十二個 open PR——平行送三題（分支 `vector-to-scf-decline-masked`、`amdgpu-maskedload-keep-alignment`、`gpu-decompose-memrefs-keep-attrs`）

本人要求「能平行就平行」。做法：兩個 agent 各自只讀 tree、出 diff ＋ 測試 ＋ commit message 草稿（GPU-3、GPU-4），我同時查 GPU-2 與上次掃描標「域外」的 VectorToSCF 題；建置與驗證在同一個 build 目錄串行做，三個分支都從 `f6a369fa4a57` 開。

**GPU-2 查證後不是 bug，刷掉。** `OpCooperativeMatrixMulAddKHR` 本來就沒有 layout 參數，SPIR-V 的 layout 在 load／store 就消費掉；`a_transpose` 只是描述「operand 用 transpose 載入」，NVVM 需要它是因為 PTX 的 `wmma.mma` 要重述 fragment layout。SPIR-V 丟掉是對的。

**VS-1（#221307）**：`convert-vector-to-scf` 對 `vector.mask { vector.transfer_read/write }` 五條路徑（progressive、full-unroll、1-D、scalable transpose、tensor）全部把展開的 `memref.alloca`／`scf.for`／低階 transfer op 塞進 mask region，verifier 失敗；而且拆出來的 transfer op 一個 mask 都沒帶（`getMask()` 只看 operand）。先跑 `-lower-vector-mask` 就正常，in-tree 整合測試也都是這個順序。修法是五個 pattern 入口 `isMasked()` 就 `notifyMatchFailure`，與上週 alepot55 的 #216947（allocation scope 檢查）同款。四個負向測試、三個 RUN 前綴都比。check-mlir 4588 個／16 失敗與基準同一組。筆記 [`notes/vector-to-scf-decline-masked.md`](notes/vector-to-scf-decline-masked.md)。

**GPU-4（#221308）**：pass 比 `alignment` 屬性早一個月（2025-07 vs 2025-08），三個重建點只傳 base／indices。存取位址與寬度沒變，所以直接 `/*nontemporal=*/false, getMaybeAlign()` 轉傳（`AffineToStandard` 同款）。LLVM 層 `align 2` → `align 16`。in-tree 只有它自己的 lit 用這個 pass，使用者是 IREE。筆記 [`notes/amdgpu-maskedload-keep-alignment.md`](notes/amdgpu-maskedload-keep-alignment.md)。

**GPU-3（#221312）**：同型問題，`memref.load` 三個屬性、`store` 兩個屬性全掉；手寫 builder 沒有 `invariant`，改用 TableGen 生的 attr 版 builder。#217274 之後 `memref.load` 是 strict property assembly，測試要寫 `alignment(16) nontemporal(true) invariant(true)`。check-mlir 4588／16 同基準。筆記 [`notes/gpu-decompose-memrefs-keep-attrs.md`](notes/gpu-decompose-memrefs-keep-attrs.md)。

**已送出：[#221307](https://github.com/llvm/llvm-project/pull/221307)、[#221308](https://github.com/llvm/llvm-project/pull/221308)、[#221312](https://github.com/llvm/llvm-project/pull/221312)。十一個 open PR。**

### 🔧 2026-09-05：第十三個 open PR——#221314，GPU-3 的同款（分支 `memref-elide-rc-keep-attrs`）

前一輪就標記 `ElideReinterpretCast.cpp:622` 有一樣的 `replaceOpWithNewOp<memref::LoadOp>(op, src, idxs)`。Repro：`memref.load %rc[...] alignment(16) nontemporal(true) invariant(true)` 經 `-memref-elide-reinterpret-cast` 後三個屬性全掉。pattern 的前提（offset 0、非 unit dim 順序與大小一致、unit dim 索引為 0）保證改寫前後是同一個元素，所以三個屬性直接轉發。一行改、一個測試，`Dialect/MemRef` 33 個 lit 全過。這一輪同時放兩個 agent 掃 `mlir/lib` 裡其他重建 `memref.load/store`、`vector.load/store/maskedload/...` 的地方，看還有沒有同款。筆記 [`notes/memref-elide-rc-keep-attrs.md`](notes/memref-elide-rc-keep-attrs.md)。

**已送出：[#221314](https://github.com/llvm/llvm-project/pull/221314)。十二個 open PR。**

### 🔧 2026-09-05：第十四～十六個 open PR——全樹掃「重建 op 丟屬性」，一次送三個（分支 `vector-fold-keep-alignment`、`vector-linearize-keep-attrs`、`memref-emulate-wide-int-keep-attrs`）

#221312／#221314 同款的問題不會只有兩處。兩個 agent 平行只讀 tree：一個掃 `memref.load/store` 的重建點，一個掃八個 vector 記憶體 op 的重建點，判準是「來源有屬性、新 op 同類、位址不變」。結果在 [`notes/attr-drop-sweep.md`](notes/attr-drop-sweep.md)：轉發無爭議的還有十一處，位址會移、要重算 alignment 的另有四組。

這輪挑三組送：**VF-1（#221317）** 是 `-canonicalize` 裡的六個 folder，影響面最大（每條 pipeline 都跑），六個 op 都實作 `AlignmentAttrOpInterface` 所以一律 `getMaybeAlign()`，跑完整套 check-mlir；**VL-1（#221319）** 兩行，XeGPU 是主要使用者，連帶跑 XeGPU／VectorToXeGPU／VectorToLLVM 共 145 個 lit；**M-2（#221320）** 是「部分轉發」（2023 年接了 `nontemporal`，後來的兩個屬性沒人接），最好答。三個分支都從 `f6a369fa4a57` 開，建置與 lit 串行。

沒送的：`VectorUnroll` gather、`LowerVectorMask` gather、bufferization gather／scatter、`StoreOpFromBroadcast` 四處也是位址不變，**等 #221317／#221319 的意見再送**，同一批 reviewer 一天內收太多會反感。`ExtractOpFromLoad`／`UnrollLoad/Store`／兩個 narrow-type emulation 位址會移，alignment 要 `min(align, offset)`，是另一種題。另外 `LowerVectorGather.cpp:297` 是反向（把 gather 的 alignment 抄到 data-dependent 的 scalar load 上），要先弄清 gather alignment 的語意。筆記 [`notes/vector-fold-keep-alignment.md`](notes/vector-fold-keep-alignment.md)、[`notes/vector-linearize-keep-attrs.md`](notes/vector-linearize-keep-attrs.md)、[`notes/memref-emulate-wide-int-keep-attrs.md`](notes/memref-emulate-wide-int-keep-attrs.md)。

**已送出：[#221317](https://github.com/llvm/llvm-project/pull/221317)、[#221319](https://github.com/llvm/llvm-project/pull/221319)、[#221320](https://github.com/llvm/llvm-project/pull/221320)。十五個 open PR。**

**下一題**：候選清單剩 L-2（`DecomposeOuterUnitDimsPackOpPattern` 的 padding bail，中等設計風險，先 @ #218141 作者）與 V-2（價值最低）；`ElideReinterpretCast.cpp:622` 的同款已送出為 #221314。

### 🔧 2026-09-05：第九個 open PR——ext 折進 `vector.contract` 要同來源型別（分支 `vector-fold-ext-contract-same-type`）

`notes/gpu-linalg-patch-candidates.md` 的 V-1，填充題。`FoldArithExtIntoContractionOp`（`9a795f0c59b1` 加、#96593 template 化成也吃 `extsi`）
只檢查 contract 兩個 operand 都來自同一種 ext op，沒比較兩個 ext 的來源 element type；
`extsi i8→i32` 配 `extsi i16→i32` 一折，新的 contract 直接拿 i8／i16 當 lhs／rhs，`'vector.contract' op failed to verify that lhs and rhs have same element type`，`extf f16`／`bf16` 同樣。
修法是在 `replaceOpWithNewOp` 前用 `getElementTypeOrSelf` 比兩邊 `getIn()` 的 element type，不同就 `notifyMatchFailure`——只比 element type 是因為 verifier 的要求就只有這一項（shape、scalable 本來就可以不同）。

驗證：兩個重現案例改動後保留 ext、contract 不變；`Dialect/Vector`＋`Conversion/VectorToGPU`＋`transform-op-vectorize` 105 個 lit 全過；check-mlir 4218 過／16 失敗（與基準同一組環境失敗）。
答辯筆記 [`notes/vector-fold-ext-contract-same-type.md`](notes/vector-fold-ext-contract-same-type.md)，PR 描述稿 `patches/vector-fold-ext-contract-same-type-pr-body.md`，ping 稿 `patches/221298-reviewer-ping.md`。

**已送出：[PR #221298](https://github.com/llvm/llvm-project/pull/221298)。第九個 open PR，8 行程式 ＋ 47 行測試。**

**下一題**：~~GPU-2~~ → 查證後不是 bug（見上一節），改送 VS-1／GPU-3／GPU-4。

### 🔧 2026-09-05：第八個 open PR——`insert_slice` 向量化的前置條件（分支 `linalg-insert-slice-vectorize-precondition`）

`notes/gpu-linalg-patch-candidates.md` 的 L-1。`vectorizeAsInsertSliceOp`（#122927，banach-space）把整個 source 讀成一個 vector，再用 minor identity map 寫到 offset；
前置條件沒查 stride、也沒查 rank-reducing 丟掉的是哪一維，所以 stride `[3,1]` 的 insert 被寫成連續兩列、`8x4` 插進 `8x1x4` 只留第 0 列。
同檔案舊的 `PadOpVectorizationWithInsertSlicePattern` 本來就有這兩個檢查。

**選最小修法**：前置條件加 `hasUnitStride()` bail ＋ `getDroppedDims().find_last() >= rankDiff` bail（`getDroppedDims` 從尾端配對，所以「dropped dims 全在最前面」＝「source 對到 dest 最內層」）。
完整修法要動 `createWriteOrMaskedWrite` 的 mask 尺寸計算，會和 #221268 撞，之後另開。
試過順手刪死掉的 `readIndices`，會讓 `insert-slice.mlir` 五個既有測試的 SSA 名稱位移，還原了。

驗證：五個重現案例全改成 `Attempted to vectorize, but failed`；`Dialect/Linalg`＋`Tensor`＋`Vector` 306 個 lit 全過；check-mlir 4218 過／16 失敗（與基準同一組環境失敗）。
答辯筆記 [`notes/linalg-insert-slice-vectorize-precondition.md`](notes/linalg-insert-slice-vectorize-precondition.md)，PR 描述稿 `patches/linalg-insert-slice-vectorize-precondition-pr-body.md`，ping 稿 `patches/221293-reviewer-ping.md`。

**已送出：[PR #221293](https://github.com/llvm/llvm-project/pull/221293)。第八個 open PR，第一個 Linalg patch。**

**下一題**：~~V-1~~ → 已送出 #221298；之後 GPU-2（SPIR-V compute 路徑轉置）。

### 🔧 2026-09-05：第七個 open PR——WMMA elementwise 降 NVVM 崩潰（分支 `gpu-wmma-elementwise-nvvm`）

候選清單前三名送完後做的**第二次掃描**（GPU 轉換層 ＋ Linalg 向量化，兩路並行），結果在 [`notes/gpu-linalg-patch-candidates.md`](notes/gpu-linalg-patch-candidates.md)。
GPU 那路第一名最硬：`WmmaOpsToNvvm.cpp:365` 的 `createScalarOp` 只有 5 個 case，`default: llvm_unreachable`，
`gpu.subgroup_mma_elementwise` 另外 10 種（`addi`／`subf`／`subi`／`muli`／`divs`／`divu`／`negatef`／`negates`／`extf`／`truncf`）全部 abort（本機 rc=134 逐一實測）。
`convert-vector-to-gpu` 會把 `arith.subf`／`negf`／`truncf`… 都轉成這個 op，所以 matmul ＋ bias 減法的 kernel 進 `-gpu-lower-to-nvvm-pipeline` 就崩；
`vector-to-mma-ops.mlir` 的 `cast_f32_to_f16_write` 產出的 IR 餵 NVVM 就是這樣。SPIR-V 側 12 種都有。
另一個症狀：`addf` 在 tf32 A-fragment 上產生 `llvm.fadd` on `i32`，verifier 報錯。

**PTX ISA 兩條規則定了做法**（§9.7.15.4.1「Manipulating fragment contents」）：逐暫存器一致運算、順序不變 → 8 個算術運算可以做；
「.f16 與 .f32 累加器 fragment 的轉換兩個方向都不支援，結果未定義」→ `extf`／`truncf` **不可能做**，改成 `notifyMatchFailure`（在建任何 op 之前，因為測試有 `allow-pattern-rollback=0`）。
packed fragment（s8／u8／tf32 multiplicand 的暫存器是 `i32`）用 `getElementTypeOrSelf(registerType) != matrixType.getElementType()` 擋。
`negates` 用 `0 - x`（LLVM 沒整數 neg）。沒動 VectorToGPU：它 target-agnostic，SPIR-V 路徑這兩個 op 是合法的。

commit `704d5b9c54b2`（基準 `c7ba46e37d78`）。測試：`wmma-ops-to-nvvm.mlir` 加 f16 `subf`＋`negatef`、i32 六種整數運算；
新檔 `gpu-to-nvvm-invalid-wmma-elementwise.mlir` 四個拒收案例；整合測試 `TensorCore/wmma-matmul-f16-elementwise.mlir`
走 `convert-vector-to-gpu` → NVVM pipeline，A[i][j]=j、C[i][j]=i，算 `-(C - (A·A + C))`，**改動前同一行 abort，改動後 RTX 3070 印出每列 `[-0, 120, …, 1800]`**。
驗證：GPUToNVVM／GPUToSPIRV／VectorToGPU／Dialect/GPU lit 全過；`check-mlir` **4220 passed / 16 failed**，16 個和基準完全相同（WSL2 環境）。
答辯筆記 [`notes/gpu-wmma-elementwise-nvvm.md`](notes/gpu-wmma-elementwise-nvvm.md)，PR 描述稿 `patches/gpu-wmma-elementwise-nvvm-pr-body.md`，ping 稿 `patches/221288-reviewer-ping.md`。

**已送出：[PR #221288](https://github.com/llvm/llvm-project/pull/221288)。第七個 open PR。** reviewer 人選：`fabianmcg`（GPU dialect，merge 了 fp64 extension）、`grypp`（NVVM CODEOWNER）、`kuhar`、`simpel01`。

**下一題已定**：`notes/gpu-linalg-patch-candidates.md` 的 L-1（`tensor.insert_slice` 向量化對 rank-reducing／strided 產生錯 IR，三種錯法已重現），
填充題 V-1（`FoldArithExtIntoContractionOp` 混寬 ext 過不了 verifier，~12 行）。

### 🔧 2026-09-05：第六個 open PR——`in_bounds` 推導要看索引（分支 `affine-vectorize-in-bounds-index`）

候選清單第三名。動手前重驗：`VectorUtils.cpp:479/484/547/552` 四行 FIXME 還在（2026-06 #202766 搬進來的，原判斷是 #201180，FedericoBruzzone）。
**撞車實查**：#215340（dhairyashilRG）已改成 opt-in pass `-vector-infer-in-bounds`，只把 `false` 變 `true`，修不到錯誤的 `true`；
討論串裡 banach-space 對「在 create 時做分析」的顧慮是成本，dhairyashilRG 08-19 說「刪 FIXME 要在 create 時做 index-aware 計算」但沒認領。
Discourse RFC「移除 `in_bounds`」（08-25 起）dcaballe 說推導「quite load bearing」，短期不會拆。結論：不重疊，直接做。

**這題不是清 FIXME，是可重現的錯誤**。三個 repro（V = 8，memref<16xf32>）：`0 to 15` 讀 `%A[%i + 1]` 第二次讀 9..16；
`4 to 16` 讀 `%A[%i]` 第二次讀 12..19；兩個都標 `in_bounds = [true]`，`-convert-vector-to-llvm` 後是無遮罩 `llvm.load`。
推導：純量合法給 `0 <= idx < D`，加 `D % V == 0` 還要 **`idx ≡ 0 (mod V)`** 才推得出 `idx + V <= D`，缺的就是這條。
`SuperVectorize.cpp` 設計說明的「always full tile」靠 `vector.transfer` 越界語意處理尾端，所以 trip count 不整除在契約內，`false` 是尾端的保護。

commit `9dbb2ccb28a9`（基準 `e33e88551902`）：`computeInBoundsFromPermutationMap` 多收 indices；新 static helper `isKnownMultipleOf`
（常數／`affine.for` IV 的 step 與下界／`affine.apply` 的 map，遞迴走下界 operand，把已知倍數的 operand 換成 `factor * d` 再用 `AffineExpr::isMultipleOf`）。
沒用 `ValueBoundsConstraintSet`：要證的是整除不是上下界，而且這樣是 O(巢狀深度) 的語法走訪，回應 banach-space 的成本顧慮。
`AffineOps.cpp:659` 有個 static 版但下界 map 不遞迴 operand，tiled matmul 的 `#map(%i)` 會算成 1，會讓 #201180 的 `MATMUL-COUNT-3` 退化，所以自己寫。
無 map 分支的 FIXME 留著（樹裡走那條的索引都是零，或是 `insert_slice` offset，verifier 已保證）。

測試：新檔 `vectorize_1d_inbounds.mlir` 6 個 case（偏移／對齊偏移／未對齊下界／對齊下界／tiling 形狀正反各一）；
`vectorize_affine_apply.mlir` 的 `vec_affine_apply_2`（索引 `d0 mod 16 + 1`）原 CHECK 期望 `true` 是錯的，改成無屬性。
答辯筆記 [`notes/vector-in-bounds-indices.md`](notes/vector-in-bounds-indices.md)，PR 描述稿 `patches/vector-in-bounds-indices-pr-body.md`。

驗證：Affine／Linalg／Vector lit 348/348；`vectorize_2d_inbounds.mlir` 的 tiled matmul 仍 4 個 `true`；
`check-mlir` **4219 passed / 16 failed**，16 個全在 `Integration/GPU/CUDA/`（15 個 `gpu.host_register`、1 個缺 `nvdisasm`），是 WSL2 環境問題，和 patch 無關。
（整合測試開了之後 check-mlir 的基準就是這樣：4219 pass ＋ 這 16 個。）

**已送出：[PR #221268](https://github.com/llvm/llvm-project/pull/221268)**，ping 稿 `patches/221268-reviewer-ping.md`。**第六個 open PR。**

### 🔧 2026-09-04：第五個 open PR——`VectorToGPU` 轉置 store（分支 `vector-to-gpu-transposed-store`）

候選清單第二名，動手前重驗：`VectorToGPU.cpp:213` 的 TODO 還在，`:642` 還是硬寫 `UnitAttr()`；
open PR 只有 #218226（alepot55，改 scf.yield 判斷 4 行 ＋ 測試附在檔尾）碰同一個檔，不重疊。
歷史：TODO 是 2021-06 原始 pass（`edd9515bd125`）留的，store 的 `transpose` 屬性 2022-12（`3d35546cd168`）就加了，
read 側 2026-02（`18ecdbfe6c74`，mplatings）重寫時只做了 read。

commit `defdf4e2b54b`（基準 `087826d491ea`），2 個檔案 +57/−8：`transferWriteSupportsMMAMatrixType` 從
「第二個結果是最內層」改成和 read 側同一行 `is_contained`；`convertTransferWriteOp` 重用 `isFirstResultLastMapDimension` 設屬性。
stride helper 不用動，read 側重寫時它已經只看 dim 位置。
測試鏡射 read 側四個：`write_transpose`（ld 3）、3-D（21／3）、4-D（231／33）、`no_convert_write_transpose_not_last_dim`。
答辯筆記 [`notes/vector-to-gpu-transposed-store.md`](notes/vector-to-gpu-transposed-store.md)，PR 描述稿 `patches/vector-to-gpu-transposed-store-pr-body.md`。

驗證：lit VectorToGPU 3/3、`check-mlir` **3965 passed / 0 failed**、clang-format 無差異。
端到端追屬性：轉出的 `subgroup_mma_store_matrix ... transpose` 再過 `-convert-gpu-to-nvvm`
得到 `nvvm.wmma.store ... layout = <col>`，語意和 `transfer_write` 的 `(d1, d0)` 一致（`(i, j)` 放 `base + j * ld + i`）。

**真的在 GPU 上跑過**：本機有 RTX 3070（sm_86），當天把 CUDA 12.8 redist 解到 `~/cuda`（不用 root）、
build 加 NVPTX target 並開 `MLIR_ENABLE_CUDA_RUNNER`／`MLIR_RUN_CUDA_TENSOR_CORE_TESTS`（細節在記憶 `local-gpu-and-cuda-toolchain`）。
新增整合測試 `mlir/test/Integration/GPU/CUDA/TensorCore/wmma-transposed-store-f16.mlir`：A[i][j] = 16i + j，
kernel 用 `transfer_read` → `addf` → 轉置 `transfer_write`，經 `convert-vector-to-gpu` ＋ NVVM pipeline，印出 B = 2·Aᵀ，lit PASS。
⚠️ WSL2 上 `gpu.host_register` 會 `CUDA_ERROR_ILLEGAL_ADDRESS`（上游 `wmma-matmul-f16/f32` 因此在本機 FAIL，bare-ptr 那個 PASS），
所以測試用 `gpu.alloc`／`gpu.memcpy`。另外零向量常數放在 launch 裡會被搬出去變 kernel 參數而 lower 失敗，所以用 `addf %A, %A`。

**已送出：[PR #221248](https://github.com/llvm/llvm-project/pull/221248)**（head `d3103c5cda5e`，base `a1ec06e04bc1`，3 個檔案 +150/−8）。
**第五個 open PR，第一個 `mlir/lib/Conversion/` 的 GPU codegen patch。**

### 📌 2026-09-04：兩週沒人回，三個 PR 全部 rebase，回 nit，再 ping

**先實查，不是憑感覺**：08-21 之後三個 PR 一則回應都沒有；三個 reviewer 都活躍
（`gh api users/<u>/events/public`），純粹是排不進優先序。唯一的動靜是
**krzysz00 08-21 在 #217892 留了兩則**（我當天沒看到）：

| 留言 | 內容 | 09-04 處理 |
|---|---|---|
| inline [3832259652](https://github.com/llvm/llvm-project/pull/217892#discussion_r3832259652) | nit：測試別寫死 `%arg0`，改在 `SCHECK-LABEL` 下用 `SCHECK-SAME` 抓引數 | 13 個本 patch 碰到的測試改成 `SCHECK-SAME: %[[ARG0:.+]]: ty, %[[ARG1:.+]]: ty`；沒碰的 `f8E8M0FNU` 測試留原樣，diff 不擴大。回覆 [3932465013](https://github.com/llvm/llvm-project/pull/217892#discussion_r3932465013) |
| top-level 5373010733 | `cvt.scalef32` 硬體讀的是 f32 scale 的 **bits 31:23**（sign＋exponent），尾數直接丟 | 承認這確定了 E5M3 scale 在 generic／硬體兩條路徑的**值**分歧；主張 follow-up 走 option 1（只對 `f8E8M0FNU` scale 或明確 `toward_zero` truncf 才用指令），除非他要放這個 PR。回覆 [5538147997](https://github.com/llvm/llvm-project/pull/217892#issuecomment-5538147997) |

**三個 rebase（都先開 `backup/*-prerebase-0904`）**：

| PR | 舊 head → 新 head | 上游在這兩週動到的相關檔 | 衝突 |
|---|---|---|---|
| #217892 | `2b11b90c3675` → **`f2ab962761d9`** | #216653 在 `ExpandOps.cpp` **同一個位置**加了 F8E5M2／F8E4M3FN 四個 converter | add/add 一個：上游四個 converter 在前、我的 `castFloatValue` 在後，兩塊照序放 |
| #215696 | `358a393a` → **`b55fb1c4d53b`** | `InferIntRangeCommon.cpp` 四個 NFC 搬動（#221070、#221081–#221083），都不在 `inferCeilDivS` | 無；4 個 patch-id 全同，證明是純 rebase |
| #215123 | `96dfbf939686` → **`7f575d426089`** | `ArithOps.cpp` 兩次（#217031、#218324），都不靠近這個 folder | 無；純 rebase，clang-format 乾淨 |

**驗證**：#217892 `check-mlir` **3965 passed / 0 failed**；#215696 相關 lit 7/7；
#215123 重編 mlir-opt ＋ `canonicalize.mlir`／`expand-ops.mlir` PASS。
三個 force-push 都用 `--force-with-lease=refs/heads/<b>:<舊 sha>`，兩個 approve 都留著
（LLVM 不會因 force-push 撤 stale approval）。

**ping**：稿子在 `patches/215123-second-ping.md`、`patches/215696-second-ping.md`，
內文寫「premerge 在新 head 已綠」，**所以要等 CI 真的綠才貼**，不能先講。
（#217892 不 ping，krzysz00 09-04 剛被回，換他。）

| PR | premerge | ping |
|---|---|---|
| #215696 | 10 pass / 2 skipping | [5538865558](https://github.com/llvm/llvm-project/pull/215696#issuecomment-5538865558) |
| #215123 | 10 pass / 2 skipping | [5539084402](https://github.com/llvm/llvm-project/pull/215123#issuecomment-5539084402) |

**這輪踩到的工具問題**：
- `gh pr view --json headRefOid` 不存在，要用 `gh api repos/llvm/llvm-project/pulls/N`。
- 這版 git 的 `git merge-tree --write-tree` 直接 exit 128，不能乾跑合併，只能真 rebase 再看。
- 同一個 rebase 過程中 `origin/main` 自己從 `46dabd2f3a82` 前進到 `eac210e8d174`（23 個 commit，有東西在自動 fetch），
  所以 #215123 的 base 比另外兩個新，無害。
- 只有一個 build dir，ninja／lit 在跑時不能 checkout 別的分支，三個 PR 只能串行。

### 🔧 2026-09-04：下一題開工——`arith.trunci` 到 `i2`（分支 `vector-trunci-i2`）

候選清單第一名（`notes/vector-patch-candidates.md`），動手前重驗：TODO 還在 `VectorEmulateNarrowType.cpp:2208`，
08-21 之後該檔零 commit，open PR 搜 `trunci i2`／`"narrow type" i2` 無撞車。

commit `a00b482bb9bc`（基準 `eac210e8d174`），3 個檔案：新 helper `rewriteI8ToI2Trunc`（兩層 deinterleave → mask → shift → or → bitcast）、
拿掉 bail、lit 測試 4 個 case（no_match 翻正向）、整合測試加 `@ftrunc_i2`。
答辯筆記 [`notes/vector-trunci-i2.md`](notes/vector-trunci-i2.md)，PR 描述稿 `patches/vector-trunci-i2-pr-body.md`。

驗證：lit 130/130（Vector＋Arith）、整合測試兩條 RUN 手動跑 PASS（本機 build 的 `MLIR_INCLUDE_INTEGRATION_TESTS` 是 OFF，
所以 check-mlir 不會跑它，要自己用 `mlir-runner` 跑）、**256 個 byte 值窮舉：重寫／不重寫／手算三者相同**。
`check-mlir` **3965 passed / 0 failed**（617 unsupported、1 expectedly failed）。

**已送出：[PR #221185](https://github.com/llvm/llvm-project/pull/221185)**（head `a00b482bb9bc`，base `543ac0371f32`），
自動指派 reviewer `dcaballe`（i4 trunc 原作者，#82565）。**第四個 open PR。**

### 🔬 2026-08-21：派三個 agent，敵意 review 抓到三個真缺陷

本人指示派 agent 協助。因為 **M1 的完成條件已經達標**（4 個實質 patch merged、
其中 3 個過第 1、2 關），力氣沒有放在「再送幾個 PR」，而是放在**保護已送出的品質**
＋ **把下一批題目備好**。

| Agent | 任務 | 結果 |
|---|---|---|
| A | 對 #217892 做**敵意 review**（明確要求找缺陷，且每條都要實跑驗證） | 3 個真缺陷，其中 1 個打掉核心論證 |
| B | 掃 `vector` 全部 TODO，過第 1、2 關 ＋ 撞車查證 | 5 個過關候選、10 類刷除理由 → [`notes/vector-patch-candidates.md`](notes/vector-patch-candidates.md) |
| C | 從 LLVM 樹裡查 `V_CVT_SCALEF32_*` 讀不讀 scale 的尾數 | **樹裡就有答案**，16 處 |

### ⚠️ 2026-08-21：#217892 的核心論證是錯的 —— `arith.convertf` 早就存在

**這是這一輪最該記住的一條。**

我在 `castFloatValue` 裡寫「同寬但不同型的轉換**無法拼寫**，所以 bail」，
並據此寫了兩個負向測試、以及 commit message 裡一整段論證。

**`arith.convertf` 在 2026-03 就進樹了**（PR #188041，`ArithOps.td:1603`），
summary 一字不差就是 "cast between floating-point types of the same bitwidth"，
description 還明講它涵蓋 `extf`／`truncf` 做不到的情況。

**它就在我編輯的那兩段 op description 往下約一百行的位置。**

**錯在哪裡**：我在寫「這個轉換不存在」之前，**沒有去搜樹上有沒有這個轉換**。
這和 08-21 稍早那次「只驗證一半就寫成全稱」是同一類——
**對「不存在」的宣稱，成本最低的驗證方式就是 grep 一次。**

自我檢查句再加一條：**「我說某個東西不存在之前，搜過了嗎？」**

### ✅ 2026-08-21：#217892 三個缺陷全部修好並 force-push（head `2b11b90c3675`）

| 缺陷 | 嚴重度 | 處理 |
|---|---|---|
| `arith.convertf` 早就存在，bail 的理由是假的 | **致命**（reviewer 三分鐘會發現） | 同寬改成產 `arith.convertf`；兩個測試從負向翻正向 |
| 純量 scale 配 shaped 運算元**產出過不了 verifier 的 IR**（實跑確認）。既有 bug，但我把舊碼唯一處理 shape 的 `cloneToShapedType` 刪掉了 | 真 bug | 加 shape 檢查 → `notifyMatchFailure`；每個 op 補一個負向測試 |
| `truncf` 分支**零測試覆蓋**——改成 `failure()`／`ExtFOp`／拿掉 fastmath 測試都不會紅 | 覆蓋漏洞 | 補 f32 scale ＋ `to_nearest_even fastmath<fast>` 測試，同時 pin 住「rounding mode 屬於結果的 cast，不屬於 scale 的 cast」 |

**沒有自己拍板的一條**：「E8M0 scale 逐字不變」在**窄運算型別**下被推翻。
`arith.scaling_truncf %a, %s : f8E8M0FNU, f8E8M0FNU to f4E2M1FN` 現在展開成
`arith.divf ... : f8E8M0FNU`（無號、無零的型別裡做除法），**能過 verifier 但撐過
`-convert-arith-to-llvm` 沒被降下去**；舊碼在同樣輸入產出過不了 verifier 的 `extf`。
「用 verifier 錯誤換無聲無法 lower 的 IR」不是改善，但真正的問題是
**這個 op 該不該接受 `f8E8M0FNU` 當運算元型別**——那是 op owner 的決定。
已在 PR 上點名 `@umangyadav` 問，沒有自己選邊。

驗證：`check-mlir` **3906 passed / 0 failed**、`clang-format` 乾淨。
留言：[5369893540](https://github.com/llvm/llvm-project/pull/217892#issuecomment-5369893540)（主動承認 `convertf` 是自己漏查）。

> 💡 **`gh pr edit --body-file` 又踩到 projects-classic 的坑**（描述長度沒變 = 沒寫入）。
> 可用的寫法：`python3` 組 JSON → `gh api -X PATCH repos/.../pulls/<n> --input <file>`。
> TODO 早就記過這條，這次還是先踩了才想起來。

### 🔎 2026-08-21：`ArithToAMDGPU` 的尾數問題，樹裡就有答案

`mlir/include/mlir/Dialect/LLVMIR/ROCDLOps.td` 對每個 `cvt.scalef32` op 都寫著
「multiplying／dividing by **the exponent part of** `scale`」——**16 處，全部一致**
（`:2952` 是 `packed_scaled_trunc` 變成的那個，`:2996` 是 `scaled_ext_packed` 的）。
且 `ArithToAMDGPU.cpp` 對 scale 型別**零限制**（整檔沒有一個 `E8M0` 字樣，
對比 `ExpandOps.cpp:682` 會 bail），gating 是 `*maybeChipset == kGfx950`（注意是 `==` 不是 `>=`）。

**這對我自己的 patch 不利，所以更要主動講**：在 `in / scale` 的讀法下，
generic expansion（改完後用完整的值）與硬體路徑（只用 exponent）**在「值」上分歧**，
不只是 rounding 不同。**我的 patch 把 #215295 的分歧修好一半、讓另一半變得更大。**

已在 PR 上寫明，並列出兩個收尾方式讓 reviewer 選，沒有自己決定：
[5369761220](https://github.com/llvm/llvm-project/pull/217892#issuecomment-5369761220)。

### 📌 2026-08-21：三個都沒人理，各 ping 一次（都帶新資訊）

**先查證不是我們的問題**：

| | 我方最後發聲 | 對方回應 | CI | mergeable |
|---|---|---|---|---|
| #215123 | 08-18 02:28 | 無 | 10 項全 success | `clean` |
| #215696 | 08-16 16:58 | 無 | 10 項全 success | `clean` |
| #215295 | 08-18 02:03 | 無 | — | — |

**三個 reviewer 都不是消失，是很活躍**（`gh api users/<u>/events/public`）：
08-18 起 `krzysz00` 100+、`kuhar` 100+、`tgymnich` 21 個公開事件，最新都在 08-20 深夜。
純粹是我們排不進優先序。

送出的三則：

| 對象 | 帶的新資訊 | 連結 |
|---|---|---|
| #215123 | **premerge 在 rebase 後的 head 已全綠**（上次留言時還在跑） | [5365939241](https://github.com/llvm/llvm-project/pull/215123#issuecomment-5365939241) |
| #215696 | approve 滿一週、第二人始終沒出現；**把問題丟回 kuhar**「一個 approve 夠不夠，還是有特定人要等」 | [5365939407](https://github.com/llvm/llvm-project/pull/215696#issuecomment-5365939407) |
| #215295 | 從「請確認」改成**「沒人反對我就開始寫」**，並附上 patch 會動與不會動的範圍 | [5365939570](https://github.com/llvm/llvm-project/issues/215295#issuecomment-5365939570) |

### ⚠️ 2026-08-21：上面那則寫錯一句，已發更正

我寫「every existing test keeps its numbers」——**錯的**。那只對 `f8E8M0FNU` scale 成立，
而我只驗證了那一半就寫成全稱。實查 `expand-ops.mlir`：**8 個測試的 scale 不是 E8M0，全部會變**。

| 類型 | 測試 |
|---|---|
| 6 個會改形狀（現在斷言 `arith.truncf ... to f8E8M0FNU` 那一步） | `scaling_truncf_propagate_rounding_mode_fast_math`、`scaling_truncf_f16_to_f4E2M1FN_using_f16_scales`、`scaling_truncf_vector_f16_to_f4E2M1FN_using_f16_scales`、`scaling_extf_to_f32_using_f16_scales`、`scaling_extf_vector_to_f32_using_f16_scales`、`scaling_extf_vector_to_f32_using_f16_scales_fastmath` |
| 2 個會反轉（現在斷言 `f8E5M2FNUZ` scale 無法 legalize） | `invalid_scaling_truncf_to_f4E2M1FN`、`invalid_scaling_extf_to_f32` |

更正留言：[5365951028](https://github.com/llvm/llvm-project/issues/215295#issuecomment-5365951028)。

**這 6 個測試等於是樹上對 exponent-only 讀法的白紙黑字**，所以更該等 tgymnich 表態再送。

**教訓（已符合既有記憶 `match-upstream-style-not-my-own`）**：
只驗證了一半就寫成全稱，正是 kuhar 08-14 抓過的同一類錯。
自我檢查句要多一條：**「我實際跑過的範圍，等於我寫的範圍嗎？」**

### ❌ 2026-08-21：舊 M1-c（`vector.extract` dynamic position）評估後放棄

撞車查證乾淨（最接近的 #115808、#171198 都停在 2026-03-26），**但兩個前提都被推翻**：

**① 筆記寫的「四處是同一個缺口」是錯的**——今天的 main 有 **10 處**，分屬 **5 個不同 folder**，
而且能不能做動態位置**逐個不同**：

| folder | 行號 | 動態位置可行性 |
|---|---|---|
| `foldExtractOpFromExtractChain` | 1478、1488 | **可以**，純串接位置，不需算術 |
| `ExtractFromInsertTransposeChainState` | 1617/1633/1651/1675/1694 | 大多不行（要比對位置相等），除非同一個 SSA value |
| `foldExtractFromShapeCast` | 1885 | 要算 linear index → 要建 `muli`/`addi`，`fold()` 建不了 op |
| `foldExtractFromExtractStrided` | 1950 | 同上，要加 offset |
| `foldExtractStridedOpFromInsertChain` | 2002 | 同上 |

所以「一次補掉是有份量的 patch」不成立，真正乾淨可做的只有第一個。

**② 第一關證據不足**：`mlir/test/Integration/` 裡動態位置的 `vector.extract` 只有 23 處，
落在 `sparse-dot-product`、`ArmSME/vector-load-store`、`Vulkan/vector-shuffle`——
**不是 AI pipeline 的必經之路**。第二關（JD 關鍵字）也照舊弱。

**判定：不做。** 保留紀錄是為了下次別再從那句過期的「四處」重新起念。

### 🔧 2026-08-21：開始寫 `in / scale` 的 patch（分支 `arith-scaling-value-semantics`）

基準 `fb7a3412079f`。**寫沒有被擋，只有送要等 tgymnich**——這是我在 issue 上公開講的分寸。

改法：兩個 converter 都不再把 scale 截成 `f8E8M0FNU`，改成把 scale **casting 到運算發生的型別**
（`scaling_extf` → result type、`scaling_truncf` → input type），然後照舊 `mulf`／`divf`。

抽出 `castFloatValue` helper，並處理一個**今天的程式碼沒處理的邊界**：
`arith.extf`／`arith.truncf` 的 verifier 都要求嚴格變寬／變窄，所以**同寬但不同型**
（例如 8 bit 的 `f8E5M3FNU` scale 配 8 bit 的 result）兩個都不合法，必須明確 `notifyMatchFailure`。
今天的程式碼在這個組合下會建出過不了 verifier 的 op。

**已完成（commit `dade85d185b4`，3 個檔案）**：

| 檔案 | 動了什麼 |
|---|---|
| `ExpandOps.cpp` | 兩個 converter 改用 scale 的值；新增 `castFloatValue` helper |
| `ArithOps.td` | 兩段 description 原本就寫著舊讀法，一併改；順手修掉原本錯亂的 SSA 編號（`%0` 定義後卻用 `%1`） |
| `expand-ops.mlir` | 6 改形狀、2 負向翻正向、新增 4（`f8E5M3FNU` 正向 ×2、同寬 bail 負向 ×2） |

**驗證**：`expand-ops.mlir` PASS、`git clang-format HEAD~1` 乾淨、
三個代表案例實跑輸出正確（f16 不再截斷／`f8E5M3FNU` 開始展開／E8M0 逐字不變）、
**`check-mlir` 3905 passed / 0 failed**（613 unsupported、1 expectedly failed）。

**第 4 關證據**（`notes/scaling-value-semantics.md` §10，可重現）：把舊展開那串 IR
餵給 `-canonicalize` 折出實際除數 —— scale `3.0`→**2.0**、`1.6`→**1.0**、`7.0`→**4.0**，
誤差上界趨近 2×。

> ⚠️ **TODO 舊紀錄已過期**：08-10 記的「`1.6 : f16` → ExpandOps 給 2.0」今天不成立。
> 實測只跑 `-canonicalize` 是**不折**（`losesInfo` 為真，正是我們自己 #214919/#216056 的效果），
> 開 `include-f8e8m0` 才折成 1.0。**要引數字就重跑，不要抄舊紀錄。**

**第 5 步撞車查證**：`#216653`（`arun-thmn`，今天還在動）同樣改 `ExpandOps.cpp` ＋ `expand-ops.mlir`，
但**只碰 pass 註冊區**（`includeF8E8M0` 那幾行）加 F8E4M3FN/F8E5M2 的 pattern，
**不碰 scaling converter**。語意不撞，同檔不同區域，誰後 merge 誰 rebase。

**已送出：[PR #217892](https://github.com/llvm/llvm-project/pull/217892)**
（2026-08-21，head `bf5128a96ff8`，base `4f5aa5128922`）。
分支 `arith-scaling-value-semantics`，答辯筆記
[`notes/scaling-value-semantics.md`](notes/scaling-value-semantics.md)、
描述存檔 [`patches/scaling-value-semantics-pr-body.md`](patches/scaling-value-semantics-pr-body.md)。

**送出前重做的兩件事**：
① rebase 到 `4f5aa5128922` 並重測（main 從 `fb7a3412` 前進過，不重測等於沒驗證）——
`expand-ops.mlir` ＋ `canonicalize.mlir` 都 PASS；
② **commit 訊息重寫**——取樣 `git log -- mlir/lib/Dialect/Arith/` 後發現上游的形狀是
**問題 → 具體 IR 例子（```mlir fence）→ 數字 → `## Change`**，原本那則是純散文沒有例子，不合。

**描述刻意寫進去的三件事**（因為 tgymnich 始終沒表態）：
- 連到 #215295，並寫明「這是兩個答案中的一個，不是已定案的問題」
- 直接對 tgymnich 說：**還是讀成 exponent 就講，我關掉 PR** ——
  比讓他 review 一個前提錯的 patch 便宜
- 把 `ArithToAMDGPU` 明確劃到本 patch 之外（那題的答案在硬體文件 §15.14，不在樹裡）

同時在 #215295 貼了指過去的留言：[5369626828](https://github.com/llvm/llvm-project/issues/215295#issuecomment-5369626828)。

### ✅ 2026-08-18：#215295 已回覆 krzysz00，並請 tgymnich 表態

留言：[5322525782](https://github.com/llvm/llvm-project/issues/215295#issuecomment-5322525782)
（2026-08-18 02:03 UTC，已回讀確認）。草稿留在
[`patches/215295-in-over-scale-reply.md`](patches/215295-in-over-scale-reply.md)。

四段：① 接受 `in / scale`，講明白他的硬體證據為什麼贏過規格解讀；
② **請 `@tgymnich` 表態**——寫法刻意是「紀錄上有兩個相反的答案，下游取決於哪個是正解」，
不是「你錯了」；③ 列出因此變錯的四個位置（見上一節的表，全部實查行號）；
④ 提出接手順序，並在最後**搭便車催 #215696**（他昨天在這條線上是活的，成本近乎零）。

`ArithToAMDGPU.cpp:592` 那一條**刻意寫成問句**——硬體是否只讀 exponent bit 由他的
§15.14 定案，不自己推。

### ⚠️ 2026-08-18：GitHub profile 顯示名已由本人改成 `Hung-Kuan Tseng`

`gh api user --jq .name` 回 `Hung-Kuan Tseng`（已實查）。
**在此之前 merge 的五個 commit 全部是 `Hung Kuan Tseng`（少連字號）**，包含 08-17 的
`898b0188d901`。merge 出來的 author 名取自 profile 而非 commit，所以往後的 commit 才會對。
**這筆已經結案，不要再列進待辦。**

### 🎉 2026-08-18：#216056 已 MERGE — 第五個 commit，第一個進 `llvm/` 而非 `mlir/`

`tgymnich` 2026-08-17 09:21 UTC 代 merge，squash commit **`898b0188d901`**。
issue **#215445 同時自動關閉**（`state_reason: completed`，closed_by `tgymnich`）。

意義：前四個 commit 都在 `mlir/`，這個動的是 **`llvm/lib/Support/APFloat.cpp`**——
LLVM 的核心浮點實作，所有前端與後端共用。履歷上「改 MLIR」變成「改 LLVM 本身」。

### ✅ 2026-08-18：#215123 拿到 approve，rebase 已做（衝突來源是自己人）

`tgymnich` 2026-08-17 09:41 UTC **APPROVED**，全文只有一句：

> LGTM. Still needs a rebase on main

GitHub 的 `mergeable_state` 確實是 **`dirty`**（真衝突，不是 stale）。
**衝突來源是我們自己的 #216056**——它也往 `mlir/test/Dialect/Arith/canonicalize.mlir`
的同一個位置後面接測試（`truncFPConstantE8M0Negative` / `...Zero`）。

| | |
|---|---|
| 舊 head | `b6b2ddb25dc5`（base `a558267da71f`，08-11） |
| 新 head | **`96dfbf939686`**（base `ecdcdf0577c1`） |
| 備份 | `backup/scaling-fold-prerebase-0818` |
| 衝突 | 只有 `canonicalize.mlir` 一處，兩段測試接在同一行後面，**兩邊都留**即可 |
| 驗證 | `.cpp` / `.td` 的 diff **逐字元相同**，只有 hunk 行號位移（`diff <(git show 舊) <(git show 新)` 只剩 commit sha 與 `@@` 行） |

**#216056 的語意變更不會碰到這個 folder**：它讓 `APFloat::convert` 回報 sign／zero 失真，
而這裡的轉換是**從** `f8E8M0FNU` 出來（那個方向無損）以及進到 result type，沒有測試行為改變。

**驗證與推送（2026-08-18 02:28 UTC）**：

| 項目 | 結果 |
|---|---|
| `ninja mlir-opt` | 4566/4566，exit 0（#216056 動到 `APFloat.cpp`，整棵 LLVM 重編約 1 小時） |
| `llvm-lit canonicalize.mlir` + `expand-ops.mlir` | 2/2 PASS |
| `ninja check-mlir` | **3873 passed / 0 failed**（1 expectedly failed、613 unsupported） |
| `git clang-format HEAD~1` | did not modify any files |
| force-push | 用 `--force-with-lease=refs/heads/arith-scaling-fold:b6b2ddb25dc5` 保護，成功 |
| 回讀 PR | head 對上 `96dfbf939686`、`mergeable: true`（衝突消失）、**tgymnich 的 APPROVED 還在** |

留言：[5322730819](https://github.com/llvm/llvm-project/pull/215123#issuecomment-5322730819)，
草稿同步回 [`patches/215123-rebase-comment.md`](patches/215123-rebase-comment.md)。

### ⭐ 2026-08-18：krzysz00 用 CDNA5 ISA 手冊定案 `in / scale`，**推翻 tgymnich**

`krzysz00` 2026-08-17 18:07 UTC 在 #215295 回覆，這次帶的是**硬體文件**而不是規格解讀：

| 來源 | 內容 |
|---|---|
| AMD Instinct **CDNA5 ISA** §7.12.6 | `f8E5M3` scale 是 OCP 規格的擴充，**真實硬體上存在** |
| 同文件 §7.6.3 | E5M3 scale 的轉換 |
| 同文件 §15.14 | `scalef32` 指令的精確定義 |

他的結論一句：**`arith.scaling_truncf => in / scale` 才是對的**。

這**推翻**了 08-13 記在 commit `51fc774` 的 tgymnich 裁決（「scaling ops 取 scale 的
exponent，依 OCP MXFP 規格」）。理路是：OCP 規格定義 MX 格式的 scale 是 E8M0，所以那個
論證只能涵蓋兩人本來就同意的那半；**真實硬體吃 E5M3 scale**，正是分歧的那半。

**#215123 完全沒被波及**——當初刻意只折 `f8E8M0FNU` scale，這是第二次兌現。

**這個裁決讓樹上這些東西變成錯的**（全部實查過，行號對 `ecdcdf0577c1`）：

| 位置 | 今天做什麼 | 在 `in / scale` 之下 |
|---|---|---|
| `ExpandOps.cpp:674`、`:716` | scale 元素型別 ≥16 bit 就先 `arith.truncf` 成 `f8E8M0FNU`，註解自己寫著 "allow implicit exponent extraction from 16/32 bits floats" | **算錯值**，不只是 rounding mode 選錯：`f16` 的 scale `3.0` 在被用到之前就變成 2 的冪 |
| `ExpandOps.cpp:682`、`:723` | 8 bit 但非 `f8E8M0FNU` 的 scale（`f8E5M3FNU`）根本不 match | krzysz00 要的那個 case 是**唯一沒有 generic 展開**的 case |
| `ArithOps.td:1480`、`:1672` | 兩個 op 的 description 直接把 lowering 寫成 `%0 = arith.truncf %1 : f32 to f8E8M0FNU` | **文件本身寫的是 exponent-only 讀法**，這是文件變更不只是程式碼變更 |
| `ArithToAMDGPU.cpp:592` | 任何 scale 型別都 `extf`／`truncf` 到 f32 交給 `amdgpu::PackedScaledTruncOp`（gated on gfx950） | 若 `V_CVT_SCALEF32_*` 真的只讀 exponent bit（他自己先前這樣說），這條路也在無聲丟尾數。§15.14 應該能定案，**這點要問他不要自己推**|

**下一題（M1-c 候選）就在這裡**：generic expansion 改成真的用 scale 的值去乘／除。
這是**值算錯**（比 folder 重），且題目天生長在 MXFP 量化上，§8.7 第 1、2 關天然過關。

草稿：[`patches/215295-in-over-scale-reply.md`](patches/215295-in-over-scale-reply.md)

### ⭐ 2026-08-17：兩個 PR 被 approve，新原則「已 approve 未 merge 就禮貌 ping」

本人指示：**approve 不等於有人會按 merge**。我們沒有 commit access，reviewer 按完批准
就去看下一個，PR 會沉。所以從現在起，**已 approve 但還沒 merge 的一律禮貌提醒一次**——
語氣是提醒＋現況同步，每則都要帶新資訊（CI 狀態、head 自哪天起未變、還缺什麼）。
已記進長期記憶 `ping-approved-but-unmerged-prs`。

三則留言已送出並回讀：

| 對象 | 內容 | 連結 |
|---|---|---|
| #216056 兩則 inline | matthias 要求「也檢查轉換後的值」，已照做 | [3792281450](https://github.com/llvm/llvm-project/pull/216056#discussion_r3792281450)、[3792281508](https://github.com/llvm/llvm-project/pull/216056#discussion_r3792281508) |
| #216056 top-level | 兩個 approve ＋ CI 全綠，請 matthias／tgymnich 代 merge | [5308573973](https://github.com/llvm/llvm-project/pull/216056#issuecomment-5308573973) |
| #215696 | 謝 kuhar 的 approve ＋ 問「繼續等 krzysz00 還是先落地」；另給 krzysz00 一段 review 導覽 | [5308574043](https://github.com/llvm/llvm-project/pull/215696#issuecomment-5308574043) |
| #215123 | 推 tgymnich 表態，順帶點出 #215295 卡在他與 krzysz00 相反的答案 | [5308574090](https://github.com/llvm/llvm-project/pull/215123#issuecomment-5308574090) |

### ✅ 2026-08-17：#216056 補上 matthias 要的值斷言（head `aa2025befe32`）

原本的 `ConvertLosesUnrepresentableSignAndZero` 只斷言 `losesInfo` 與 `status`，沒斷言值。
改法是**把巢狀迴圈拆開**——因為兩個格式對 zero 的答案不同，塞在同一個迴圈裡寫不出期望值。

| 輸入 → 目標 | 轉換後實測值 |
|---|---|
| `-2.0` → `f8E8M0FNU`／`f8E5M3FNU` | **負號原封留著**（`isNegative()`、`convertToDouble() == -2.0`）；`losesInfo` 就是在報這件事 |
| `+2.0` → 兩者 | `2.0`，`opOK`、`losesInfo == false` |
| `0.0`／`-0.0` → `f8E8M0FNU` | **都變 `+2^-127`**（`makeSmallestNormalized(false)` 會清掉符號），bit pattern `0x00` |
| `-0.0` → `f8E5M3FNU` | 仍是 `-0.0`（有 zero），只報符號失真 |

**負值刻意不用 `bitcastToAPInt()` 斷言**：這兩個格式沒有符號位元，編碼根本顯示不出被帶進來的
符號，而符號正是這個 case 在測的東西。改用 `convertToDouble()`。

驗證：`ADTTests` **2188 passed / 0 failed**、`git clang-format` 乾淨；
**負向對照**——把 `APFloat.cpp` 的新檢查關掉重編，該測試 fail（`losesInfo` false、status `opOK`）。
force-push 後回讀：head 對上，**兩個 APPROVED 都還在**（LLVM 沒設 dismiss stale reviews，第二次確認）。

> ⚠️ **這台的 git 不支援 `git stash push --staged`**（會印 usage 而不是報錯），
> 我沒察覺就接著跑 `reset --hard`，把暫存的改動洗掉，還誤 `stash pop` 了一個舊 stash。
> 復原方式記著：`git stash pop` 掉的那個 stash commit sha 會印在 "Dropped refs/stash@{0} (…)"，
> 用 `git stash store -m "<原訊息>" <sha>` 就能原封放回（原訊息用 `git show -s --format=%s <sha>` 查）。
> **通則：要把改動搬到另一個 commit 上，先 `git commit` 再說，不要靠 stash。**

### ⚠️ 2026-08-17：本地 `index-ceildivs-intmin` 又落後 fork（第二次踩到）

本地停在 `0e1e741d`（base `5f33e4f0`），fork/PR head 是 `358a393a`（base `17930a3c`，
08-14 21:05 rebase 過）。**四個 commit 的 patch-id 逐一比對完全相同**，純 rebase。
已 `git branch -f` 對齊。

**通則（#215318 也發生過一次）：動任何 PR 分支前，先 `git ls-remote fork <branch>` 比對 head；
不同就先逐 commit 比 patch-id 確認是純 rebase，再對齊本地。**

### 🎉 2026-08-14：#215318 已 MERGE — 第四個 commit（第一個 `vector`）

`banach-space` 2026-08-13 16:20 UTC 代 merge，squash commit **`1ccdf48548ed`**。
**這是第一個進上游的 vector dialect commit**（M1-d），也是主場從 arith 往 vector 擴的第一步。

他回覆署名那段的重點：**GitHub UI merge 的 email 取自 GitHub 設定、名字取自 commit**，
並說「同一個 GitHub 帳號是我們追蹤貢獻的依據（例如日後申請 commit access）」。

⚠️ **實際 merge 出來是 `Hung Kuan Tseng <tseng.tim096@gmail.com>`——少了連字號。**
來源是 GitHub profile 的顯示名（`gh api user --jq .name`），不是 commit 的 author。
**已定案一律用 `Hung-Kuan Tseng`**，profile 要改成一致（見「待本人處理」）。
回覆已送出，短的，只講 email 正確 ＋ 名字已對齊 ＋ 帳號從頭到尾是 `Tim096`。

### ⚠️ 2026-08-14：kuhar 第三輪 — **兩點都是風格問題，本人要求絕不再犯**

| 位置 | 他說什麼 | 處理 |
|---|---|---|
| PR 描述 | 「五個地方算 signed ceiling division」講太滿，要收窄並講明邊界 | 拿掉數量宣稱，改成**限定「arith／index／affine 這條路上」＋ 逐條列狀態的表** |
| `Affine/Utils.cpp:156` | 註解裡的變更史與 `divideCeilSigned`／`inferCeilDivS` 交叉引用該刪，只留當下的不變量 | 照做，砍成三句 |

**兩條都已寫進長期記憶 `match-upstream-style-not-my-own`**：
註解不寫變更史／跨檔引用（會各自過期）；描述不寫數量型全樹宣稱（無法驗證、漏一個就被抓）。
自我檢查句：「這句三個月後還會是真的嗎？」「reviewer 能不能當場否證？」

**順帶查清一件事**：他說 `arith::CeilDivSIOp::fold` 也還在 negate ——
那是**本 PR 過期的 base**（`a558267da71f`，08-11）造成的，
#214637 是 08-12 才 merge（`2a0c335d4538`），已經把那個 folder 換成不 negate 的版本、
TODO 也刪了。**已 rebase 到今天的 main**，舊 head 留在 `backup/index-ceildivs-prerebase-0814`。
重點放在「那句宣稱本來就不該那樣寫」，不是「你看錯」。

### ⚠️ 2026-08-14：krzysz00 回了，**推翻 tgymnich 昨天的裁決**

三點：① 「取尾數」正確名稱是 **`toward_zero` 不是 `downward`**（MLIR 拼法
`toward_zero`，`ArithBase.td:186`）；② **反對非 E8M0 型別的 exponent-only 讀法**
——有硬體吃 `f8E5M3U` 之類的 scale，`arith.scaling_truncf` 應該要能表達；
③ 他當初講的 AMDGPU 是「把 `arith.truncf ... toward_zero` **摺進** `cvt_scalef32`」，
不是拒收非 E8M0 scale。

**所以昨天規劃的 #215123 follow-up（折任何 scale 型別）重新卡住**——
兩種讀法算出的值不同（`in / 2^exp(scale)` vs `in / scale`）。
**#215123 本身不受影響**（只折 E8M0，兩種讀法都同意），當初刻意限制的價值在這裡兌現。

回覆裡放的實查事實（這是這則的重量）：

| 位置 | 對非 E8M0 scale 的現況 |
|---|---|
| `ExpandOps.cpp:675`／`:717` | ≥16 bit 先截成 E8M0（尾數丟掉）；**`f8E5M3FNU` 是 8 bit 且非 E8M0 → 根本不 match，沒有通用展開** |
| `ArithToAMDGPU.cpp:566` | scale 一律 ext／trunc 到 f32 交給 `amdgpu::PackedScaledTruncOp`，**任何型別都收**，尾數由硬體忽略 |

＋ 一句核心：**OCP 規格定義的是 MX 格式的 E8M0 scale，沒有定義 f16／f8E5M3 的 scale
是什麼意思**——tgymnich 引的規格能定兩人本來就同意的那半，涵蓋不到分歧的那半。
最後把問題收成一句可判定的：`arith.scaling_truncf(in, scale : f16)` 是
`in / scale` 還是 `in / 2^exponent(scale)`，並列出兩個答案各自要改什麼。

### 🔍 2026-08-14：buildbot 失敗信 — 查清楚是別人的老問題

收到 `clang-aarch64-lld-2stage` 的失敗信，blamelist 約 50 人（含 #215318）。
**與我們無關，也不是表現機會。** 查證過程留著當往後的 SOP：

1. **失敗的是哪個專案**：`compiler-rt/test/msan/release_origin.c`（MSan runtime），
   我們動的是 MLIR——**MLIR 不會被連進 clang／compiler-rt**。
2. **失敗長什麼樣**：斷言的字串 `soft rss limit exhausted` **有印出來**，
   只是晚了一個取樣點（`RSS: 18Mb` 不大於門檻 18 → 不觸發；memset 之後才 `18Mb vs 19Mb`）。
   **1MB 決定成敗。**
3. **前科**：[#171209](https://github.com/llvm/llvm-project/issues/171209) 就是同一支測試、
   同一個 AArch64（tstellar 實測 x86 baseline 44Mb、aarch64 57Mb），
   [#196565](https://github.com/llvm/llvm-project/pull/196565) 的修法就是**把門檻數字調掉**
   ——現在的 `18` 就是那次調的值，邊際只剩 1MB。

唯一有實質的動作是去 #171209 留一則帶新數據點的復發回報（5 分鐘），
但**過不了 §8.7 第 1／2 關**，決定跳過。

### ⭐ 2026-08-13 傍晚：tgymnich 定案「scaling op 就是取 exponent」

他 15:05 的回覆（#215123）是這幾天最有價值的一則，兩件事：

1. **「I'm ok with landing the other FP types as a follow up.」** — 我提的順序被接受。
2. **`scaling_extf`／`scaling_truncf` 對 scale 一律取 exponent，依據是 OCP MXFP 規格**
   （不是「pass 現在剛好這樣做」）。而 **`arith.truncf` 本身仍未定案**。

**這一刀把兩個問題切乾淨了**：scaling op 的語意從此**不依賴** truncf 怎麼定，
只有 `ExpandOps.cpp` 的展開還依賴（它是透過一個沒帶 rounding mode 的 `arith.truncf`
走到 E8M0 的，正是 tgymnich 自己在 #215295 提議要改成 `truncf ... downward` 的那條）。

**follow-up 因此解鎖**（等 #215123 merge 後做）：

| 要做什麼 | 細節 |
|---|---|
| 折任何 float scale | 取 exponent ＝ `rmTowardZero` 轉換（對這個格式裝得下的值等價） |
| **不折負的與零的 scale** | bit-level 的取 exponent 會丟掉符號、且 `0x00` 一邊讀 `0.0` 一邊讀 2^-127（#216056）。folder 靜靜丟掉符號比不折更糟 |
| inf／NaN | 兩條路都落在 `0xFF`，一致 |
| 驗證 | 全部 65536 個 f16 scale 對 `--arith-expand=include-f8e8m0 -canonicalize` |

同時已在 #215295 把問題收窄成剩下的那一題（truncf 是 RNE 還是取 exponent），
並指出 krzysz00 原本想要的「拒收非 E8M0 scale」可以換成
「展開時把想要的轉換寫明」——同樣的效果、不用拒收。

### ✅ #216056 premerge 全綠

Linux／AArch64／Windows／macOS arm64／code_formatter／LLVM_ABI 全過，`mergeable=clean`。
**Linux 那輪會跑 check-llvm**，也就是本機沒跑到的那部分——APFloat 改動沒有打到任何
LLVM 端的既有測試。

### 🔥 2026-08-13 下午：tgymnich 三連回，開了第七個 PR

一天內 tgymnich 回了三個地方，全部都要動：

| 在哪 | 他說什麼 | 我怎麼做 |
|---|---|---|
| #215445 | "good find! Reporting the loss of sign and zero sound like the right thing to do here. Feel free to send a patch." | ✅ 已送 **[PR #216056](https://github.com/llvm/llvm-project/pull/216056)** |
| #215123 | ① 任何 scale 型別都能折，只要跟 expansion 一致 ② NaN 特判先拿掉 | ② 已做完（見下）；① 排在 #216056 之後 |
| #215295 | 提第三條路：rounding mode 顯式化，expansion 只收 `downward`／`to_nearest_even`，`scaling_extf` 改發 `truncf %x downward` | 已回覆支持並補三個要先釘的點 |

### 🆕 [PR #216056](https://github.com/llvm/llvm-project/pull/216056)：APFloat 不回報 sign／zero 失真

分支 `apfloat-unrepresentable-sign-zero`，基準 `a558267da71f`，**兩個 commit**。
這是第一個動到 `llvm/lib/Support` 的 patch（不是 MLIR）。

| commit | 內容 |
|---|---|
| `77bf8c72735a` | `IEEEFloat::convert` 在目標 `hasSignedRepr == false` 或 `hasZero == false` 時回報 `opInexact` ＋ `losesInfo`；值本身不變 |
| `c3b8cccc8639` | MLIR parser 拒收「沒有符號表示的型別」的負字面值 |

**為什麼要兩個 commit**：第二個 reproducer（直接寫 `arith.constant -2.0 : f8E8M0FNU`）
**不經過 `losesInfo`**——`parseFloatAttr` 走 `FloatAttr::get`，根本不看回報，
所以只有 APFloat 那半是修不掉它的。兩條 literal 路徑（scalar 的 `parseFloatAttr`、
dense 的 `parseFloatFromLiteral`）都要擋。

⚠️ **動到一個既有測試的期望值**：`APFloatTest.ConvertDoubleToE8M0FNU` 原本斷言
`0.0 → E8M0` 是 `opOK` ＋ `losesInfo == false`（註解寫「zero encoding is
represented as the smallest normalized value」）。替代值 2^-127 我保留，
只把兩行狀態翻掉，並在 PR 描述裡單獨開一節點名這件事，請 reviewer 確認。

**技術細節**：`convert` 裡 NaN 那段原本 `return` 提早離開，我改成 else 分支
落到共同結尾，這樣新的檢查看得到每一條路徑。

驗證：`ADTTests` 2188 passed / 0 failed、`check-mlir` 3848 passed / 0 failed、
clang-format 乾淨；兩個 reproducer 都實測過（fold 不再發生、literal 出診斷而非 abort）。

⚠️ **踩到自己的舊教訓**：我在留言裡把 `Pradeep Kumar` 的 GitHub 帳號猜成
`Pradeep-Kumar-CB`，實際是 `schwarzschild-radius`（`gh api repos/.../commits/<sha> --jq .author.login`）。
已編輯留言修掉。**帳號一律用 API 查，不要從人名猜。**

### ✅ 2026-08-13：#215123 的 NaN 特判已拿掉（sweep 已重跑確認）

`getScalingCastNaN` 整個刪掉，兩個 fold 裡的 `if (scale.isNaN())` 也刪掉。
head `b6b2ddb25dc5`，PR 描述已同步，premerge 全綠。
**lit 測試零改動、全過**——包括三個 NaN 測試：E8M0 的 NaN 加寬本來就無損，
所以一般路徑照樣折得出 NaN；而 finite-only 結果型別（`f4E2M1FN`）那個，
`convertFloatValue` 本來就會擋（實測 `arith.truncf %nan : f32 to f4E2M1FN` 不折）。
真正失去的只有「輸入加寬有損 ＋ NaN scale」這種組合，枚舉空間裡碰不到。

**窮盡 sweep 重跑（16,777,216 組，truncf 那輪 2292 秒）：三張表數字一字未變**
（656/4096、4096/4096、33390/16777216，三項檢查全 0 分歧）。

放寬 scale 型別（他的第一點）已回覆說明順序：先 land 現在這版 →
#215295 定案 → 再依定案的 rounding mode 放寬，並對 65536 個 f16 scale 做窮盡比對。
理由是「跟 expansion 一致」＝往零捨去，那正是 #215295 在決定的事；
而寬 scale 可能為負或零，需要 #216056 先進去。
[回覆連結](https://github.com/llvm/llvm-project/pull/215123#issuecomment-5282032177)

### 🔥 2026-08-13：#215696 第二輪 review — 另外兩條 lowering 也要修

`kuhar` 2026-08-12 20:03 的 review body（不是 inline）：共用的 inference 改動落地前，
**`IndexToSPIRV.cpp:103` 與 `Affine/Utils/Utils.cpp:177` 這兩條 lowering 也還在 negate**。
兩條都做了，各自放在 inference commit 之前，維持「每個 commit 之後樹裡都沒有不一致」。

| commit | 內容 |
|---|---|
| `86d0a8a60d8c` | index folder ＋ IndexToLLVM ＋ **IndexToSPIRV** |
| `9804e901fdd6` | **affine `ceildiv` 展開** |
| `a59259828f74` | 刪 `inferCeilDivS` 兩層 workaround |
| `9cafe941bf39` | 32-bit inference 回歸測試 |

**SPIR-V** 照抄 IndexToLLVM 的形狀。用 arith i32 把新舊兩串序列各自算出來對照：
舊 `306783378`、新 `-306783378`。

**affine 刻意沒照抄**：affine `ceildiv` 規定除數必為正（`visitCeilDivExpr` 本來就對
非正的常數除數報錯，舊展開也是靠這個假設），所以同號判斷可以整個收掉，只剩一個比較：

```
a ceildiv b = let q = a / b in a > q * b ? q + 1 : q
```

`q * b` 就是 `a` 減掉餘數，`b > 0` 時「`a` 大於它」等價於「除不盡且商為正」。
回覆裡有寫明這是刻意偏離，並說「要對齊的話我加回符號判斷」。

實測 `INT64_MIN ceildiv 7`：舊 `1317624576693539401`、新 `-1317624576693539401`
（＝ kuhar 給的數字）。**展開是三者裡唯一走鐘的那個**——affine 自己的常數折疊走
`divideCeilSigned`，本來就給精確的負商，所以早在 inference 之前 fold 與 lowering 就不一致。

> 💡 **又踩到同一個機制，這次是 affine**：`-lower-affine` 也是 dialect conversion，
> **fold 先於 pattern**。`affine.apply` 的運算元是常數的話，affine 自己的 folder 就把它折掉了，
> **展開根本不會跑**——那樣寫的回歸測試在舊程式碼上照樣會過。
> 解法：把被除數藏在 `arith.addi %cmin, %c0` 後面，lower-affine 當下看不到常數屬性，
> 展開就會跑；後面的 `-canonicalize` 再把整串折成常數。
> **負向對照做過**：把展開還原重編，該測試 fail 並印出正的那個值。

`check-mlir` 3848 passed / 0 failed，`git clang-format` 乾淨。
PR 描述已同步成四個 commit 的版本（`gh api -X PATCH`，已回讀）。
舊 stack 留在 `backup/index-ceildivs-prespirv-0813`。

回覆稿：[`patches/index-ceildivs-lowering-paths-reply.md`](patches/index-ceildivs-lowering-paths-reply.md)

### ✅ 2026-08-13：#215318 已 APPROVED，已請 banach-space 代 merge

`banach-space` 2026-08-12 14:35 UTC 給 APPROVED（"LGTM, thank you!"），
premerge 五項全綠、`mergeable=true`。已留言請他代 merge，
並照 #214637 的做法在留言裡挑明兩個 git 署名是同一個人。
留言：[5279547544](https://github.com/llvm/llvm-project/pull/215318#issuecomment-5279547544)

### ✅ 2026-08-13：#215123 收到 tgymnich 的 suggestion，已採用

唯一一則 inline（`ArithOps.cpp:1878`）：手動 `scaleIt++` 換成
`llvm::zip_equal(inElements, scaleElements)`。採用，head `36f2f3ab9b33`。
回覆點出長度相等本來就是前置條件（上面的 guard 已經擋掉不等長），
所以 `zip_equal` 的 assert 只是把這層耦合寫明。
`check-mlir` 3848 passed / 0 failed。
順便問他要不要看實質面（只折 `f8E8M0FNU` scale、NaN 特判這兩個決定）。

### ✅ 2026-08-13：兩個 issue 各 ping 一次（都帶新東西，不是純催）

- **#215445**：新資料點——`hasSignedRepr == false` 的**不只 E8M0**，
  `f8E5M3FNU` 也是，實測 `arith.constant -2.0 : f8E5M3FNU` 同樣 crash
  （連 pass 都不用跑）。所以這是該類格式的性質，該修在 `convert` 而不是某個呼叫端。
  並宣告「沒人反對就送回報 loss 的 patch，兩個 reproducer 都當測試」。
  ⚠️ `hasZero == false` 目前仍只有 E8M0 一個。
- **#215295**：把問題再收窄成一句「truncf → E8M0 是 RNE 還是取 exponent」，
  兩個答案各自對應要改哪一邊；補上「唯一寫得出來的 rounding mode 正好被
  `F8E8M0TruncFOpConverter` 拒絕」這個副作用；再問一次 krzysz00 的 E5M3 論點。

### 🔥 2026-08-12：#214637 merge，同一分鐘 #215696 收到 review

`kuhar` 13:35 UTC 在 #215696 留三個 inline comment，13:39 UTC 把 #214637 merge 掉。
三點都已處理，amend 進第一個 commit（stack 維持三個 commit），
新 head `7a0d9f0ea804`，`ninja check-mlir` 3848 passed / 0 failed，
`git clang-format` clean。舊 stack 留在 `backup/index-ceildivs-prereview-0812`。

**(a) `IndexOps.cpp` 改用 `APIntOps::RoundingSDiv(n, m, Rounding::UP)`**

他要我別自己再維護一份餘數／符號修正。看 `llvm/lib/Support/APInt.cpp:2816`，
`RoundingSDiv` 是 `sdivrem` 後判 `Rem.isNegative() != B.isNegative()`；
`sdivrem` 的餘數符號跟被除數相同，所以那就是同號條件的另一種寫法，完全等價。
順便可以拿掉我原本在 `+1` 上的 `sadd_ov`——`RoundingSDiv` 自己的 `Quo + 1` 也沒防護，
理由是商等於 `INT_MAX` 需要 `m == ±1`，而那兩個都整除，修正根本不會觸發。

**一個刻意的偏離**：他寫「放在既有的 `sdiv_ov` guard 後面」，我改成直接寫
`n.isMinSignedValue() && m.isAllOnes()`——那就是 `sdiv_ov` 內部算的東西。
因為 `RoundingSDiv` 裡面已經有一次 `sdivrem`，照字面寫等於除兩次。
回覆裡有寫明這點並說「你要的話我改回去」。

**(b) `index-canonicalize.mlir` 補負/負不整除**：`@ceildivs_neg` 加第二個結果，
`ceildivs(-5, -2)` → `3`。原本 same-sign 修正只有正/正走得到。

**(c) `index-to-llvm.mlir` 補值的迴歸**：加在既有的 `INDEX32`／`INDEX64` run 底下，
不用新開 RUN line——光是 conversion 就已經吐出 `llvm.mlir.constant(-306783378)`。

> 💡 **這裡有個一定要知道的機制**：`ConversionConfig::foldingMode` 預設是
> `BeforePatterns`，`OperationLegalizer` 會**先試 fold 再找 pattern**
> （`mlir/lib/Transforms/Utils/DialectConversion.cpp:2601`）。
> 所以常數運算元的 `index.ceildivs` 根本不會走到 `ConvertIndexCeilDivS`，
> 那個常數是 folder 算出來的。
> 這個 check 在 main 上仍然會 fail（那邊 fold 失敗 → pattern 真的跑 → 而
> `llvm.sdiv`／`add`／`mul`／`select` 都沒有 folder，不會再被折起來），
> 所以確實是他要的迴歸；但它 pin 的是「fold 和 lowering 對這個輸入是否一致」，
> **不是 pin 產生的 op 序列**。上面那段序列 CHECK 才是管 lowering 的。
> 測試註解和回覆都照這個講法寫，不要讓它讀起來像 lowering 測試。

**額外自查**：7140 組運算元（-40..40 全配對 ＋ `INT_MAX`／`INT_MIN`／
`±1000000007`，排除除以零）對照 LLVM 外部算的精確 ceiling，零不一致，
唯一折不掉的是 `(-2147483648, -1)`。

回覆草稿（三則 inline ＋ 一則 top-level，含 comment id）在
`patches/index-ceildivs-intmin-review-reply.md`。

### ✅ 2026-08-12：#215123 的衝突已解

rebase 到 `a558267da71f`，衝突（`canonicalize.mlir` 撞 #214919 的 E8M0 測試）解掉，
`dirty` → `mergeable=true`，premerge 全綠。**patch 內容一個字沒動**——那三個檔案
上游自 merge-base 起零改動，只有行號位移（`git show | grep -v '^index '` 前後 diff 為空）。
舊 commit 留在 `backup/scaling-fold-prerebase-0812`。

**順便補上兩件事**：

1. **PR 描述之前只改了一半**。08-10 晚間那次只更新了 NaN 那段，
   「`scale = 1.6 : f16` 兩邊算出 2.0 vs 1.0」那段還是舊的——而那句正是
   `tgymnich` 在 #215295 指出不成立的（1.6→2.0 發生在建 attribute 時，不是 fold）。
   現在整份描述＝commit message，已同步。
2. **重跑 exhaustive sweep**（`tools/verify-scaling-fold/verify.py`），因為原本那張表是在
   #214919 合併**之前**量的。數字完全一致（4096/656、4096/4096、16777216/33390，零不一致），
   而且 `NaN-scale diffs vs expansion` 現在是 **0**——這就是 NaN 那段理由該換掉的實證。
   truncf 那輪 1677 萬筆跑 2009 秒。

⚠️ **`gh pr edit --body-file` 會被 GitHub 的 projects-classic 棄用錯誤擋掉**（看起來沒報錯但沒寫進去）。
改用 `gh api -X PATCH repos/llvm/llvm-project/pulls/<n> --input <json>` 才會生效。**改完一定要回讀驗證。**

### 🔥 2026-08-12：#214637 的 review 與由此挖到的東西

`kuhar` 留了兩則 inline comment：

1. **`inferCeilDivS` 也要一起改**（`mlir/lib/Interfaces/Utils/InferIntRangeCommon.cpp`）。
   他給的例子：`ceildivsi(INT64_MIN, 1189465982)` 在 `-test-single-fold` 得 `-7754212542`，
   在 `-int-range-optimizations` 得 `7754212542`。
2. **加一個 vector 測試**，釘住 folder 裡 `overflowOrDiv0` 是整個 vector 共用的。

**挖到的**：這個矛盾**不是本 PR 造成的，在 upstream main 上已經成立**。用只多了不相干
scaling fold 的 binary（＝main 的 `ceildivsi` 行為）實測：

```
$ mlir-opt cd1.mlir -arith-expand -canonicalize   →  -7754212542
$ mlir-opt cd2.mlir -int-range-optimizations      →  斷言 == +7754212542（且 != -7754212542）
```

來由：#116284（2024-11）加 sign flip 是為了配合當時的 expansion `-(-a/b)`（`-MININT` 是 noop，
所以結果變正）；#121062 再加一層 range union 去補那個不連續。但 **#133774（2025-04-02）
已把 expansion 換成數學上的 ceiling**，兩層 workaround 從那時起就對不上任何實作了。

**改法**：兩層全刪，`inferCeilDivS` 變成跟 `inferFloorDivS` 完全對稱。可以刪 union 的理由：
`inferDivSRange` 只在 range 端點取值，而 ceildivsi 在除數不變號時對兩個運算元都單調
（`inferDivSRange` 本來就會在除數可能變號時放棄），所以端點就能界住。#121062 的回歸測試
`@ceil_divsi_full_range` 不靠 union 也照樣不折——已驗證。

改完三者一致：`-test-single-fold`、`-arith-expand -canonicalize` 都給 `-7754212542`，
`-int-range-optimizations` 斷言 `== -7754212542`。`check-mlir` 3848 passed / 0 failed。

**四個 commit 的分工**（LLVM 是 squash merge，但分開讓 kuhar 好讀）：

| commit | 內容 |
|---|---|
| `60759dbd7cde` | 先補 MININT divisor 的測試（現況行為） |
| `2823ce06986d` | folder 本體 |
| `a2053d64062c` | 刪掉 `inferCeilDivS` 兩層 workaround ＋ int-range 測試 |
| `c67814fef49a` | vector 共用 flag 的回歸測試 |

回覆裡有提「這條可以拆成獨立 PR」，等他表態。

⚠️ **寫給上游的東西不要用 `miscompile` 這類升級用語**（2026-08-12 他明確要求）。
「兩個 pass 對同一個 op 給出矛盾答案，而且早於你指出的改動」就夠了——並排放兩個輸出、
說清從哪個 commit／日期開始，比形容詞有用。

⚠️ **`InferIntRangeCommon.cpp` 在 `MLIRInterfaceUtils` 裡，動它要重編 ~1500 個 target**（約 25 分鐘），
不是只編幾個檔案。另外 sweep 跑的時候**不能 rebuild**——`bin/mlir-opt` 會被換掉，
sweep 每次都是重新 spawn，結果會被污染。

### ✅ 2026-08-12：#214637 **kuhar APPROVED**（"LGTM % one comment"）

拆分那則回覆送出後 67 分鐘（UTC 00:24），`kuhar` 批准了，只留一個 nit
（`ArithOps.cpp:1001`）：

```cpp
// 他要的
if (a.isNegative() != b.isNegative() || a.srem(b).isZero())
```

**理由**：`a.srem(b)` 是第二次有號除法（`sdiv` 已經算過一次），而異號的組合
本來就直接回 quotient、不需要餘數。`||` 短路，所以 disjunct 的順序就是成本順序，
換一下大約一半的輸入省掉那次除法。

**#215696 的 index 版本本來就是這個順序**，所以這一改是把兩邊對齊。
這條原則已記進長期記憶（`short-circuit-order-is-cost-order`）：
寫 fold 的條件式要先問每個 disjunct「多貴、多常中」，便宜且常中的放左邊；
同一份邏輯若跨 dialect 重複，順序也要一起對齊。

**順著同一個方向再往前一步**（本人指示：成本低、同一類，就一起做）：
`a.srem(b).isZero()` 換成 `quotient * b == a`。srem 是除法，乘法便宜得多，
而且這正是 `ExpandOps.cpp` 的 ceildivsi expansion 在用的形狀
（commit message 本來就寫「mirrors the expansion」，現在名副其實）。
**等價性**：`q*b` 的精確值是 `a - r`，必定在範圍內、不會 wrap，
所以 `q*b == a ⟺ r == 0`。用 python 對全部 65279 組 i8 pair 驗過，零不符。
於是同號路徑也不再需要第二次除法——kuhar 只點掉異號那一半，這一步把另一半也拿掉。

改動併回 folder 那個 commit（不另開一個修自己的 commit），
新 head `a92dedfc02bd`，相對舊 head 只差那一行。`check-mlir` 3848 passed / 0 failed。
已 force-push ＋ [inline 回覆](https://github.com/llvm/llvm-project/pull/214637#discussion_r3763597542)。
**force-push 沒有讓 APPROVED 消失**（LLVM 沒設 dismiss stale reviews），已回讀確認。

### ✅ 2026-08-12 已定案：git 署名一律用 `Hung-Kuan Tseng <tseng.tim096@gmail.com>`

| 已 merge 的兩個 commit | 現在起（三條分支都已是） |
|---|---|
| `曾鈜寬 Tseng Hung Kuan <P76091014@gs.ncku.edu.tw>` | **`Hung-Kuan Tseng <tseng.tim096@gmail.com>`** |

（`78e17e70bd52` / `794aa0fd923a` 是舊的那批。）

LLVM 是 squash merge、author 取自 PR 上的 commit，所以 upstream 的 `git log`
會有兩個看起來不同的人。**本人決定：不回頭改舊的，新的一律用 gmail 這個**，
並在請 kuhar 代 merge 時直接說明「之前那個也是我」。

**以後開新分支前先確認 `git config user.email`**，不要再分岔。

### 🔥 2026-08-12 晚：kuhar 第二輪 review → `inferCeilDivS` 拆成獨立 PR

15:06 那輪之後，`kuhar` 18:39 又留了一則（`InferIntRangeCommon.cpp:381`）：
`inferCeilDivS` 不只 `arith` 在用，`index::CeilDivSOp` 也用，而 index 那邊
沒有跟上——`calculateCeilDivS` 與 `ConvertIndexCeilDivS` 都還是 `-(-n / m)`。
他給的可觀察後果：`-int-range-optimizations -canonicalize` 把
`index.cmp sle(index.ceildivs(-2147483648, 7), 0)` 折成 `true`，
但 `--convert-index-to-llvm=index-bitwidth=32` 產出的碼在執行期是 false。
**二選一：這發一起修 index，或把共用的 inference 改動拆走。**

**選了拆走**，理由：他要的是「inference 改的時候 index 必須已經一致」，
拆兩個 PR 反而要跨 PR 追蹤；而且能讓 #214637 維持原本的小範圍。

| 分支 | 內容 |
|---|---|
| `arith-ceildivsi-minint-fold` | rebase 掉 `a2053d64062c`，剩 3 個 commit，只動 `ArithOps.cpp` ＋ `constant-fold.mlir`。新 head `a1c2690f7d79`（舊的留在 `backup/ceildiv-with-inference-0812`） |
| `index-ceildivs-intmin`（新，基準 `a558267da71f`） | `141bc15b` index folder ＋ lowering 不再 negate → `a080792b` 刪 inference 兩層 workaround → `b98eff9e` 32-bit 回歸測試 |

commit 順序刻意如此：**每一個 commit 之後樹裡都沒有不一致**。

實測（同一個基準，改動前 vs 改動後）：

| | 改動前 | 改動後 |
|---|---|---|
| `-canonicalize` 折 `index.ceildivs(-2147483648, 7)` | 不折 | `-306783378` |
| `-canonicalize` 折 `index.ceildivs(-2147483648, -1)` | `2147483648` | 不折 |
| `-int-range-optimizations` 對 kuhar 的例子 | 無法證明 | `true` |

**`ceildivs(INT_MIN, -1)` 從折變不折，是刻意的**：在 32-bit 上精確結果 `2^31`
不可表示，舊算法只是因為修正項 wrap 回 `INT_MIN`、剛好等於 64-bit 結果的截斷，
才通過 `foldBinaryOpChecked` 的一致性檢查。lowering 那邊發的是
`sdiv INT_MIN, -1`（poison），而 `arith.ceildivsi` 對同一情況本來就不折。

**新加的 32-bit 回歸測試單獨驗過**：只還原 `InferIntRangeCommon.cpp` 重編後它會 fail，
所以釘住的是 inference 而不是 folder。`check-mlir` 3848 passed / 0 failed。

草稿：[`patches/index-ceildivs-intmin-pr-body.md`](patches/index-ceildivs-intmin-pr-body.md)
／回覆稿 [`patches/ceildivsi-split-reply.md`](patches/ceildivsi-split-reply.md)

### ✅ 2026-08-12 晚：#215318 拿到 banach-space 的 review，三點都已處理

`@banach-space`（`MaskableOpRewritePattern` 的作者）2026-08-11 18:27 回了，
總評 "Makes sense, thank you!"，三點：

| 位置 | 內容 | 處理 |
|---|---|---|
| `LowerVectorTransfer.cpp:143` | 註解「…and does.」問是不是漏字 | 改成「Its mask is indexed in memory order, so only the passthru has to be transposed.」 |
| `LowerVectorTransfer.cpp:149` | 要一個帶 passthru 的測試 | 加 `@xfer_read_minor_identity_transposed_masked_with_passthru` |
| review body | "Will there be follow-ups?" | 要回答（見下） |

**新測試刻意用三維旋轉**：既有的 masked read 測試都是 `[0, 2, 1]`，
**自反**，所以分不出 `invertPermutationVector(transposePerm)` 和 `transposePerm`。
新測試用 `(d0, d1, d2) -> (d2, d0, d1)`，permutation `[2, 0, 1]`，inverse `[1, 2, 0]`。
**驗證過**：把 `invertPermutationVector` 拿掉重編，該測試會 fail。

本地 head `d0170cd77b5c`（增量 commit，**不要 amend** `3eddbc33`，
否則 banach-space 的 inline review 會脫節）。`check-mlir` 3848 passed / 0 failed，
`git clang-format` 乾淨。

"Will there be follow-ups?" **不是技術問題，是在問計畫**——PR 描述說有兩個 pattern
留給後續，他想知道會不會真的做。回覆稿裡答「會，而且那兩個的 mask 需要變換
不是直通，各自要獨立論證」。草稿：
[`patches/vector-masked-transfer-review-reply.md`](patches/vector-masked-transfer-review-reply.md)

### ⚠️ 2026-08-11 實查：#215318 本地與 fork 不同步

fork 上的分支在 **2026-08-11 07:33 UTC 被 force-push 成 `3eddbc33ed8d`**
（parent `febf50748eff`，比本地基準新），本地 `vector-masked-transfer-lowering`
還停在 `5b04e8cdfcda`。**這次 push 不是本 session 做的。**

**內容沒變**：兩個 commit 的 `git patch-id --stable` 都是 `9bf39a9b123c...`，純 rebase。
本地的 `fork/` remote-tracking ref 先前是舊的，已 `git fetch fork` 更新。
**要動這條分支前先把本地對齊 `3eddbc33`，不然下次 push 會把 rebase 蓋掉。**

### ✅ #214919 合併後，已同步修正 #215123 的理由（2026-08-10 晚間）

#215123 原本用「加寬 `f8E8M0FNU` 的 NaN 會得到 inf 的編碼」當作 NaN 特判的理由。
那句話在它自己的基準（`08cb7d93`，**不含**修復）上是對的，
但 #214919（`794aa0fd923a`）合併後就不成立了——一旦 rebase 或 merge 到現在的 main，
註解會變成在描述一個不存在的 bug。

已改成在新舊基準上都成立的理由：**NaN scale 之下結果必為 NaN、與輸入無關，
所以即使加寬輸入有損也照樣能折**（這本來就是特判比走 convert 多做到的事）。

| 項目 | 內容 |
|---|---|
| 改了什麼 | `getScalingCastNaN` 的 doc comment ＋ commit 訊息／PR 描述的同一段 |
| 程式碼行為 | **完全不變**（NaN 特判在 `convertFloatValue` 之前就攔截，測試不用動） |
| commit | `439d4601` → **`9ff58a1f`**（force-push，已確認 PR head 對上） |
| `git clang-format` | 乾淨 |

> ⚠️ **`gh` 2.4.0 太舊，`gh pr edit --body-file` 會撞到 GitHub 的
> Projects classic 棄用錯誤而靜默失敗**（指令回 0 但描述沒更新）。
> 改用 `gh api -X PATCH repos/llvm/llvm-project/pulls/<N> -F body=@<file>` 才成功。
> 下次改 PR 描述直接用 API，並且**一定要回讀確認**。

### 🆕 2026-08-10 晚間：同時推進兩條線

本人指示：**選題要以履歷訊號強度為第一判準**，而且要「用聰明的方法找題目」。
據此排序：**找到 correctness bug > 補缺的 fold > NFC**，且盡量落在 vector 或量化路徑。

#### 線 A：[Issue #215295](https://github.com/llvm/llvm-project/issues/215295)（2026-08-11 已有兩位 maintainer 回應）

`arith.scaling_extf`／`scaling_truncf` 的 **scale 語意分歧**。原 issue 不宣稱誰對誰錯，
只問一個具體問題 ＋ 列三種收法，因為樹裡每一層都沒記載硬體怎麼解讀 scale：
`amdgpu.scaled_ext_packed` 只寫「extend and scale」、`llvm.amdgcn.cvt.scalef32.*`
零註解、`AMDGPUUsage.rst` 沒有條目。

| 回應者 | 內容 |
|---|---|
| `@krzysz00` | `V_CVT_SCALEF32_*` **只讀 exponent bits**。傾向在 `ArithToAMDGPU` 拒收非 E8M0 scale，再折掉 truncate + shift |
| `@tgymnich` | truncf→E8M0 **不該用 round-to-nearest**，正解是 `--arith-expand=include-f8e8m0`（抽 exponent）。**反對拒收**，該改的是文件 |

**問的問題有答案了，但「怎麼修」兩人沒共識**（拒收 vs 改文件），任何 patch 送出去都等於替他們選邊。

⚠️ **原 issue 有一處實質錯誤，已在回覆中更正。** 我拿
`arith.constant 1.6 : f8E8M0FNU` 折成 `2.0` 當作「folder 四捨五入」的證據，
但那是**常數屬性 parse 當下就四捨五入**，跟 folder 無關。實測 folder 會拒絕不精確的折疊
（`convertFloatValue` 的 `losesInfo` 檢查），`--arith-expand --convert-arith-to-llvm` 也確認
truncf→E8M0 沒有 LLVM conversion，op 原地不動。

**分歧的位置也跟著修正**：硬體只讀 exponent 之後，**兩條 lowering 其實一致（都是 1.0）**，
落單的是 APFloat 的 round-to-nearest。分歧整個縮回 `arith` 內部：

| `1.6 : f16` → `f8E8M0FNU` | 結果 |
|---|---|
| `--arith-expand=include-f8e8m0`（`F8E8M0TruncFOpConverter`，抽 exponent＝往零捨去） | **1.0** |
| `APFloat::convert`（folder／常數屬性，RNE） | **2.0** |

`kDefaultRoundingMode` 是 `NearestTiesToEven`，但 `F8E8M0TruncFOpConverter`
一看到 rounding mode 屬性就 bail——**兩邊對「沒寫 rounding mode」的解讀相反**。
副作用：`arith.truncf %x to_nearest_even : f32 to f8E8M0FNU` 在該 pass 下 fail to legalize，
**唯一寫得出來的 rounding mode 正好是它拒絕的那個**。

回覆已把問題收窄成這一題並問該改哪一邊，同時直說**讀不懂 krzysz00 的 E5M3 論點**
（exponent-only 定義下 E5M3 兩條路都會掉 mantissa）。與其猜著回，不如問。

[回覆連結](https://github.com/llvm/llvm-project/issues/215295#issuecomment-5248174927)
／草稿：[`patches/mxfp-scale-divergence-reply.md`](patches/mxfp-scale-divergence-reply.md)

#### 線 A′：[Issue #215445](https://github.com/llvm/llvm-project/issues/215445)（2026-08-11 新開，查證線 A 時撞到）

`APFloat::convert` 轉進 `f8E8M0FNU` 時**不看 `hasSignedRepr` 也不看 `hasZero`**，
負數與零都被當成無損轉換。負數會讓 `mlir-opt` 直接 abort：

```mlir
%c = arith.constant -2.000000e+00 : f8E8M0FNU   // 連 pass 都不用跑
```

```
This floating point format does not support signed values
UNREACHABLE executed at llvm/lib/Support/APFloat.cpp:3178!
```

| 項目 | 內容 |
|---|---|
| 根因 | `IEEEFloat::convert` 只做 `semantics = &toSemantics;`，`sign` 原封不動，回報 `opOK` ＋ `losesInfo == false` |
| 受害者 | `convertFloatValue`（`ArithOps.cpp:1711`）靠 `losesInfo` 把關，因此放行 |
| 爆點 | AsmPrinter 印成 `-2.000000e+00` 再 re-parse，撞 `convertFromString` 的 unreachable |
| reproducer | ① `truncf(-2.0 : f32)` 走 `--canonicalize`；② **完全不跑 pass**，直接寫負的 E8M0 常數 |
| 零的部分 | 不 crash，但 folder 給 2^-127、expansion 給 `0.0`（同一個根因的另一半，`hasZero == false`） |
| 基準 | `11799583db91`（乾淨 upstream main，assertions build） |

**第二個 reproducer 是刻意找的**：只有第一個的話，很容易被回成「那是 arith folder 的鍋」。

⚠️ **labels 設不上。** 建 issue 時帶的 `crash / floating-point / llvm:adt / mlir` 被丟掉，
事後補打 API 回 **403 Must have admin rights**。已在文末手動
cc `@tgymnich @krzysz00 @umangyadav @kuhar`。
✅ **2026-08-11 實查：triager 已上標 `llvm:support` / `mlir:arith`。**
**結論：非 admin 貢獻者設不了 label，交給 triage 就好，不用再試 API。**

草稿：[`patches/e8m0-negative-sign-issue.md`](patches/e8m0-negative-sign-issue.md)

**兩條線都在等回應。** #215445 表態傾向**回報 loss**（呼叫端本來就都在檢查 `losesInfo`；
在一個契約就是「回報失真」的函式裡靜默改值不合理），方向確定就能送 patch ＋ 兩個 reproducer 的測試。

#### 線 B：[PR #215318](https://github.com/llvm/llvm-project/pull/215318)（已送出 2026-08-11）

`LowerVectorTransfer.cpp` 六個 pattern 全部拒絕 masked op。本發做其中兩個。
完整分析與答辯稿：[`notes/vector-masked-transfer-lowering.md`](notes/vector-masked-transfer-lowering.md)

核心洞見：**mask 不需要任何變換**——transfer 的 mask 活在記憶體維度順序
（`inferTransferOpMaskType` 用 inverse permutation 映回去），而這兩個改寫
只重排結果順序。passthru 才要轉置（它活在結果座標系）。

> ⚠️ **M1-c 的舊記錄過期了。** TODO.md 原本寫「四處 TODO 是同一個缺口、
> 一次補掉是有份量的 patch」。2026-08-10 實查：今天的 main 上是**十處，
> 分屬 7 個獨立的 fold 常式**，各自要獨立論證，不是一次補完的題目。

**撞車**：PR #200703（open，作者 `SeongjaeP`）動同一批函式（0-d guard，非 mask），
行號相鄰。已在 PR 描述點名，並在留言 heads-up 給對方。

| 驗證 | 結果 |
|---|---|
| 建置 | 3664 目標，零錯誤零警告 |
| `check-mlir` | **3847 passed / 0 failed**（611 unsupported、1 expectedly failed 皆正常） |
| 既有測試 | 3 個如預期改變、**4 個維持不變**（屬未改動的 pattern，仍斷言「不支援」） |
| `git clang-format` | 乾淨 |
| 改動幅度 | 2 檔，+34 −20 |

**reviewer**：`@banach-space`（Andrzej Warzyński）——他**寫了
`MaskableOpRewritePattern` 這個基礎設施本身**，也是那個測試檔最大的作者（10 commit）。
這是「找對人」的範例：不是找檔案的最大作者（這個檔案作者很分散），
而是找**這個機制的作者**。

**實測驗證了核心推論**：三個案例的 mask 型別改寫前後完全相同
（`vector<8x4xi1>`、`vector<2x4xi1>`、scalable 的 `vector<2x[4]xi1>`），
`vector.mask` 的 verifier 也接受了——推論若錯會當場被擋。

### ⚠️ 建置狀態的坑（2026-08-10 又踩一次）

在**基準差很遠的兩個分支之間切換**，會讓 build 目錄整批作廢：
先前為了跑 #215123 的 check-mlir 而在新基準（`08cb7d93`）編過一批物件，
回到舊基準（`27f1aa4c`）時 ninja 要重建 **3737 個目標**。

**教訓**：往前建到 `origin/main`，不要為了省事回頭接在舊基準上——
兩個方向成本一樣，但建到新的才會一直有用。vector 分支因此直接開在 `origin/main`。

<details>
<summary>📜 2026-08-09 當時的狀態（保留供對照）</summary>

| PR | 內容 | 狀態（2026-08-09 實查） | CI |
|---|---|---|---|
| [#214622](https://github.com/llvm/llvm-project/pull/214622) | M0：`AtomicRMWKind` switch 窮盡（NFC） | ✅ **kuhar 已 APPROVE**（14:31，無留言，純批准） | Linux / Windows pass，AArch64 pending |
| [#214637](https://github.com/llvm/llvm-project/pull/214637) | M1-a：`ceildivsi` MININT 折疊 | open，仍無回應 | — |
| [#214919](https://github.com/llvm/llvm-project/pull/214919) | M1-b0：`f8E8M0FNU` NaN 被折成 Inf（APFloat miscompile） | 🟡 **janr-bay 說 LGTM**（14:14），但他不是 maintainer，轉手 @matthias-springer | **全綠**（Linux / AArch64 / Windows / macOS arm64 / code_formatter） |

janr-bay 原文：
> Thanks for the fix. LGTM, but I'm not a maintainer. @matthias-springer could you have a look at this?

</details>

### 🔥 M1-b 現況（2026-08-10 完成）

分支 `arith-scaling-fold`，基準 `main = 27f1aa4c9a42`，單一 commit `66b9c0eef219`，
3 檔 **+280 行**。**已送出 [PR #215123](https://github.com/llvm/llvm-project/pull/215123)。**

完整分析與答辯稿：[`notes/scaling-op-constant-folding.md`](notes/scaling-op-constant-folding.md)
PR 描述（＝ commit 訊息，squash merge 後就是它）：[`patches/m1b-scaling-fold-pr-body.md`](patches/m1b-scaling-fold-pr-body.md)
驗證工具：[`tools/verify-scaling-fold/verify.py`](tools/verify-scaling-fold/verify.py)

| 驗證 | 結果 |
|---|---|
| 窮盡 sweep | **16,785,408 組**，三項檢查（值 vs 展開 oracle、值 vs Python oracle、折/不折決定）**全部 0 分歧** |
| `check-mlir` | 4450 tests，**3838 passed / 0 failed** |
| 新增 lit 測試 | 14 個（含 5 個「不該折」的負面測試 ＋ 2 個 poison） |
| `git clang-format` | 乾淨 |
| 撞車複查（2026-08-10） | `scaling_extf`／`scaling_truncf` 各 0 筆；`f8E8M0FNU+fold` 命中 #210422，實查只動 `emulate-wide-int.mlir`，**不撞** |

**與原計畫的兩處差異（本人已同意）**：

1. **合成一發，不分兩發。** precommit test 的價值是顯示「哪些既有行為改變了」，
   但這裡測試全是新增的，且 diff 裡 `hasFolder = 1` 本身就說明先前沒有 folder。
   要做出可信的 precommit commit 得還原 `.td` 再重建（1085 目標／1.5 小時），來回三小時不划算。
2. **truncf 的窮盡掃描輸入型別用 `f16` 不是 `f8E4M3FN`。** 展開鏈裡有
   `extf(scale : f8E8M0FNU → 輸入型別)`，所以輸入必須嚴格寬於 8 bit。
   組合數因此從 65536 變成 16,777,216。

**2026-08-09 已留的兩則留言：**

1. #214622 — 請 kuhar 代為 merge，署名 `Hung-Kuan Tseng <p76091014@gs.ncku.edu.tw>`
   （＝ `git config` 的值，三支分支的 commit 本來就都是這個，全部統一）
2. #214919 — 謝 janr-bay，並 ping @matthias-springer，附四行摘要（為什麼會發生、
   為什麼看不出來、改動多小、怎麼驗的），另外主動把 `losesInfo` 該不該是 `false`
   這個不確定點列出來請他判斷

**分支同步狀態（2026-08-09 實查）：**

| 分支 | local | fork | |
|---|---|---|---|
| `arith-exhaustive-atomicrmwkind-switch` | 原本 `9ea23028` | `d3cedcc8` | patch-id 相同（`7bf3d4c7`），只是 rebase 基準不同；已把 local 設成 fork 那版 |
| `arith-ceildivsi-minint-fold` | `73b28d75` | 同 | ✅ |
| `apfloat-e8m0-nan-convert` | `2ddc0c54` | 同 | ✅ |

另外本地有一支空分支 `apfloat-e8m0-nan-to-inf`（停在 `main`，0 個 commit，沒推上 fork），
2026-08-09 已刪。現在本機只剩三支 PR 分支 ＋ `main` ＋ worktree 的 `explore`。

**下一步：M1-c／M1-d（`vector`）**——動手前必做撞車查證（M1-c 還沒查過）。
完整題目清單見下面「⭐ 題目清單」。

### 🔄 2026-08-08 專案轉向（先讀這段，不然下面的題目排序看不懂）

本人要求：**之後每一題都要對應到 AI compiler JD 真正會用到的東西。**

| 改了什麼 | 在哪 |
|---|---|
| 定位：通用編譯器基建 → **AI compiler 中端 codegen** | `Goal.md` §1.3（舊版保留在摺疊區） |
| 路線：`arith` 純量 → **`arith` 量化 op → `vector` → `linalg`/GPU** | `Goal.md` §3.1 |
| **⭐ 選題四關過濾器**（這次的核心產出，每題都要過） | `Goal.md` §8.7 |
| 里程碑加 M5、標註 M4→M5 的斷點 | `Goal.md` §5 |
| 決策日誌 4 筆 | `Goal.md` §2.4 |

做的事情沒變（folder、canonicalization、正確性、可驗證證據），換的是地段。
已送出的兩個 PR 維持不動——它們的產出是流程打通與 reviewer 關係。

`kuhar` 近 12 個月在 **Vector 有 10 個、Linalg 有 9 個** commit，
所以往 vector 走是同一個 reviewer，關係可以延續。

### ⚠️ 2026-08-08 實查，修正一筆先前的錯誤紀錄

> **2026-08-09 更新：下面第 1 點已經過期。** premerge CI 現在真的跑了——
> #214919 的 Linux / AArch64 / Windows / macOS arm64 / code_formatter 全綠，
> #214622 的 Linux / Windows 也 pass。所以「本機 check-mlir 是唯一證據」這句
> 對現在的三個 PR 不再成立。下面保留原文當紀錄。

**「CI 7 項全 pass」是錯的——真正會建置 MLIR 的 CI 從來沒跑過。**
兩個 PR 上實際跑過的只有 `automate-prs-labels`（貼 label）、
`Graphite / mergeability_check`（能不能 merge）、`greeter`（skipped），
以及 `buildkite/libcxx-ci`（**libcxx，跟 MLIR 無關**，因為沒動到 libcxx 檔案而空過）。

`premerge.yaml`（**Build and Test Linux / Windows**）的狀態是 **`action_required`**
＝ 卡在「等 maintainer 按 Approve and run workflows」，這是 GitHub 對首次貢獻者的預設閘門。
`pr-code-format.yml`（clang-format 檢查）同理也沒跑。

**意義：本機的 `check-mlir` 是目前唯一的驗證證據。** 所以每次 rebase 後都要自己重跑。

---

## 環境（全部在 WSL 原生檔案系統）

| 項目 | 位置／版本 |
|---|---|
| 本 repo | `~/Side_Project/MLIR` |
| LLVM 上游 | `~/llvm-project`（主要工作區）+ `~/llvm-explore`（worktree，分支 `explore`） |
| 建置目錄 | `~/llvm-project/build` |
| 機器 | 16 核 / 31GB RAM / 928GB 可用 |
| Toolchain | clang 14.0.0、lld 14、ninja 1.10.1、ccache 4.5.1、cmake 3.22.1、z3 4.8.12 |

**⚠️ 不要把任何東西放回 `/mnt/*`（Windows 磁碟）。** 理由見 `Goal.md` §2.4 決策日誌。

建置設定與每個 cmake flag 的理由：`Goal.md` §7.3。

---

## 進行中

- [x] **push，三條** — 2026-08-12 全部完成，head 都回讀驗證過：
      #214637 `a1c2690f7d79`（force-push）、#215318 `d0170cd77b5c`（增量）、
      #215696 `b98eff9e3d64`（新開）。
      ✅ 這次 `gh pr create --body-file` 沒有踩到 projects-classic 那個坑
      （只有 `gh pr edit --body-file` 會），描述 2630 字元完整寫入，已回讀確認。

- [x] **🎉 #214637 已 MERGE** — 2026-08-12 13:39 UTC，`kuhar` 代 merge，
      squash commit `2a0c335d4538`。第三個進上游的 commit。
      留言裡附 `Hung-Kuan Tseng <tseng.tim096@gmail.com>` 說明作者身分那招有效。

- [x] **#215696 三點已改完並回覆** — 2026-08-12 force-push（head `7a0d9f0ea804`），
      三則 inline（[r3767492306](https://github.com/llvm/llvm-project/pull/215696#discussion_r3767492306)、
      [r3767492472](https://github.com/llvm/llvm-project/pull/215696#discussion_r3767492472)、
      [r3767492664](https://github.com/llvm/llvm-project/pull/215696#discussion_r3767492664)）
      ＋ 一則 top-level（[5268408619](https://github.com/llvm/llvm-project/pull/215696#issuecomment-5268408619)）。
      已回讀確認 `in_reply_to_id` 對上原 comment。**球在 kuhar 那邊。**
      💡 這台機器沒有 `jq`，要組 JSON body 用 `python3 -c` 寫檔再 `gh api --input`；
      `gh --jq` 是內建的，可以用。

- [x] **#215696 同步兩項優化** — 先判符號本來就是對的，乘法取代 srem 已補上。
      兩個 dialect 的 ceildivs 現在算法完全一樣。

- [x] **回覆全部送出** — 2026-08-12（UTC 08-11 23:17）：
      #214637 一則 top-level（[5259965488](https://github.com/llvm/llvm-project/pull/214637#issuecomment-5259965488)）；
      #215318 兩則 inline（[r3762420018](https://github.com/llvm/llvm-project/pull/215318#discussion_r3762420018)、
      [r3762420126](https://github.com/llvm/llvm-project/pull/215318#discussion_r3762420126)）
      ＋ 一則 top-level（[5259966583](https://github.com/llvm/llvm-project/pull/215318#issuecomment-5259966583)）。
      已回讀確認 `in_reply_to_id` 對上原 comment。
      💡 inline 回覆要用 `gh api repos/.../pulls/<n>/comments/<comment_id>/replies`，
      才會 threaded 在原留言底下；貼到 `issues/<n>/comments` 只會變成獨立的 top-level。

- [x] **#215123 rebase** — 2026-08-12 已完成，`mergeable=true`，premerge 全綠。

- [x] **#215318 本地對齊 fork** — 2026-08-12 已 `reset --hard fork/...`（`3eddbc33`）。

- [x] **ping #214637** — 2026-08-11 已送出（開了 4 天、零 review）。
      內容：premerge 現在全綠、仍 clean、patch 未變，並點名唯一動到的既有測試
      （`ceildivsi_overflow` → `ceildivsi_minint_dividend`）。
      [留言連結](https://github.com/llvm/llvm-project/pull/214637#issuecomment-5253490654)

- [x] ~~**待本人處理：把 GitHub profile 顯示名改成 `Hung-Kuan Tseng`**~~
      **2026-08-18 本人已改，實查 `gh api user --jq .name` 回 `Hung-Kuan Tseng`。**
      在此之前 merge 的五個 commit 都是少連字號的版本，往後才會對。

- [ ] **等兩個 PR 落地** — #216056 已於 08-17 merge，剩下兩個**都已 approve、只差有人按按鈕**：
      **#215123** `tgymnich` 08-17 approve，rebase 已做（head `96dfbf939686`），推上去後等他代 merge；
      **#215696** `kuhar` 08-14 approve 等第二人，已在 #215295 的回覆末尾搭便車催過，
      **不要再單獨開 ping**（08-16 才推過一次，連催兩則語氣會難看）。

- [x] ~~**#216056 merge 後：關掉 #215445**~~ — `tgymnich` merge 時 GitHub 自動關掉了
      （2026-08-17 09:21:36 UTC，`state_reason: completed`）。08-17 17:03 那則通知不是新內容，
      是 `EugeneZelenko` 把 label 從 `mlir:arith` 改成 `mlir`，觸發機器人重貼內文給訂閱群。

- [ ] **等兩個 issue 的方向** — #215295（scale 語意，兩位 maintainer 對怎麼修沒共識）、
      #215445（`APFloat::convert` 不回報 sign／zero 失真，含 crash）。
      **2026-08-13 各 ping 一次，都帶了新資訊**（見上面）。
      #215445 已表態「沒人反對就送 patch」，**再等一輪沒人回就動手**；
      #215295 仍然不要替 maintainer 選邊。

- [x] **M1-b0：`f8E8M0FNU` 的 NaN 被折成 Infinity（APFloat miscompile）**
      — 做 M1-b 探測邊界時撞到的。**已送出 [PR #214919](https://github.com/llvm/llvm-project/pull/214919)**
      （分支 `apfloat-e8m0-nan-convert`，基準 `main` = `27f1aa4c9a42`，單一 commit `2ddc0c5d4475`）。
      `arith.extf` 把 E8M0 的 NaN 常數折成 `+inf`。根因在 `llvm::APFloat::convert`：
      E8M0 的 `precision = 1`，NaN payload 是 0 個位元，widen 之後 significand 全零
      ＋ NaN 指數 = 目標格式裡 infinity 的編碼。
      完整分析、驗證、四關判定：`notes/e8m0-nan-becomes-inf.md`。
      **這是 M1-b 折疊的前提**（折疊的語意鏈中間就是這個 extf）。
      本機狀態：`APFloatTest` 186 全過、`ADTTests` 2187 全過、`check-mlir` 3841 全過；
      拿掉修復後新測試會紅（已實測）。

- [x] **🔥 M1-b：`arith.scaling_extf` / `scaling_truncf`（MXFP4/FP8 量化 op）**
      — **2026-08-10 已送出 PR #215123，見上面「M1-b 現況」。**
      第 1 關的具體證據（實測）：`-arith-expand -canonicalize` 會折、
      單獨 `-canonicalize` 不會折 ＝ 走硬體 lowering 的 pipeline 拿不到折疊。
      `ExpandOps` 與 `ArithToAMDGPU` 對非 E8M0 scale 語意不一致
      （`1.6 : f16` → 前者 2.0、後者 1.0），所以折疊限制在 scale 已是 `f8E8M0FNU`。
      完整分析與答辯稿：[`notes/scaling-op-constant-folding.md`](notes/scaling-op-constant-folding.md)。

- [ ] **決定 ArithToSMT 要怎麼走** — 見 `notes/arith-to-smt-exploration.md` §5。
      建議：先在 PR #131484 留一則有憑有據的意見（具體反例＋上游既有正解位置＋
      指出零測試），看作者反應再決定要不要徵求接手。
      ⚠️ 對外公開動作，送出前要本人確認。
      **⚠️ 過濾器判定：這題過不了 §8.7 第 1／2 關**（AI pipeline 走不到、
      履歷關鍵字為零）。**降級為 M4 引擎的內部零件，不算 M1 的一發。**

- [ ] **決定 Q1（rounding mode）要怎麼收尾** — 證明已完成（z3，三個 pattern 全證），
      但撞到 PR #209287。**過濾器判定：過不了第 1／2 關**——AI 推論不設 custom
      rounding mode。**不當履歷題，改當 M4 的第一個示範案例**（工具能自動吐出
      `x=-0.0 ∧ RTN` 這個反例，就是 M4 有效的第一個證據）。
      留言給 #209287 仍值得做（低成本、建立能見度）。⚠️ 對外動作，要本人確認。

---

## ✅ M0 — 已送出（2026-08-07）

**PR：https://github.com/llvm/llvm-project/pull/214622**
`[mlir][arith][NFC] Make AtomicRMWKind switches exhaustive`，1 檔 +6 −6。

| 項目 | 結果 |
|---|---|
| 建置 | 零警告 |
| 目標測試（Arith / Transforms / Affine / OpenACC）| 276/276 passed |
| `check-mlir` | **3839 passed / 0 failed** |
| `git clang-format` | 乾淨 |
| CI | 7 項全 pass |
| labels / reviewer | `mlir`、`mlir:arith` / `kuhar`（皆自動） |

**送出前的關鍵驗證**——拿掉 `default:` 重新編譯，讓 `-Wswitch` 自己列出未處理的值，
實測兩處各一則、且只有 `assign`。比人工比對可靠，而且 reviewer 可以自行重現。

### reviewer 若提問，要能不看筆記回答

| 提問 | 答案 |
|---|---|
| 怎麼確定只缺 `assign`？ | 拿掉 `default:` 編一次，`-Wswitch` 逐一點名。實測只有 `assign` |
| 真的是 NFC？超出範圍的 enum 值呢？ | 診斷移到 switch 之後，那條路徑照舊得到同一個診斷 |
| 為何不用 `llvm_unreachable`？ | 那會把超出範圍的值從診斷變成 abort，就不是 NFC。是另一個議題 |
| `assign` 為什麼存在？ | 在 `memref.atomic_rmw` 有效（lower 成 `xchg`），只是不是 reduction |

## VS Code 開發環境（2026-08-07 建好）

用 **`~/Side_Project/MLIR/mlir-dev.code-workspace`** 開，會同時掛上本 repo 與
`llvm-project` 兩個資料夾。

**一鍵執行**：開著任一 `.mlir` 檔按 **`Ctrl+Shift+B`**
→ 先 `ninja mlir-opt`（沒改東西約 1 秒）再跑 `--canonicalize`。
「先建置再執行」是刻意的：拿舊執行檔測新程式碼會得到看起來很像真的錯誤結論。
裝了 Code Runner 後右上角 ▷ 也可以直接跑（只跑不建置，改過 C++ 時別用這個）。

其他任務在 Terminal → Run Task，清單見 `playground/README.md`。

設定檔位置（**都被上游 `.gitignore` 蓋掉，不會誤入 PR，已確認**）：
`~/llvm-project/.vscode/{settings,tasks,launch,extensions}.json` 與 `~/llvm-project/.clangd`

已裝擴充：`vscode-mlir`、`vscode-clangd`、`code-runner`。
⚠️ `settings.json` 已把 **cpptools 的 IntelliSense 關掉**（`C_Cpp.intelliSenseEngine: disabled`），
因為兩個引擎同時開會打架；但 cpptools 擴充本身要留著，`launch.json` 的偵錯靠它。

⚠️ `cmake.configureOnOpen` 等三項已關閉——不然 cmake-tools 可能自動 reconfigure，
把 `Goal.md` §7.3 那組精選 flag 沖掉。

⚠️ **刻意不開 `formatOnSave`**：整檔格式化會動到你沒碰的區域，diff 立刻多出幾百行雜訊。
LLVM 的正確做法是只格式化改動的行 = `git clang-format`，已做成任務。

---

## 環境驗收（2026-08-07 全數通過）

**🎉 M-1 達成** — `ninja check-mlir`：**3838 passed / 0 failed**
（611 unsupported 是需要 GPU/特定 target 的測試，正常；1 expectedly failed 也是預期內）。
測試耗時 435s，全建置約 1.5 小時。

| 檢查項 | 結果 |
|---|---|
| `mlir-opt` | ✅ LLVM 24.0.0git，**Optimized build with assertions**（符合 `Goal.md` §7.3） |
| `mlir-translate` / `mlir-reduce` / `mlir-lsp-server` | ✅（`mlir-reduce` 是 M2 要用的） |
| `llvm-lit` / `FileCheck` / `not` | ✅ |
| 單檔 lit test | ✅ `canonicalize.mlir` + `constant-fold.mlir` 2/2 passed |
| `mlir-opt` 實跑真實 IR | ✅ 見 `notes/ceildivsi-minint-analysis.md` §4 |
| `clang-format` | ✅ **22.1.0**（見下方注意事項） |
| `git clang-format` | ✅ 實測可跑 |
| fork push 權限 | ✅ `git push --dry-run` 通過 |
| z3 | ✅ 4.8.12 |
| `gh` | ✅ 2.4.0（舊但堪用） |
| 磁碟 | ✅ 921G 可用，build 目錄僅 1.7G |

### ⚠️ clang-format 的坑（重裝環境時會再遇到）

1. **版本必須對齊上游 CI。** 上游 `pr-code-format.yml` 用容器
   `ghcr.io/llvm/ci-ubuntu-24.04-format`，其 Dockerfile 釘死
   `LLVM_VERSION=22.1.0`。**apt 只有 14，差 8 個大版本，格出來會跟 CI 不一致**。
   解法：`pip3 install clang-format==22.1.0`（不需要 sudo）。

2. **PATH 設定有兩層陷阱。** pip 裝到 `~/.local/bin`：
   - `~/.profile` 有加 `~/.local/bin`，但只在 **login shell** 生效，
     且該目錄是裝完才建的，當下的 shell 抓不到
   - `~/.bashrc` 對**非互動 shell 會提前 `return`**，加在檔尾永遠跑不到
     → 要插在 early-return **之前**（已處理）

3. **最可靠的是完全不依賴 PATH**，直接告訴 git 位置（已設定，重灌環境要重設）：

   ```bash
   git config --global alias.clang-format '!'"$HOME"'/.local/bin/git-clang-format'
   git config --global clangformat.binary "$HOME/.local/bin/clang-format"
   ```

### 重跑 build 的指令

```bash
pgrep -a ninja                       # 還活著嗎
tail -20 ~/llvm-project/build/build.log
cd ~/llvm-project/build && setsid nohup ninja check-mlir > build.log 2>&1 < /dev/null &
```

### ⚠️ 兩個已經實際踩過的坑

**1. 一定要用 `setsid` 讓它脫離 session。**
第一次跑沒加，終端機 session 結束時整個 build 被帶走。
（副作用：`setsid` 脫離後 `pkill -f "ninja check-mlir"` 不一定殺得掉，
要用 `pgrep -a ninja` 拿 PID 再 `kill`。）

**2. 🔥 絕對不要同時跑兩個 ninja 在同一個 build 目錄。**
2026-08-07 實際踩到：背景 `check-mlir` 跑到一半，另開一個 `ninja mlir-opt`，
結果測試大量 FAIL，訊息是

```
mlir-opt: error while loading shared libraries: libLLVMX86Desc.so.24.0git:
cannot open shared object file
```

因為我們用 `BUILD_SHARED_LIBS=ON`，第二個 ninja 重新連結 `.so` 的**瞬間**，
正在執行的測試就找不到函式庫。**這種失敗跟程式碼完全無關，但看起來很像真的迴歸**——
會浪費大把時間去 debug 一個不存在的 bug。

**判斷方法**：看到 `error while loading shared libraries` 就知道是這個原因，
不是你的 patch 壞掉。做法是等前一個跑完，或先 `kill` 掉再重跑。

---

## 下一步（依序）

### 0. 送 PR 的前置設定

**✅ 全部就緒（2026-08-07）**

| 項目 | 現況 |
|---|---|
| GitHub 帳號 | **`Tim096`**（曾鈜寬 Tseng Hung Kuan） |
| `gh` CLI | ✅ 已裝並 `gh auth login` 完成 |
| fork | ✅ `Tim096/llvm-project` |
| `fork` remote | ✅ `https://github.com/Tim096/llvm-project.git` |
| git identity | ✅ `Hung-Kuan Tseng` / `p76091014@gs.ncku.edu.tw`（全域） |

`origin` 維持指向 `llvm/llvm-project`（fetch 上游用），`fork` 才是 push 的地方。

> ⚠️ **踩過的坑**：一開始只憑姓名去猜 GitHub 帳號，猜成 `hungkuan`——
> 那是一個 2014 年建立、0 repo 的**別人的**帳號，remote 一度指錯。
> 正確做法是直接讀 `gh auth status`，不要猜。

### ~~兩個還沒定案的個資決定~~ ✅ 已定案並用於 PR #214622

1. **email 會永久公開在 LLVM commit 歷史裡。** 現在是學校信箱
   `p76091014@gs.ncku.edu.tw`，畢業後可能失效。
2. **`user.name` 現在是 `HungKuan`。** LLVM 慣例是用完整真名
   （GitHub 上登記的是「曾鈜寬 Tseng Hung Kuan」），例如 `Hung-Kuan Tseng`。
   履歷要對得起來的話，這裡的名字最好跟 GitHub profile 一致。

```bash
git config --global user.email "<新的>"
git config --global user.name  "<新的>"
```

### 1. ~~先確認沒撞車~~ ✅ 已完成（2026-08-06）

用 GitHub search API 掃過 open PR，結論在下面各題目底下。**兩個題目都安全。**

```bash
# 用過的查法（gh 沒裝，直接打 API；未認證有 rate limit 但夠用）
curl -s "https://api.github.com/search/issues?q=repo:llvm/llvm-project+is:pr+is:open+<關鍵字>" \
  | grep -E '"(number|title)"' | paste - -
# 看某個 PR 動了哪些檔案 ← 判斷有沒有真的撞到，只看標題會誤判
curl -s "https://api.github.com/repos/llvm/llvm-project/pulls/<N>/files" | grep '"filename"'
```

### 2. ~~M0 — 打通 PR 流程~~ ✅ **已送出 PR #214622**，詳見上面「✅ M0」段落。

### 3. ~~M1 第一發 — `ceildivsi` MININT folding gap~~ ✅ **已送出 PR #214637**

`[mlir][arith] Fold ceildivsi with MININT operands`，2 commit、2 檔、+81 −74。

**做法**：不取負，改用 `sdiv` 往零截斷的性質 + `srem` 判斷是否除盡。
與上游 `ExpandOps.cpp` 展開 `ceildivsi` 用的公式同構。

| 證據 | 內容 |
|---|---|
| Alive2 | https://alive2.llvm.org/ce/z/Chnon4 → `Transformation seems to be correct!` |
| 窮盡測試 | i4 240/240、i8 65280/65280 全對（Python 精確 ceiling 當 oracle）|
| 改善幅度 | i8 未折疊數 **507 → 1**；兩版折錯皆為 0 |

**兩份證據刻意互補**：Alive2 是符號式證明但只證「與 ExpandOps 一致」，
萬一 ExpandOps 也錯就一起錯；oracle 掃描則獨立於任何 LLVM 實作。

**意外發現**：上游 TODO 只提 `a`（被除數）是 MININT，
但 `b`（除數）是 MININT 也一樣漏折，且在 507 組中佔 **254 組、超過一半**。
**這一側從沒有人記錄過**，是本 patch 比停擺的舊 PR #90855 多做到的部分。

**用到的社群慣例**：precommit test——第一個 commit 只加測試、
CHECK 反映改動前行為；第二個 commit 才是修正 + CHECK 的 diff。
這樣 reviewer 一眼看得出哪些行為真的變了。

⚠️ 本 patch **動到既有測試** `@simple_arith.ceildivsi_overflow`
（改名為 `ceildivsi_minint_dividend`），PR 描述已主動點名。

### reviewer 若提問（要能不看筆記回答）

| 提問 | 答案 |
|---|---|
| 這是修 bug 嗎？ | 不是。舊版正確但保守，是**漏折疊**不是算錯。折錯數改動前後都是 0 |
| 為什麼舊版會漏？ | 它先把負數取負變正。`i8` 負數比正數多一個，`-(-128)=128` 放不進去就溢位放棄 |
| 新演算法為什麼對？ | `sdiv` 往零截斷，答案為負時就等同往上取整；只有同號（答案為正）且除不盡才要補 1 |
| 還有什麼不折？ | 只剩 `b == 0` 與 `MININT / -1`（後者答案 `-MININT` 本身放不進型別）|
| 怎麼確定沒漏？ | i4/i8 全窮盡比對數學精確值，不是抽樣 |

### ~~4. M1 主菜 — rounding mode 安全性~~ ⬇️ **2026-08-08 降級**

證明已完成（z3，三個 pattern 全證，見下面 Q1），但**過不了 `Goal.md` §8.7 第 1／2 關**
——AI 推論不設 custom rounding mode，履歷關鍵字為零。
**改當 M4 驗證器的第一個示範案例**，不當 M1 的一發。

### 4'（新）. M1 主菜 — `scaling_extf` / `scaling_truncf` 的 MXFP 量化折疊

見下面「⭐ 題目清單」的 **M1-b**。

### 5. 2026-09-05 現況：等十五個 open PR

- 等 merge：#215696（kuhar approve，第二人未出現）、#221248（mplatings approve）。**已 approve 未 merge 就禮貌 ping，要帶新資訊。**
- 等 review：#217892（krzysz00）、#221185（dcaballe）、#221268（banach-space／dcaballe／FedericoBruzzone）、#221288（fabianmcg／grypp）、#221293（banach-space／hanhanW）、#221298（raikonenfnu／banach-space／dcaballe）。09-05 實查前七個都沒有新 review。
- 第二次掃描已做完 → `notes/gpu-linalg-patch-candidates.md`；GPU-1 已送出為 #221288，L-1 已送出為 #221293，V-1 已送出為 #221298，VS-1（VectorToSCF 的 `vector.mask`）為 #221307，GPU-4 為 #221308，GPU-3 為 #221312，GPU-3 同款的 `ElideReinterpretCast` 為 #221314；GPU-2 查證後不是 bug。 全樹掃描（`notes/attr-drop-sweep.md`）再送 #221317／#221319／#221320；**還有四處位址不變的可送（等前兩個的 review 意見），四組位址會移的要重算 alignment。****剩 L-2（設計風險）、V-2（價值低），先等 review。**

---

## 未解問題（有結論就搬進 `notes/`）

### ~~⭐ Q1：三個 canonicalization 在 custom rounding mode 下到底安不安全？~~ ✅ 已解（2026-08-08）

**答案：mul / div 安全，subf 不安全，且 subf 的反例是唯一的一組。**
用 z3 的 IEEE-754 浮點理論（`QF_FP`）證明，f16 / f32 / f64 三種寬度全跑。
`rm` 宣告成自由變數 → **一次證完所有捨入模式**，不是逐一列舉。

| Pattern | 結果 |
|---|---|
| `MulFOfNegF` | `unsat` = 所有捨入模式下保值 ✅ |
| `DivFOfNegF` | `unsat` = 所有捨入模式下保值 ✅ |
| `SubFOfNegZero` | `sat` → 反例 **`x = -0.0` ∧ `roundTowardNegative`**；排除這一組後 `unsat`，代表**整個輸入空間就只有這一組** |

原本的手推結論完全正確，現在有機器證明背書。

> 📄 完整分析、證明腳本、以及可重跑的 `notes/rounding-mode-proofs/run.sh`
> 見 [`notes/rounding-mode-canonicalization.md`](notes/rounding-mode-canonicalization.md)。

**⚠️ 但這題不能直接開 PR 送**，撞車查證查到
PR **[#209287](https://github.com/llvm/llvm-project/pull/209287)**
`[mlir][arith][RFC] Add new strict FP handling in Arith`（`andykaylor`）
動的正是這三個 pattern：替每個浮點 op 加 `$fenv` 運算元、三個 pattern 各多一道 bail、
**TODO 原封不動留著**。而且 PR 描述明講現有的 rounding-mode 機制
「is intended to be **replaced** / should be considered **deprecated**」。

→ 直接送會衝突，而且論述前提可能被抽掉。
**建議改成在 #209287 留一則有憑有據的意見**（他保留 TODO 又多加 bail，
代表他也沒驗證；我們正好補上這塊）。⚠️ 對外動作，送出前要本人確認。

### ~~Q2：`arith.muli` 的 overflow TODO 到底想講什麼？~~ ✅ 已結案，**不建議做**（2026-08-08）

`ArithOps.cpp:654` 的 `// TODO: Handle the overflow case.`
是 **2021 年 `arith` 從 `std` 拆出來時就在的**（`git log -L` 查到，commit `8c08f21b6041`,
Mogball），**那時 `muli` 根本還沒有 `nsw`/`nuw` flag**。

以今天的語意讀，它指的是「`nsw`/`nuw` 溢位時該折成 poison，而不是折成繞回的常數」。
但 `ArithOps.cpp` 裡有 **11 處**寫著同一句：

```cpp
// ... would need the ub dialect to materialize ub.poison; left out for now.
```

這是上游**反覆做過的刻意決定**，不是疏漏。單獨替 `muli` 補會前後不一致，
還會引入 `arith` → `ub` 的相依。**那是 RFC 題目，不是 M1 patch。**

（附帶查證：把折成 poison 的 op 折成具體常數**不是 miscompile**——
poison 可以 refine 成任何值，方向是對的。所以這裡沒有正確性 bug，只是精度較差。）

### ~~Q3：MLIR 的 `smt` dialect 現在還在嗎？~~ ✅ 已解（2026-08-07）

**在，而且比預期完整。** 但有兩個關鍵限制，直接影響 M4 怎麼設計。

有的東西：
- `mlir/{include,lib}/Dialect/SMT` — dialect 本體
- `mlir/lib/Target/SMTLIB/ExportSMTLIB.cpp` — **能匯出成 SMT-LIB 文字**，
  可以直接餵給已裝好的 z3，不必自己接 C++ binding
- types：`Bool` / `Int` / `BitVector` / `Array` / `SMTFunc` / `Sort`
- bitvector 理論 op 齊全：`add mul udiv sdiv urem srem smod shl lshr ashr
  and or xor not neg cmp concat extract repeat bv2int int2bv`
  → **`arith` 的整數 op 幾乎可以一對一對應**

⚠️ **限制一：merge 進 main 的沒有 `ArithToSMT` conversion**——但**有一個停擺的 draft PR**。

> 📄 **完整探查見 [`notes/arith-to-smt-exploration.md`](notes/arith-to-smt-exploration.md)。**
>
> PR **#131484**（`makslevental`，就是上游化 SMT dialect 的同一人）：
> draft、2025-03-16 開的、**17 個月零留言零 review**、+498 行。
> 骨架合理，但 **`ceildivsi` 的轉換數學上是錯的**（用 `(a+b-1)/b`，
> 而 `arith.divsi` 往零截斷，只在 `a>0 且 b>0` 可靠；10 取樣錯 6），
> **而且該 pattern 零測試覆蓋**。上游 `ExpandOps.cpp:91` 早就有正確版本。
>
> ⚠️ **教訓**：第一次掃只用 `ls mlir/lib/Conversion/ | grep -i smt` 看本地 source tree，
> 結論「上游完全沒有」是錯的——**看不到未 merge 的 PR**。
> 判斷有沒有人做過，一定要同時搜 open PR。

⚠️ **限制二：`smt` dialect 沒有浮點理論。** types 裡沒有 FloatingPoint，
全樹 grep 不到 `fp.` / `RoundingMode` 之類字樣。
**所以 Q1（rounding mode 那三個 pattern）走不了 `smt` dialect 這條路**——
SMT-LIB 標準本身有 FP 理論、z3 也支援，但得直接產生 SMT-LIB 文字丟給 z3，
繞過 `smt` dialect。

**對 M4 的結論**：分兩條腿。整數用 `smt` dialect（但要先自己補 `ArithToSMT`）；
浮點直接產 SMT-LIB 餵 z3。

### ~~Q4：`scaling_extf` / `scaling_truncf` 有沒有 fold 機會？~~ ⬆️ **升為 M1-b 首選**（2026-08-08）

原本標「優先度低」。套用 `Goal.md` §8.7 過濾器後**翻成第一名**，
完整內容見下面「⭐ 題目清單」的 M1-b。

---

## ⭐ 題目清單（2026-08-08 依 `Goal.md` §8.7 四關過濾器重選）

> 四關：**①真實 AI pipeline 走得到？ ②說得出 JD 關鍵字？ ③能不看筆記答辯？ ④做得出可驗證證據？**
> 表格裡的 ✅／❌ 是**已查證的結論**，不是猜測；查證指令附在各題底下。

### 總表

| # | 題目 | ①AI pipeline | ②JD 關鍵字 | 撞車 | 判定 |
|---|---|---|---|---|---|
| M1-a | `ceildivsi` MININT 折疊 | ❌ | ❌ | 無 | ✅ **已送出**，不撤（流程成本） |
| **M1-b0** | **`f8E8M0FNU` NaN → Inf（APFloat miscompile）** | ✅ | ✅ quantization | **無** | 🔥 **改好了，等確認送出** |
| **M1-b** | **`scaling_extf`/`scaling_truncf` 折疊** | ✅ | ✅ quantization | **無** | 🔥 **M1-b0 之後** |
| M1-c | `vector.extract/insert` dynamic position canonicalization | ✅ | ⚠️ 弱 | 待查 | 🟡 備案 |
| M1-d | vector 的其他 TODO（138 個，待掃） | 待查 | ✅ vectorization | 待查 | 🟡 待掃 |
| — | `vector.contract` mixed-mode lowering | ✅ | ✅ mixed precision | ❌ **撞車** | ⛔ **不做** |
| — | Q1 rounding mode（證明已完成） | ❌ | ❌ | ⚠️ #209287 | ⬇️ 降為 M4 示範案例 |
| — | Q2 `muli` overflow | ❌ | ❌ | — | ⛔ 已結案，不做 |
| — | ArithToSMT（PR #131484） | ❌ | ❌ | ⚠️ draft 停擺 | ⬇️ 降為 M4 內部零件 |

---

### 🔥 M1-b0：`f8E8M0FNU` 的 NaN 被折成 Infinity（改動已完成，等確認送出）

完整分析在 **`notes/e8m0-nan-becomes-inf.md`**。這裡只留摘要與現況。

**是什麼**：`arith.extf` 把 E8M0 的 NaN 常數（`0xFF`）折成 `+inf`（f32 得 `0x7F800000`）。
MXFP 規格裡 NaN scale 代表「這個 block 無效」，折成 inf 等於把無效標記換成一個會傳染的巨大數。

**根因**：`llvm::APFloat`。E8M0 的 `precision = 1` → NaN payload 是 0 個位元 →
widen 時 significand 左移仍是全零 → 「NaN 指數 ＋ 全零 significand」在有 infinity 的
目標格式裡正好是 inf 的編碼。`APFloat` 物件的 `category` 還是 `fcNaN`（`isNaN()` 回 true），
但 `bitcastToAPInt()` 吐出 inf 的位元，而 `FloatAttr` 存的就是那串位元。

**改動**（3 個檔案，+62 行）：

| 檔案 | 內容 |
|---|---|
| `llvm/lib/Support/APFloat.cpp` | `IEEEFloat::convert()` 的 `fcNaN` 分支加 8 行：來源格式沒有 significand 時，改建目標格式的標準 qNaN |
| `llvm/unittests/ADT/APFloatTest.cpp` | 新增 `Float8E8M0FNUNaNConvert`，檢 f16/bf16/f32/f64 四個目標的位元圖樣，並把位元讀回來確認仍是 NaN |
| `mlir/test/Dialect/Arith/canonicalize.mlir` | 新增 `@extFPConstantE8M0NaN` 與 `@extFPVectorConstantE8M0NaN` 兩個 lit 測試 |

**驗證現況**：

| 項目 | 結果 |
|---|---|
| 窮盡掃描（256 個 E8M0 值 × f16/bf16/f32/f64/f128） | 0 failures |
| 拿掉修復後新測試是否會紅 | 會（已實測，`Actual: false / Expected: true`） |
| `APFloatTest` | 186 全過 |
| `ADTTests` | 2187 全過 |
| `check-mlir` | 3841 passed / 0 failed |
| 撞車查證 | `E8M0+NaN`、`Float8E8M0FNU+convert` 搜 open PR / issue，無相關 |

**已送出**：[PR #214919](https://github.com/llvm/llvm-project/pull/214919)（2026-08-08）。
分支 `apfloat-e8m0-nan-convert`，基準沿用前兩發的 `main` = `27f1aa4c9a42`，單一 commit。
送出時的 PR 上還沒有 label（label bot 尚未跑）。

**commit 沒有加任何 AI 揭露 trailer**，沿用 2026-08-08 對前兩發的決定（見上面「實查」段）。

**PR 上已留兩則留言**（2026-08-08）：

1. 回覆 policy bot——沿用前兩發的同一段文字（讀過三份政策、本人為作者、能答辯）
2. @janr-bay 請他看（他是 PR #204200 動 E8M0 bit 轉換那位），
   並先講清楚**這個 bug 不是他那個 PR 造成的**：問題在 `IEEEFloat::convert` 的
   一般 NaN 路徑，比 #204200 更早，只是因為 `Float8E8M0FNU` 是唯一 `precision == 1`
   的格式才顯現。

其他 APFloat.cpp 活躍作者（還沒 @）：David Majnemer（8）、lntue（5）、Kazu Hirata（5）。
一週沒動靜再禮貌 ping。

**建置設定被我改過一項**：`build/CMakeCache.txt` 的 `LLVM_BUILD_TESTS` 從 `OFF` 改成 `ON`，
否則 `ADTTests`（LLVM 自己的 unit test）沒有 target。要還原就 `cmake -DLLVM_BUILD_TESTS=OFF build`。

---

### 🔥 M1-b：`arith.scaling_extf` / `scaling_truncf` 的折疊（M1-b0 之後）

**這是重選後唯一四關全過的題目。**

**① 真實 AI pipeline —— 已查證，不是推測：**

```bash
grep -rln "ScalingExtF\|ScalingTruncF\|scaling_extf" mlir/lib/ mlir/test/Integration/
```

查到它的真實用途：

| 證據 | 內容 |
|---|---|
| 規格 | `.td` 的 description 直接引用 **OCP MXFP spec**（arxiv 2310.10537），型別是 `f4E2M1FN` / `f8E8M0FNU` |
| AMD 後端 | `mlir/lib/Conversion/ArithToAMDGPU/ArithToAMDGPU.cpp` —— 降到 MI300/MI355 的硬體指令 |
| Intel 後端 | `mlir/lib/Conversion/XeGPUToXeVM/XeGPUToXeVM.cpp`、`GPUToXeVMPipeline.cpp` |
| **會跑的整合測試** | `mlir/test/Integration/Dialect/XeGPU/WG/simple_mxfp_gemm_dequantizeB_F4.mlir` ← **真的是 MXFP GEMM 反量化** |

**白話**：這就是 LLM 低精度推論（FP4/FP8 權重）在 MLIR 裡的那個 op。
Blackwell 的 FP4、MI355 的 MXFP 走的都是這條。

**② JD 關鍵字**：`quantization`、`mixed precision`、`MXFP4/FP8`。
履歷可以寫「microscaling (MXFP4/FP8) quantization op folding in upstream MLIR」。

**③ 上游的縫隙有多大 —— 已查證：**

```bash
grep -n "ScalingExtF\|ScalingTruncF" mlir/lib/Dialect/Arith/IR/ArithOps.cpp
#   → 只有 areCastCompatible() 和 verify()，沒有 fold()、沒有 canonicalizer
grep -rn "scaling_extf\|scaling_truncf" mlir/test/Dialect/Arith/*.mlir | cut -d: -f1 | sort | uniq -c
#   → 42 行，全部在 expand-ops.mlir。canonicalize.mlir 與 constant-fold.mlir 是零
```

- 全 `arith` **唯二**沒有 folder 也沒有 canonicalizer 的 op
- **canonicalize / constant-fold 的測試覆蓋是零**

**④ 撞車查證（2026-08-08 實查）：`scaling_extf`、`scaling_truncf`、`arith MXFP`
三組關鍵字搜 open PR，全部零筆。乾淨。**

#### 動手順序（刻意分兩發，不要一次做完）

**第一發：先補測試覆蓋，不寫任何 folder。**
在 `mlir/test/Dialect/Arith/canonicalize.mlir` 加 scaling op 的案例，
CHECK 反映**現在**的行為（也就是「什麼都沒折」）。

理由有三：
1. 這是上游的 precommit test 慣例，M1-a 已經用過一次，reviewer 認得
2. 覆蓋率是零，**光補測試本身就是可以獨立 merge 的貢獻**，而且幾乎不會被拒
3. 有了 baseline，第二發的 diff 才看得出「哪些行為真的變了」

**第二發：實作 folder。以下全部是未驗證的假設，狀態＝待證。**

| 候選改寫 | 待解決的前提 |
|---|---|
| `scaling_truncf(scaling_extf(x, s), s) → x` | truncf 會捨入，round-trip 不保證回到原值。需確認成立條件（可能限於 scale 相同且不溢位） |
| scale 為常數時的 constant fold | 需確認 `f8E8M0FNU` 的常數在 MLIR 裡的表示方式、APFloat 支援度 |
| scale 對應 `2^0` 時 → 退化成 `extf` / `truncf` | 需查 `f8E8M0FNU` 的 exponent bias |
| NaN 傳播 | `.td` 明訂「if either scale or the input element is NaN, result is NaN」。常數 NaN 的折疊待驗 |

**驗證方法（沿用 M1-a 的兩份互補證據）**：
- `f4E2M1FN` 只有 **16 個值**、`f8E8M0FNU` 只有 **256 個值** → **整個輸入空間可以完全窮盡**
  （16 × 256 = 4096 組，比 M1-a 的 i8 65280 組還小）。這是這題最大的優勢：
  **不需要 SMT，直接窮盡就是完整證明。**
- 第二份證據：拿 `-arith-expand-ops` 展開後的結果當 oracle 對照
  （`ExpandOps.cpp` 的 `ScalingExtFOpConverter` 已讀過，邏輯是
  `truncf(scale)→f8E8M0FNU` → `extf` 成 `2^scale` → `mulf`）

**要先讀的檔案**：
```
mlir/include/mlir/Dialect/Arith/IR/ArithOps.td      :1447 (ScalingExtFOp) / :1632 (ScalingTruncFOp)
mlir/lib/Dialect/Arith/IR/ArithOps.cpp              :1790 / :1962
mlir/lib/Dialect/Arith/Transforms/ExpandOps.cpp     ScalingExtFOpConverter
mlir/test/Dialect/Arith/expand-ops.mlir             現有的 42 行測試
```

---

### 🟡 M1-c：`vector.extract` / `insert` 的 dynamic position canonicalization

`mlir/lib/Dialect/Vector/IR/VectorOps.cpp` **1478 / 1488 / 1617 / 1633** 四處
掛著同一句：

```cpp
// TODO: Canonicalization for dynamic position not implemented yet.
```

**四處是同一個缺口**（`ExtractFromInsertTransposeChainState` 那條鏈），
一次補掉是有份量的 patch。

- **① AI pipeline**：✅ vector extract/insert 是 vectorization 之後的產物，必經
- **② JD 關鍵字**：⚠️ **偏弱**。「vector canonicalization」不如「vectorization」有力
- **撞車**：**還沒查，動手前必查**
- **④ 證據**：vector 的 shape 讓窮盡變難，可能要靠 SMT（M4 的工作）

**判定：M1-b 做完再回來評估。** 若 M1-b 順利，可能直接跳到掃 vector 的其他 TODO（M1-d）。

---

### 🟡 M1-d：vector 的其他 TODO（138 個，尚未逐一過濾）

尚未做的事：**把 138 個 TODO 逐一過第 1 關**。

已知較有希望的方向（**都還沒查證，不要當結論**）：

| 位置 | 內容 | 為什麼可能有價值 |
|---|---|---|
| `LowerVectorGather.cpp` 114/121/131/139/147 | 五處 gather 的限制（rank > 2、strided、dynamic offset） | gather = embedding lookup / sparse 存取 |
| `LowerVectorMask.cpp:217` | `vector.mask` passthru 與 `transfer_read` | masking = 向量化迴圈的尾端處理，AI kernel 必用 |
| `LowerVectorBroadcast.cpp:129` | scalable vector 要用 `scf.for` | scalable = Arm SVE，邊緣推論 |

**掃描指令**：
```bash
grep -rn "TODO\|FIXME" mlir/lib/Dialect/Vector/ | grep -viE "remove this|once tests|deprecat"
```

---

### ⛔ `vector.contract` mixed-mode lowering —— 撞車，不做

`LowerVectorContract.cpp:907` 的 `// TODO: support mixed mode contract lowering.`

**這題四關全過**（mixed precision matmul = 量化推論的核心），**但已經有人在做**：

> **PR [#117753](https://github.com/llvm/llvm-project/pull/117753)**
> `[mlir][Vector] Support mixed mode vector.contract lowering`
> 作者 **`Groverkss`**（IREE 開發者）、open、**2024-11-26 開的，2026-03-26 還有更新**。

不是停擺的 draft，是活的 PR。

> 推論：四關全過的題目，別人也篩得出來。過濾器排除的是低價值題目，不排除競爭。
> 所以撞車查證固定放在每題最後一關（已寫進 `Goal.md` §8.7 第 5 步）。

---

## 已完成

- [x] 決定策略：upstream 為主軸 + 自建 fuzzer/verifier 當引擎（`Goal.md` §2）
- [x] 選定主場 dialect：`arith`（`Goal.md` §3）
      → **2026-08-08 改為路線制**：`arith` → `arith` 量化 op → `vector` → `linalg`/GPU
- [x] **2026-08-08 專案轉向 AI compiler 中端 codegen**，並建立 `Goal.md` §8.7 選題四關過濾器
- [x] **依過濾器重選所有後續題目** → 見上面「⭐ 題目清單」
      （M1-b 升為首選、Q1／Q2／ArithToSMT 降級、mixed-mode contract 查出撞車）
- [x] 建立 repo 與 `Goal.md`
- [x] 安裝建置依賴
- [x] clone LLVM（blobless partial clone，保留完整 commit 歷史供找 reviewer 用）
- [x] cmake 配置成功
- [x] 掃描 `arith` 產出候選 patch 清單 → `notes/arith-patch-candidates.md`
- [x] **撞車查證**：M0（AtomicRMWKind）與 M1 第一發（ceildivsi）都確認安全
- [x] **ceildivsi 深入分析** → `notes/ceildivsi-minint-analysis.md`
      （含舊 PR #90855 停擺原因、reviewer 的原話、完整的「哪些該折 / 哪些必須 bail」）
- [x] 全部遷移到 WSL 原生檔案系統（舊的 `/mnt/e/Side_Project/MLIR` 只剩一張 `MOVED.md`，
      可以直接 `rm -rf` 掉）

### 掃描時推翻的一個假設（值得記住）

`Goal.md` §8.4 原本說「找缺的 canonicalization」是主要題目來源。
**這在 `arith` 裡不成立**——54 個 op 幾乎全都有 folder，這條路早被做掉了。

真正的縫隙在**既有 folder 裡被明確標註放棄的 case**（也就是那些 TODO）。
換到別的 dialect 時，掃描方法要照這個教訓調整：先看 TODO/FIXME，再看覆蓋率。

---

## 常用指令

```bash
cd ~/llvm-project/build

ninja mlir-opt                      # 只建主要工具
ninja check-mlir                    # 建置 + 跑全部 MLIR 測試
./bin/llvm-lit -v ../mlir/test/Dialect/Arith/canonicalize.mlir   # 跑單一測試檔
./bin/mlir-opt input.mlir -canonicalize                          # 手動觀察 pass 效果
./bin/mlir-opt input.mlir --mlir-print-ir-after-all              # 看每個 pass 後的 IR

git clang-format HEAD~1             # 送 PR 前必跑

# 找某個檔案該 @ 誰 review
git log --format='%an' -- <file> | sort | uniq -c | sort -rn | head
```
