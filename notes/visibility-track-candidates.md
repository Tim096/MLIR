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

---

## 🥇 1. `vector.vscale` 沒有範圍資訊（一題算兩邊）

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

---

## 🥈 2. 多個整數向量 op 不傳範圍（一題算兩邊，第 1 關弱）

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

---

## 🥉 3. 帶 padding 的 `linalg.pack` 分解直接放棄

`mlir/lib/Dialect/Linalg/Transforms/Transforms.cpp:1230`

**現況**：FIXME 原文「Handle this case by decomposing the padded pack instead of bailing out;
a non-unit un-tiled outer dim should be supported here.」。padding ＋ 非單位 un-tiled outer dim
時 `notifyMatchFailure`。09-05 掃描的 L-2（當時在 `:1175`），FIXME 還在。

- ① 09-05 記錄的負向測試 `decompose-pack.mlir:365`（這次沒重驗行號）
- ② **tensor layout、tiling**
- ⑤ **沒查**。FIXME 是 #218141（prometheusfma-llvm）留的，**動手前先 @ 作者**

屬於 `linalg`，是路線圖的 M5（`Goal.md` §3.1），不是 `vector`。中等設計風險：
padded pack 的 `tensor.pad` high pad 怎麼算。09-05 估 40～60 行。

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

---

## 5. strided gather 的改寫限制太多

`mlir/lib/Dialect/Vector/Transforms/LowerVectorGather.cpp:114`、`:121`、`:131`、`:139`、`:147`

**現況**：五個 TODO 都還在（rank > 2、多維 stride、動態 offset 等）。08-21 掃描的第 5 名。

- ① `XeGPUVectorLinearize.cpp` 呼叫它；整合測試 `CPU/gather.mlir`（08-21 的證據，沒重驗）
- ② GPU codegen（經 XeGPU）——**五題裡關鍵字最弱**
- ⑤ **沒查**；08-21 時周邊 XeGPU 很擠

---

## ⛔ 不要碰

- **mixed-mode `vector.contract`**（`LowerVectorContract.cpp:918`，TODO 還在）：
  08-21 時被 #117753 佔著，現況沒查。要做就去那個 PR 留言，不開競爭 PR。

---

## 建議順序

1 → （2 或 3 擇一）→ 4。

- **先做 1**：小、兩條線都算、SVE 關鍵字，而且讓 A-③ 不再是沒有使用者的基礎建設。
- **2 要先補第 1 關**，補不出來就換 3。
- **4 留到想要一題大的**。5 放最後。

## 順便看到的（沒過濾，留給下次掃描）

`grep -i scalab` 在 `Vector/`、`Linalg/Transforms/Vectorization.cpp`、`Conversion/VectorTo*` 找到約 20 處
「scalable vectors are not supported」，例如 `LowerVectorBroadcast.cpp:128`（08-21 已因第 2 關刷掉）、
`VectorToSCF.cpp:339`／`:736`、`LowerVectorScan.cpp:129`、`VectorTransforms.cpp:954`／`:1280`／`:1350`／`:1557`、
`Vectorization.cpp:1600`／`:3913`。SVE／RVV 是被看見線關鍵字最強的方向，值得專門掃一次並逐條過四關。

> ✅ **同日已掃**：[`scalable-patch-candidates.md`](scalable-patch-candidates.md)。82 行裡過關的只有三題。
