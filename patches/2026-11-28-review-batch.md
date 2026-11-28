# Review 草稿一批：#235349、#227199、#236005

狀態：#235199 於 2026-11-28 已貼（COMMENT，pullrequestreview-6096700565）。#235349（pullrequestreview-6096723465）、#227199（6096723586）、#236005（6096723679）也於 2026-11-28 已貼，都是 COMMENT；貼之前確認三個 head 與驗的相同、沒有新留言。

本機分支 `review/batch-1128`（`376f04dd8bdb`＋三個 PR 的 diff，一次 build）。
lit：`mlir/test/Dialect/Arith`＋`mlir/test/Analysis/DataFlow` 44 個全過。
驗的 head：#235349 `c1a70eb565`、#227199 `304ab97f95`、#236005 `d66036a06a`。基底是本機 11-16 的 main，不是各 PR 自己的基底。
測試輸入在 `scratchpad/b1128/`（`u1`～`u8.mlir`、`ic.mlir`、`rc.mlir`、`recomp.py`）。

沒選的：#233234（kuhar 要作者先上 Discourse 發 RFC，卡在那裡）。

---

## #235349 `[mlir][arith] Fix crash in SameInputOutputTensorDims with unranked tensors`（viniciusfdasilva，10-24 開，+2/−1，零 review）

白話：arith 的 cast 類 op 會檢查「輸入和輸出的 tensor 形狀一樣」。檢查時直接讀形狀，但 unranked tensor（`tensor<*xf32>`）沒有形狀可讀，所以 assert。PR 加一個「有 rank 才讀」的判斷。修 issue #234633。

這就是 11-26 我自己撞到的那個 `uitofp` assertion：已經有 issue、也有這個 PR，不用另開題目。origin/main 上 `ArithOps.td` 這段還是舊的（11-28 查）。

查證：
- issue 的重現（`truncf tensor<*xf64> to tensor<*xf32>`）不再 assert。
- 用同一個 trait 的其他 op 在 unranked 上也不 assert：`uitofp`、`extsi`、`index_cast`、`bitcast`、`scaling_extf`。`--canonicalize`、`--arith-expand`、`--arith-int-range-narrowing` 跑過不 crash；`trunci(extsi(x))` 在 unranked 上照常折成 `x`。
- unranked → unranked 現在是**被接受**，不是報錯。unranked 與 ranked 混用仍報錯：`tensor<*xf64>` → `tensor<f32>`（`must have the same shape and base type`）、→ `tensor<4xf32>`（`same tensor dimensions`）。
- PR 描述寫「emits a regular error message instead of crashing」，跟上一點不符。
- PR 沒有測試。

貼出的內容（COMMENT）：

I ran this locally. The reproducer from #234633 no longer asserts, and the other ops with this trait (`uitofp`, `extsi`, `index_cast`, `bitcast`, `scaling_extf`) are fine on unranked tensors too, also under `--canonicalize`.

Two notes. The patch has no test; the case from the issue would fit in `mlir/test/Dialect/Arith/ops.mlir`. And the description says the verifier emits an error, but unranked to unranked is accepted now:

```mlir
%r = arith.truncf %t : tensor<*xf64> to tensor<*xf32>
```

That matches the other arith ops, which take unranked tensors as well, so the description could say that. Mixing unranked and ranked (`tensor<*xf64>` to `tensor<f32>` or `tensor<4xf32>`) is still rejected with a regular error.

---

## #227199 `[mlir][arith] Support hybrid optimization for indexcast indexcastui chains`（pranavalavandi，09-29 開，+39/−9，零 review，09-30 ping 過 kuhar）

白話：`i8` 轉成 `index` 再轉回 `i8`，值不變，可以整段拿掉。原本只認「兩次都是有號」或「兩次都是無號」，PR 讓「一次有號一次無號」的兩種混搭也認。修 issue #224927。

為什麼對：往寬的轉不管補 0 還是補符號，低 8 個 bit 都是原值；轉回來只取低 8 個 bit。

查證（`--arith-int-range-narrowing='int-bitwidths-supported=8'`）：
- 四種組合都折成 `%arg0`。
- 內層帶 `nneg` 的 `index_castui` 也折（`nneg` 違反時原本是 poison，換成 `x` 是 refinement）。
- 外層型別不同（`i8` → `index` → `i16`）不折；vector 不折。兩者跟原本一樣。
- origin/main 上還是舊的單一 template 參數版本（11-28 查），沒有別的 PR 在修。
- 註解與 `template` 之間多了一個空行，doc comment 會跟 struct 分開。

貼出的內容（COMMENT）：

I ran this locally and the tests pass. With `int-bitwidths-supported=8` all four combinations fold, also when the inner `index_castui` has `nneg`. A different outer width and vectors are left alone, as before. LGTM.

Nit: the blank line between the doc comment and `template` detaches the comment from the struct.

---

## #236005 `[mlir][arith] Fold signed quotient and remainder recomposition`（meinie0826，10-27 開，+236/−0，只有 Copilot bot 的空 review，10-29 ping 過 kuhar，描述註明用了 AI 工具）

白話：`(x / d) * d + x % d` 就是 `x`。PR 在 `addi` 的 fold 裡認出這個形狀，直接回傳 `x`。

查證：
- 等式（`recomp.py`，寬度 1～8，跳過 `d == 0` 與 `INT_MIN / -1` 這兩種本來就是 UB 的輸入）：86,862 組有定義的輸入，和都等於被除數，零反例。
- flag：`muli` 或 `addi` 的 `nsw` 在這些輸入上永遠不會溢位（0 組）。`muli nuw`（27,037 組）、`addi nuw`（19,848 組）、`divsi exact`（81,944 組）會是 poison；fold 把 poison 換成 `x`，是 refinement。
- 除數是常數時也折；兩個相同值的常數（canonicalize 會合併）也折。
- **無號版沒折**：`divui`＋`muli`＋`remui`＋`addi` 留著。同一條等式在無號下也成立。
- `subi(x, muli(divsi(x, d), d))`（等於 `remsi`）不在這個 PR 範圍，沒折。`floordivsi` 搭 `remsi` 不折，這是對的（兩者捨入方向不同）。

貼出的內容（COMMENT）：

I ran this locally and the tests pass. I checked the identity separately for widths 1 to 8: on every defined pair the sum equals the dividend, `nsw` on the `muli` or the `addi` never overflows, and `nuw` or `exact` can give poison, which the fold only refines. LGTM.

The unsigned form has the same identity and is not folded:

```mlir
func.func @unsigned(%x: i32, %d: i32) -> i32 {
  %q = arith.divui %x, %d : i32
  %m = arith.muli %q, %d : i32
  %r = arith.remui %x, %d : i32
  %s = arith.addi %m, %r : i32
  return %s : i32
}
```

You may want to cover it here or in a follow-up.

---

# 依「跟自己相關」重排（2026-11-28，他說相關的才是比較好的範圍）

| 相關程度 | PR | 跟我們哪裡相關 | 狀態 |
|---|---|---|---|
| 直接重疊 | #235199（matthias-springer） | 跟自己的 #215696 修同一件事、改同四個檔 | 已貼 |
| 同一個檔 | #230976（SomnusGG）、#245151（yifeihe07） | 都改 `ExpandOps.cpp`，跟自己的 #217892 同檔；窄浮點格式跟 #221386、#230086 同題 | 還沒驗 |
| 主線 A（poison） | #240708（frederikgramkortegaard）、#242700（draft） | `ub.poison`／`ub.assume` | #240708 matthias-springer 已在審；#242700 只讀過 |
| 副線 B（範圍分析） | #227199 | `int-range-narrowing` | 已貼 |
| 自己撞到的 bug | #235349 | 11-26 的 `uitofp` assertion | 已貼 |
| 只是同 dialect | #236005 | arith 的 fold，跟自己的 PR 沒有交集 | 已貼 |

## #235199 `[mlir] Fix signed ceiling division of INT_MIN`（matthias-springer，10-24 開，+149/−128，零 review，開了之後沒有任何動作，標 `Assisted-by: Codex`）

白話：`index.ceildivs`（有號、往上取整的除法）遇到 `INT_MIN` 會算錯正負號，因為舊寫法要先取 `-n`，而 `-INT_MIN` 放不下。PR 改成先做一般除法，除不盡且兩邊同號時再加一。

**跟 #215696 的關係**（自己的，08-11 開，kuhar 08-14 approve，沒 merge）：
- IndexToLLVM、IndexToSPIRV 兩邊的新公式相同：`q = n / m`，`q * m != n` 且同號時取 `q + 1`。
- 兩邊都拿掉 `InferIntRangeCommon.cpp` 裡 `INT_MIN` 的 workaround。
- 不同處：#235199 的折疊改用 `APIntOps::RoundingSDiv`；#215696 另外改了 `Affine/Utils/Utils.cpp` 的 ceildiv 展開，並有 unittest。
- 兩個 PR 互相沒有提到對方。issue #235168（10-24，fuzzer）有連到 #215696。

查證（本機分支 `review/pr-235199`，`376f04dd8bdb`＋PR diff；`scratchpad/b1128/cd.py`）：
- 套用時 `InferIntRangeCommon.cpp` **衝突**：#238124（11-03 進 main）在同一段加了程式碼，PR 的基底比它舊。照 PR 的意思解掉（整段換成一行 `return`）後才 build 得起來。
- 14 個邊界值（`INT_MIN`、`INT_MIN+1`、`INT_MIN+2`、±1、±2、±3、±7、0、`INT_MAX-1`、`INT_MAX`）兩兩配對，去掉除以 0 與 `INT_MIN / -1`，共 181 組：
  - 常數折疊：103 組折了，全對；78 組沒折（index 的折疊要 32／64 bit 結果一致才折）。
  - lowering 後用 `mlir-runner` 實跑：181 組全對。
- lit：`Dialect/Index`、`Conversion/IndexToLLVM`、`Conversion/IndexToSPIRV`、`int-range-interface.mlir`、`mlir/test/Interfaces` 共 32 個全過（衝突是照 PR 解的）。
- **沒驗到**：範圍推論我自己寫的輸入語法錯了沒跑成，只有 PR 自帶的 lit；SPIR-V 沒有實跑。

貼出的內容（2026-11-28 已貼，COMMENT；貼之前確認 head 仍是 `892f962d18`、沒有新留言）：

This overlaps with #215696, which has been open since August: the same formula in the LLVM and SPIR-V lowerings and the same removal of the range-inference workaround. #215696 also changes the affine `ceildiv` expansion.

I ran this one locally. On 181 pairs of edge values (around `INT_MIN`, 0 and `INT_MAX`) the folder and the executed LLVM lowering both give the mathematical result. It conflicts with main in `InferIntRangeCommon.cpp` since #238124.

Which of the two would you like to keep? I am fine either way and can rebase #215696 or close it.
