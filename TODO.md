# TODO / 現況快照

> **這份文件的用途**：接續工作用的交接文件。
> 換一個 session、換一台機器、或隔了一個月回來，讀這份就能接上，不必翻聊天紀錄。
>
> 分工：
> - **`Goal.md`** = 為什麼這樣做（策略、決策、MLIR 背景知識、貢獻 SOP）——**改動頻率低**
> - **`TODO.md`**（本檔） = 現在在哪、下一步做什麼、有什麼還沒確認——**每次有進展就更新**
>
> 新 session 開場建議直接說：「讀 Goal.md 和 TODO.md，然後接續」。

最後更新：2026-08-12

---

## 一句話現況

**🎉 M0 里程碑達成。第三個 commit 進去了，`arith` 的 `ceildivsi` MININT 折疊。**
**六個 PR：3 merged、3 open。**
**#215696（`kuhar`）三點都改完、已 push；#215318（`banach-space`）球在 reviewer 那邊。**

| PR | 內容 | 狀態（2026-08-12 實查） | CI |
|---|---|---|---|
| [#214622](https://github.com/llvm/llvm-project/pull/214622) | M0：`AtomicRMWKind` switch 窮盡（NFC） | ✅ **已 MERGE**（2026-08-09 15:03，merge commit `78e17e70bd52`） | — |
| [#214919](https://github.com/llvm/llvm-project/pull/214919) | M1-b0：`f8E8M0FNU` NaN 被折成 Inf | ✅ **已 MERGE**（2026-08-10 11:09 UTC，merge commit `794aa0fd923a`） | 全綠 |
| [#214637](https://github.com/llvm/llvm-project/pull/214637) | M1-a：`ceildivsi` MININT 折疊 | ✅ **已 MERGE**（2026-08-12 13:39 UTC，`kuhar` 代 merge，squash commit `2a0c335d4538`） | 全綠 |
| [#215123](https://github.com/llvm/llvm-project/pull/215123) | M1-b：`scaling_extf`/`scaling_truncf` 常數折疊 | 衝突已解（rebase，head `6319069bfd7b`），`mergeable=true`。描述已同步。**零 review，開了 3 天** | **全綠**（Linux / Windows / AArch64 / code_formatter / LLVM_ABI） |
| [#215318](https://github.com/llvm/llvm-project/pull/215318) | M1-d：transfer permutation lowering 支援 masked op | `banach-space` 2026-08-11 18:27 review 三點，已全部回覆並 push（head `d0170cd77b5c`）。**球在 reviewer 那邊** | 全綠 |
| [#215696](https://github.com/llvm/llvm-project/pull/215696) | 從 #214637 拆出：`index`／inference 的 `ceildivs` INT_MIN 一致性 | **`kuhar` 2026-08-12 13:35 review 三點**（inline，COMMENTED）。三點都改完，amend 進第一個 commit 後 force-push，head `21ffbbcf9bc2`。**回覆草稿寫好但尚未送出** | 待跑 |

### 🔥 2026-08-12：#214637 merge，同一分鐘 #215696 收到 review

`kuhar` 13:35 UTC 在 #215696 留三個 inline comment，13:39 UTC 把 #214637 merge 掉。
三點都已處理，amend 進第一個 commit（stack 維持三個 commit），
新 head `21ffbbcf9bc2`，`ninja check-mlir` 3848 passed / 0 failed，
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

- [ ] **🔥 #215696 的回覆還沒送出** — 三點都已改完並 force-push（head `21ffbbcf9bc2`），
      草稿在 `patches/index-ceildivs-intmin-review-reply.md`，三個 comment id：
      `3766876868`（`IndexOps.cpp`）、`3766876874`（canonicalize 測試）、
      `3766876880`（index-to-llvm 測試）。**送出前先確認 (a) 那個刻意偏離要不要保留。**

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

- [ ] **等 review** — 只剩 #215123 是真的零 review（開了 3 天，全綠、mergeable）。
      **可以考慮 ping。** #215318 已回覆完，球在 `banach-space`；
      #215696 已改完 push，剩回覆要送。

- [ ] **等兩個 issue 的方向** — #215295（scale 語意，兩位 maintainer 對怎麼修沒共識，
      我的回覆送出後尚無新回應）、#215445（`APFloat::convert` 不回報 sign／zero 失真，含 crash，
      **triager 已上標 `llvm:support` / `mlir:arith`**，零回應）。
      詳見上面「線 A」與「線 A′」。**方向確定才動手，不要替 maintainer 選邊。**

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
