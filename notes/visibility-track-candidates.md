# 被看見線候選題目（2026-11-28 掃描）

> 第三次掃描。前兩次見 [`vector-patch-candidates.md`](vector-patch-candidates.md)（08-21）、
> [`gpu-linalg-patch-candidates.md`](gpu-linalg-patch-candidates.md)（09-05）。
> 這次的目的不同：`Goal.md` §11.5 把 `vector` 定為**被看見線**，選題條件是
> 「講得出下游是誰」，而且**優先找分析在 owner 線、使用者在 `vector`／`linalg` 的題**（一題算兩邊）。
>
> 行號對 `origin/main` = `a6321f2d`（2026-11-28）。

## ⚠️ 這份清單的查證程度（比前兩次低，動手前要補）

| 項目 | 前兩次 | 這次 |
|---|---|---|
| 行號、TODO 還在 | ✅ | ✅ 讀原始碼確認 |
| 本機 `mlir-opt` 重現 | ✅ | ❌ **沒有 build，沒有重現** |
| 撞車查證（open PR） | ✅ | ❌ **沒查**。掃描的 session 讀不到 `llvm/llvm-project` 的 PR |
| 第 1 關證據 | 實查的檔案路徑 | 題 1、3、4、5 有路徑；**題 2 沒有** |

每一題動手前：① 查 open PR（`gh pr list --repo llvm/llvm-project --search "<關鍵字>"`）；
② 在本機重現「現況」那一句；③ 重驗行號。

**排隊用，不是現在送。** 09-14 對 banach-space 的承諾還在（審中的 PR 進或關之前不開新 PR），
11-28 有九個 open PR。

## ✅ 11-28 本機審查（補上面缺的三項）

同日在本機補查：有 build（checkout base `376f04dd8bdb`）、有重現、原始碼對 `origin/main` `f496863dad20` 重驗、
open PR 用 `gh pr list --search` 與 GitHub 搜尋 API 查過。**撞車是關鍵字搜尋，0 筆不等於沒有。**
Discourse 沒查到（搜尋被限流，HTTP 429）。

| 題 | 結論 | 一句話 |
|---|---|---|
| 1 `vscale` 範圍 | 🔧 **改寫**，與 `scalable-patch-candidates.md` 的 S-2 合成一題 | 只回下界 `[1, max]` 沒有效果，要有上界；上界在 IR 上已經有載體 |
| 2 向量 op 傳範圍 | ❌ **刷掉** | 第 1 關補不出來 |
| 3 padded `linalg.pack` | ⏸ **移出這份清單** | 是 `linalg`，不在兩條線（owner＝`arith`／範圍，被看見＝`vector`）裡 |
| 4 transfer 降維支援 tensor | ✅ 維持 | TODO 還在，撞車 0 筆 |
| 5 strided gather | ❌ **刷掉** | 已有三個 open PR 在動同一塊 |

各題的細節寫在該題底下的「11-28 審查」。

---

## 🥇 1. `vector.vscale` 沒有範圍資訊（一題算兩邊）——🔧 11-28 審查後要改寫

`mlir/include/mlir/Dialect/Vector/IR/VectorOps.td:3079`

**現況**：`vscale` 的 op 文件寫它是「a positive integer value」（`:3084`），但 op 的 trait 只有
`Pure` 和 `OpAsmOpInterface`，沒有 `InferIntRangeInterface`。`IntegerRangeAnalysis` 把它當成全範圍，
也就是可能是 0。

**使用者**：scalable 的 tiling／peeling 會產生以 `vscale` 的倍數當除數的運算。

- `mlir/test/Dialect/Linalg/transform-op-peel-and-vectorize.mlir:25`：`arith.remui %C2000, %STEP`，`STEP = vscale * 8`
- `mlir/test/Dialect/Linalg/tile-to-forall-scalable.mlir:176-178`：`1024 ceildiv (vscale * 8)`（走 `affine.apply`）
- `mlir/test/Dialect/Vector/eliminate-masks.mlir:21`：`1080 mod s0`

| 關 | 證據 |
|---|---|
| ① AI pipeline | 整合測試 `Integration/Dialect/Linalg/CPU/ArmSVE/pack-unpack-scalable-inner-tile.mlir`、`ArmSVE/pack-unpack-mmt4d.mlir`、`Vector/CPU/ArmSVE/contraction.mlir` 都同時有 `vector.vscale` 和除法／取餘 |
| ② JD 關鍵字 | **SVE／RVV、scalable vectorization** |
| ⑤ 撞車 | **沒查** |

**為什麼算兩邊**：這是 owner 線 A-③（自動標「不會除以零」）的第一個真實客戶。
`arith::DivUIOp::getSpeculatability`（`ArithOps.cpp:894`）只看除數；除數是 `vscale * 8` 時，
要「`vscale ≥ 1`」＋「乘法不溢位」才推得出非零——後者正是 Discourse 第 19 則講的
「範圍窄」與「不是 poison」是兩件事。

**做法**：`VectorScaleOp` 加 `InferIntRangeInterface`，`inferResultRanges` 回 `[1, max]`；
測試加在 `mlir/test/Dialect/Vector/int-range-interface.mlir`（`vector.step` 的測試已在那裡，`:112` 起）。
估 2 個檔 ＋ 1 個測試檔。

**限制與待查**：

- IR 上只拿得到下界 1。上界（`vscaleMax`）目前是 `ScalableValueBoundsConstraintSet` 的建構參數
  （`ScalableValueBoundsConstraintSet.h:35`），走 pass 選項，不在 IR 裡。不要在這個 PR 處理。
- `vector.step` 對 scalable 型別直接 `return`（`VectorOps.cpp:8641` 起），是同一類缺口，可以當 follow-up。
- **待查**：`affine.apply` 形式的 `ceildiv` 走的是 affine 的範圍推導，`vscale` 的下界傳不傳得過去沒確認。
- **待查**：LLVM LangRef 對 `vscale` 的保證是「正整數」還是更強，寫 PR 描述前要查原文。

### 11-28 審查：只回下界沒有效果

用 `test.with_bounds` 假裝 `vscale` 有某個範圍，跑 `-int-range-optimizations`，看 `vscale * 8` 的範圍（輸入檔：[`vscale-range-probe.mlir`](vscale-range-probe.mlir)）：

| `vscale` 的範圍 | `arith.muli %vscale, %c8` | `vscale * 8` 的範圍 | 推得出非零 |
|---|---|---|---|
| 現況（沒有 interface） | — | 全範圍；`vscale` 本身也是全範圍 | 否 |
| `[1, UMAX]` | 無旗標 | 全範圍（乘法可能溢位） | 否 |
| `[1, UMAX]` | `overflow<nuw>` | `umin = 8` | 是 |
| `[1, UMAX]` | `overflow<nsw>` | 全範圍 | 否 |
| `[1, SMAX]` | `overflow<nsw>` | `[8, SMAX]` | 是 |
| `[1, 16]` | 無旗標 | `[8, 128]` | 是，`cmpi ne, 0` 折成 `true` |

對照上面引用的使用者：

- `transform-op-peel-and-vectorize.mlir` 的 `STEP` 是 `arith.muli %VSCALE, %C16 : index`，**沒有旗標** → 第二列，推不出。
- `Integration/.../ArmSVE/contraction.mlir:74-75` 是先 `arith.index_cast %vscale : index to i32` 再 `divui`；
  截斷到 `i32` 之後下界會丟（沒有上界時）→ 推不出。
- `affine.apply` 降階出來的乘法帶 `nsw`（`Affine/Utils/Utils.cpp:68-70`），所以那條路要 `vscale` 的**有號**下界也是 1 才有用（第五列）。

所以「`VectorScaleOp` 加 `InferIntRangeInterface` 回 `[1, max]`」這個做法**是對的但沒有可觀察的效果**，
上面寫的「估 2 個檔 ＋ 1 個測試檔」只涵蓋這個沒有效果的版本。要有效果需要上界。

**上界在 IR 上已經有載體**（上面「限制與待查」第一點要修正）：

- `func.func` 可以掛 `llvm.vscale_range`，`convert-func-to-llvm` 會認並轉到 `llvm.func` 的 `vscale_range`
  （`Conversion/Passes.td:526-531`、`LLVMOps.td:2155`、`LLVMAttrDefs.td:1506`）。
- 另外有 pass 選項這條路：`VectorTransforms.h:120` 的 `VscaleRange`，`eliminateVectorMasks` 在用。

所以設計問題是：**範圍分析要不要讀已經在 IR 上的 `llvm.vscale_range`**（`vector` 的 op 去讀 `llvm.` 開頭的屬性有分層問題），
不是「上界要不要放進 IR」。這就是 S-2 提的 RFC 題目，兩題合成一題。

**第 1 關的現況**：樹內沒有任何整合測試跑範圍分析（`grep -rl "int-range" mlir/test/Integration` 0 筆），
`populateIntRangeOptimizationsPatterns`／`populateIntRangeNarrowingPatterns` 在樹內除了自己的 pass 沒有呼叫者，
`getDivUISpeculatability` 只認常數除數。目前的證據是「`vscale` 出現在除法旁邊」，不是「有 pass 會用這個範圍」。
下游線索：IREE 的 Codegen 有用 `IntegerRangeAnalysis`（`TensorDynamicDimAnalysis`、`PadDynamicAlloc` 等，GitHub code search），**沒有細看**它跟 `vscale` 有沒有關係。

**撞車**：`vscale range`、`vscale InferIntRangeInterface` 的 open PR 與 issue 搜尋都是 0 筆。

---

## ~~🥈 2. 多個整數向量 op 不傳範圍（一題算兩邊，第 1 關弱）~~ ❌ 11-28 刷掉

`mlir/include/mlir/Dialect/Vector/IR/VectorOps.td`

**現況**：有 `InferIntRangeInterface` 的只有六個——`extract`（`:426`）、`broadcast`（`:750`）、
`insert`（`:946`）、`shape_cast`（`:2585`）、`transpose`（`:2923`）、`step`（`:3171`）。
會帶整數值卻沒有的：`shuffle`、`interleave`、`deinterleave`、`from_elements`、`to_elements`、
`extract_strided_slice`、`insert_strided_slice`、`scalable.insert`、`scalable.extract`、
整數的 `reduction`（min／max／and／or）。

**使用者**：`arith-int-range-narrowing` 本來就支援向量型別
（`IntRangeOptimizations.cpp:270-275`、`:331` 處理 shaped type），但範圍在上面這些 op 斷掉。
`interleave`／`deinterleave` 正是 #221185（i2 trunci）用的那組。

| 關 | 證據 |
|---|---|
| ① AI pipeline | ❌ **沒找到**樹內有 pipeline 對向量跑 narrowing。這是這題最大的洞，補不出來就降級或不做 |
| ② JD 關鍵字 | **quantization、narrow integer** |
| ⑤ 撞車 | **沒查** |

**做法**：多數是把輸入範圍原樣傳出或取聯集（`insert` 現有的寫法是 `argRanges[0].rangeUnion(argRanges[1])`，
`VectorOps.cpp:3785`）。`reduction` 要逐種 kind 想：min／max 不變、and／or 可界定、add／mul 不做。

**注意**：做成**一個有故事的 PR**（「narrowing 在哪些 op 斷掉、補上之後哪個例子能縮」），
不要拆成八個一行的——那是 `Goal.md` §11.5 明說被看見線不收的純清理，而且會再踩一次量能警告。

### 11-28 審查：第 1 關補不出來，刷掉

- 樹內：`populateIntRangeNarrowingPatterns` 除了 `arith-int-range-narrowing` 這個 pass 自己，沒有呼叫者；整合測試沒有人跑它。
- 下游：IREE 有呼叫，但在 `Dialect/Util/Transforms/OptimizeIntArithmetic.cpp`——那是 codegen 之前的 Util 層，處理的是純量與 index，沒有向量。
- 六個有 interface 的 op 與行號重驗無誤（`:426`、`:750`、`:946`、`:2585`、`:2923`、`:3171`）。

照上面自己訂的條件（「補不出來就降級或不做」）處理：不做。之後若找到對向量跑 narrowing 的 pipeline 再放回來。

---

## 🥉 3. 帶 padding 的 `linalg.pack` 分解直接放棄——⏸ 11-28 移出這份清單

`mlir/lib/Dialect/Linalg/Transforms/Transforms.cpp:1230`

**現況**：FIXME 原文「Handle this case by decomposing the padded pack instead of bailing out;
a non-unit un-tiled outer dim should be supported here.」。padding ＋ 非單位 un-tiled outer dim
時 `notifyMatchFailure`。09-05 掃描的 L-2（當時在 `:1175`），FIXME 還在。

- ① 09-05 記錄的負向測試 `decompose-pack.mlir:365`（這次沒重驗行號）
- ② **tensor layout、tiling**
- ⑤ **沒查**。FIXME 是 #218141（prometheusfma-llvm）留的，**動手前先 @ 作者**

屬於 `linalg`，是路線圖的 M5（`Goal.md` §3.1），不是 `vector`。中等設計風險：
padded pack 的 `tensor.pad` high pad 怎麼算。09-05 估 40～60 行。

### 11-28 審查

- FIXME 還在 `Transforms.cpp:1230-1231`；`git blame` 確認是 `ede2b5fe3ce6`（#218141，prometheusfma-llvm，2026-08-25）。
- 撞車：`linalg.pack decompose padding` 的 open PR 搜尋 0 筆。
- **不在兩條線內**：`Goal.md` §11.5 的 owner 線是 `arith`＋範圍／poison，被看見線是 `vector`；這題是 `linalg`，兩邊都不算，
  也不符合 11-24 Federico 在 #245596 建議的「集中在一個子集」。題目本身沒問題，留在 09-05 那份清單（L-2）即可。
  要做它，先在 `Goal.md` 明講被看見線包含 `linalg`。

---

## 4. `transfer_read/write` 的降維不支援 tensor

`mlir/lib/Dialect/Vector/Transforms/VectorTransferOpTransforms.cpp:485`、`:609`

**現況**：兩個 pattern `dyn_cast<MemRefType>` 失敗就放棄（`// TODO: support tensor types.`）。
08-21 掃描的第 4 名，TODO 還在（當時 `:485`、`:605`）。

- ① `Integration/Dialect/Linalg/CPU/ArmSME/pack-unpack-mmt4d.mlir` 等（08-21 的證據，沒重驗）
- ② **vectorization**（＋ tensor layout）
- ⑤ **沒查**

**這題的性質**：「rank reduction 該不該在 bufferization 之前發生在 tensor 上」是設計問題，
預期有 review 辯論。**被看見的效果最強，但不會快**。想要一題大的時候再做。

### 11-28 審查

兩個 TODO 還在（`:485`、`:609`）。撞車：`transfer_read rank reduc tensor` 的 open PR 搜尋 0 筆。結論不變。

---

## ~~5. strided gather 的改寫限制太多~~ ❌ 11-28 刷掉

`mlir/lib/Dialect/Vector/Transforms/LowerVectorGather.cpp:114`、`:121`、`:131`、`:139`、`:147`

**現況**：五個 TODO 都還在（rank > 2、多維 stride、動態 offset 等）。08-21 掃描的第 5 名。

- ① `XeGPUVectorLinearize.cpp` 呼叫它；整合測試 `CPU/gather.mlir`（08-21 的證據，沒重驗）
- ② GPU codegen（經 XeGPU）——**五題裡關鍵字最弱**
- ⑤ **沒查**；08-21 時周邊 XeGPU 很擠

### 11-28 審查：已有人在做，刷掉

五個 TODO 還在（`:114`、`:121`、`:131`、`:139`、`:147`），但同一塊有三個 open PR：

| PR | 內容 | 作者 | 最後更新 |
|---|---|---|---|
| #189178 | Remove unit-stride check in `Gather1DToConditionalLoads` | jtuyls | 2026-04-07 |
| #194395 | Make gather/scatter index dimensions separately | krzysz00 | 2026-05-11 |
| #241601 | Do not fold contiguous gather/scatter on non-unit strides | aeft | 2026-11-26 |

另有 #181357（banach-space，釐清 gather/scatter 索引語意）、#132227（Groverkss，多維 scatter）。
語意本身還在被改，關鍵字又是五題裡最弱的，不做。#241601 可以當 review 的對象。

---

## ⛔ 不要碰

- **mixed-mode `vector.contract`**（`LowerVectorContract.cpp:918`，TODO 還在）：
  08-21 時被 #117753 佔著，現況沒查。要做就去那個 PR 留言，不開競爭 PR。

---

## 建議順序

~~1 → （2 或 3 擇一）→ 4。~~

**11-28 審查後**：這份清單剩 1（改寫後與 S-2 合併）與 4。

- **1 不再是小題**：要連上界一起處理，而且得先回答「分析讀不讀 `llvm.vscale_range`」。它現在是 owner 線的設計題，
  適合先在 Discourse 問，不是直接開 PR。動手前先把第 1 關補實：找出一條真的會用到這個範圍的 pass 或下游。
- **4 留到想要一題大的**。
- 2、5 刷掉；3 移回 09-05 的清單。
- scalable 那份清單多了一題小的、可以獨立送的：`rewrite_narrow_types` 遇到 scalable 向量 assert 失敗（S-1a）。
- 以上全部受 09-14 的承諾限制，現在都不能開。可以先做的是 review：
  #244284（scalable `transfer_read`／`transfer_write` 的 unrolling，Vaisman，11-25；可以用 qemu 環境實跑）、
  #208873（Guard transfer read narrow type emulation，qyingwu，11-27；與 #221185 同一個檔）。

<details>
<summary>審查前的順序與理由（留底）</summary>

- **先做 1**：小、兩條線都算、SVE 關鍵字，而且讓 A-③ 不再是沒有使用者的基礎建設。
- **2 要先補第 1 關**，補不出來就換 3。
- **4 留到想要一題大的**。5 放最後。

</details>

## 順便看到的（沒過濾，留給下次掃描）

`grep -i scalab` 在 `Vector/`、`Linalg/Transforms/Vectorization.cpp`、`Conversion/VectorTo*` 找到約 20 處
「scalable vectors are not supported」，例如 `LowerVectorBroadcast.cpp:128`（08-21 已因第 2 關刷掉）、
`VectorToSCF.cpp:339`／`:736`、`LowerVectorScan.cpp:129`、`VectorTransforms.cpp:954`／`:1280`／`:1350`／`:1557`、
`Vectorization.cpp:1600`／`:3913`。SVE／RVV 是被看見線關鍵字最強的方向，值得專門掃一次並逐條過四關。

> ✅ **同日已掃**：[`scalable-patch-candidates.md`](scalable-patch-candidates.md)。82 行裡過關的只有三題。
