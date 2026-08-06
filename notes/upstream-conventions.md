# LLVM/MLIR 社群怎麼運作 — 實地調查

最後更新：2026-08-07
方法：讀 `~/llvm-explore` 的官方文件 + 統計近期真實 merged PR + 讀真實 review 往來。
**不是二手教學，是從上游本體與 GitHub API 直接取得的。**

---

## 0. 🔴 最重要：`llvm/docs/AIToolPolicy.md`

上游有**正式的 AI 工具使用政策**（193 行）。我們整個專案的做法都受它規範，
所以放在第一節。**動任何東西之前先讀懂這節。**

### 政策允許什麼

> 「contributors can use whatever tools they would like to craft their
> contributions, but there must be a **human in the loop**.」

工具本身**不禁止**。但有幾條硬性條件：

| 要求 | 原文重點 | 對我們的意思 |
|---|---|---|
| **人必須先看過** | 「Contributors must read and review all LLM-generated code or text before they ask other project members to review it」 | 送出前你要自己讀過每一行 |
| **你是作者、你負全責** | 「The contributor is always the author and is fully accountable」 | 不能說「這是 AI 寫的」來卸責 |
| **要能回答 review 的提問** | 「able to answer questions about their work during review」 | ⚠️ **這條最關鍵**，見下 |
| **要標示** | 「be transparent and label contributions that contain substantial amounts of tool-generated content」 | 用 commit trailer |
| **新手從小做起** | 「start with small contributions that they can fully understand」 | 正好就是 M0 的定位 |

### ⚠️ 「要能回答提問」這條，決定了我們的工作方式

> 「Passing maintainer feedback to an LLM doesn't help anyone grow,
> and does not sustain our community.」

意思是：reviewer 問問題時，**不能把問題丟回來給 AI 再貼答案**。
你必須真的懂到能當場回答。

**這正是我們寫 `notes/` 的意義**——不是文件潔癖，是讓你在 review 時
能自己講清楚「為什麼這樣改」。送 PR 前，先自問：
**「如果 reviewer 問我為什麼選這個做法，我能不看筆記講出來嗎？」**
答不出來就還不能送。

### 標示方式

政策建議的 trailer：

```
Assisted-by: <name of code assistant>
```

⚠️ **不要用 `Co-Authored-By:`**——那等於宣稱 AI 是共同作者，
跟「contributor is always the author」直接衝突。

> **已修正**：M0 的 commit 原本寫 `Co-Authored-By: Claude Opus 5`，
> 2026-08-07 已 amend 成 `Assisted-by: Claude Code (Claude Opus 5)`。
> （本 repo 自己的 commit 不受此限，那不是上游貢獻。）

### 政策也管 PR 留言與 RFC

適用範圍明列：code、RFC / 設計提案、issue、**「Comments and feedback on pull requests」**。

⚠️ 所以我們原本想在 PR #131484 留的那則意見，**同樣受這條規範**。
而且政策**強烈建議 PR 描述由你自己寫**：

> 「it is strongly recommended that contributors write PR descriptions themselves
> (if needed, using tools for translation or copy-editing)」

實務做法：技術分析可以由工具整理（像 `notes/` 那些），
但**送出去的文字你要自己組織過**，至少是自己重寫一遍。

### 明文禁止

- **禁止用 AI 工具處理 `good first issue`**：「**Using AI tools to fix issues
  labelled as "good first issues" is forbidden**」。
  （`Goal.md` §8.4 本來就說別搶這類 issue，現在多了一條硬禁令。）
- 禁止未經人類核准就在專案空間行動的 agent
- 禁止未經人類 review 就自動發言的審查工具

### 「Extractive contribution」這個概念要記住

> **golden rule**：「a contribution should be worth more to the project than
> the time it takes to review it」

不合格的 PR 會被貼 `extractive` 標籤，維護者甚至有一段制式回覆可以直接貼。
**降低「extractive」的方法是：縮小規模、降低複雜度，或提高實際價值。**
這解釋了為什麼 M0 要挑最小的題目——小而正確的 patch 不會浪費別人時間。

### 政策舉的正面例子

> 「[This PR] contains a **proof from Alive2**, which is a strong signal of
> value and correctness.」

**上游官方點名 Alive2 證明是「價值與正確性的強訊號」。**
這等於直接背書了 `Goal.md` §5 M4 的方向——形式化證明不只是我們自己覺得酷，
是社群明文認可的品質訊號。

---

## 1. 另一條硬性要求：GitHub email 必須公開

`llvm/docs/DeveloperPolicy.md`：

> 「the LLVM community requires contributors to have a public email address
> associated with their GitHub commits, so please ensure that
> **"Keep my email addresses private" is disabled**」

理由是 buildbot 要用 email 通知建置失敗。

🔴 **實測：`Tim096` 目前沒有公開 email，不符合這條。**
送第一個 PR 前要去 https://github.com/settings/emails 關掉隱私設定。
（不想曝光真實信箱的話，文件說可以用轉寄服務。）

---

## 2. Commit / PR 的格式慣例

### 標題

從近 30 個 arith 相關 commit 統計：

```
[mlir][arith] Fold trivial shifts (`0<<x`, `x>>x`, `-1>>x`)
[MLIR][Arith] Fix BitcastOp fold crashing on unhandled constant attributes
[mlir][arith][NFC] ...
```

- 格式 `[專案][dialect] 祈使句`，**動詞開頭**（Fold / Fix / Add / Reject / Canonicalize）
- 大小寫**兩種都有**，`[mlir][arith]` 小寫較近期也較多，跟著用
- 結尾的 `(#212159)` 是 GitHub squash-merge 自動加的，**自己不要打**
- 純重構加 `[NFC]`

### 描述／commit body

**不是一句話交代。** 真實的 body 都相當紮實，共同結構是：

1. **問題具體是什麼**——講到可重現的程度（哪個 op、哪種輸入、怎麼壞的）
2. **為什麼這個修法是對的**
3. **刻意不做什麼、為什麼**（常見：「folding to poison 會讓 arith 相依 ub dialect，先不做」）
4. **證據**——godbolt 連結、**Alive2 證明表格**

範例（#212159，`victor-eds`）直接在描述裡放了一張表，
每一條 fold 都附一個 Alive2 連結打勾。**這就是上面政策說的「strong signal」。**

---

## 3. Review 文化（讀真實往來得到的）

取樣 PR #212483（8 則 review 意見、改了 6 版）：

- **`nit:` 前綴**代表「小建議，不是擋你」
- **可以有禮貌地反駁，而且會被接受**。實例：reviewer 建議改測試函式命名，
  作者回「Camelcase matches the naming of the other tests in this file though.
  I would suggest to keep it as is」——就這樣定案了。
  **不必照單全收，講得出理由就好。**
- **多位 reviewer 會各自進來**（該 PR 有 gysit、krzysz00、xlauko 三人）
- 常見要求：測試放到更精準的位置、避免未初始化變數、考慮用 `TypeSwitch`
- reviewer 會用 GitHub 的 ` ```suggestion ` 區塊直接給改法

### 合併速度（別被嚇到也別誤判）

| PR | 開→合 | review 意見 |
|---|---|---|
| #212159（熟面孔）| **當天** | 0 |
| #212072（熟面孔）| 1 天 | 0 |
| #212483（較新的人）| 6 天 | 8 則、改 6 版 |

熟面孔幾乎不用 review 就進去了；**新人會被實質審查，這是正常的，不是針對你。**

---

## 4. 測試的規矩

### `llvm/docs/InstCombineContributorGuide.md` — 最貼近我們主場的官方指南

那是 LLVM IR 端寫 fold 的指南。**規則不能無條件套用到 MLIR**
（MLIR 沒有 `update_test_checks.py`，用的是 `mlir/utils/generate-test-checks.py`），
但**原則是共通的**，而且帶 LLVM 背景的 reviewer 會用這套標準看你：

- **Precommit tests**：先送一個 commit 只加測試、CHECK 反映**改動前**的行為；
  第二個 commit 才是功能改動 + CHECK 的 diff。
  > 「If the second commit in your PR does not contain test diffs, you did
  > something wrong.」
  ⚠️ 例外：修 assertion failure / 無窮迴圈時**不要** precommit。

  👉 **這對 M1 的 ceildivsi 剛好完美**——既有測試
  `@simple_arith.ceildivsi_overflow` 本來就在斷言「不折疊」，
  等於 baseline 已經在上游了，我們的 patch 天然就是「CHECK 的 diff」。

- **Negative tests**：一定要測「不該套用」的情況，而且要做到
  **每個測試剛好只違反一個前提**。
  👉 對應我們的 `MININT / -1` 與 `b == 0`。

- **Alive2 證明**：「Your pull request description **should** contain one or
  more alive2 proofs」。用泛化的變數，不要只證特定常數。

- **Real-world usefulness**：
  > 「Transforms that do not have real-world usefulness provide *negative* value」

  ⚠️ 特別點名：「fixes for **fuzzer-generated missed optimization reports**
  will likely be rejected if there is no evidence of real-world usefulness」。
  👉 **這條直接影響 M2/M3 的 fuzzer 策略**——fuzzer 找到的「漏最佳化」
  不能直接送 PR，要先論證真實世界用得到。**crash 不受此限**（crash 一定要修）。

---

## 5. 🔴 M4 的前提要修正：上游已經有 Alive2 的橋

`mlir/utils/verify-canon/verify_canon.py`（2024-05-13，Ivan Butygin，#91867）

做的事：抽出指定的 func → 跑 `-canonicalize` → 原始版與 canonical 版**都 lower 到 LLVM IR**
→ 分別加上 `src_` / `tgt_` 前綴後合併輸出，**讓你複製貼到 Alive2 網頁**。

**所以「MLIR 這邊什麼都沒有」是不對的。** 但差距依然很大：

| | `verify_canon.py` | M4 想做的 |
|---|---|---|
| 規模 | 90 行 helper | 真正的工具 |
| 操作 | **人工複製貼上到網頁** | 自動化、批次 |
| 範圍 | 只能處理 lower 得到 LLVM IR 的東西 | 直接在 MLIR 層驗證 |
| 輸入 | 你自己手寫 | fuzzer 產生 |
| 用途 | 一次驗一個 | 迴歸、CI |
| 現況 | **樹裡沒有任何東西用它**，無 CI 無測試 | — |

👉 **Ivan Butygin 同時是 `ArithOps.cpp` 的第二大作者（7 commits）與這支腳本的作者。**
M1 和 M4 都該找他。

---

## 6. 送 PR 前的檢查清單（依本次調查整理）

- [ ] GitHub 設定關掉 "Keep my email addresses private"（§1，**還沒做**）
- [ ] 標題 `[mlir][arith] 動詞開頭...`，純重構加 `[NFC]`，不要自己打 `(#NNNN)`
- [ ] 描述**自己寫過**，涵蓋：問題、為何正確、刻意不做什麼、證據
- [ ] 有 Alive2 證明就放進描述（政策明文認可的強訊號）
- [ ] Negative test：每個剛好只違反一個前提
- [ ] 動到既有測試就主動點名，不要讓 reviewer 自己發現
- [ ] `Assisted-by:` trailer（**不是** `Co-Authored-By:`）
- [ ] `git clang-format HEAD~1` 乾淨
- [ ] `ninja check-mlir` 全綠
- [ ] **自問：reviewer 問起來，我能不看筆記自己回答嗎？**
