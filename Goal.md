# MLIR 專案總綱 (Goal.md)

> **這份文件是什麼**：專案的**長期真實來源**——目標宣言、決策紀錄、MLIR 入門教材、貢獻 SOP。
> 講的是**為什麼**，不是「現在做到哪」。
>
> **與 `TODO.md` 的分工**（重要，別讓兩邊漂移）：
>
> | | `Goal.md`（本檔） | `TODO.md` |
> |---|---|---|
> | 內容 | 為什麼這樣做、背景知識、SOP | 現在在哪、下一步、未解問題 |
> | 改動頻率 | 低（決策變了才改） | 高（每次有進展就改） |
>
> **怎麼用**：
> - 今天要動手 → **直接看 `TODO.md`**，不用讀這份
> - 隔了兩週回來忘記在幹嘛 → 讀 §1，然後看 `TODO.md`
> - 想知道「為什麼是這樣做，不是那樣做」 → 讀 §2（含被否決的方案與理由）
> - 完全不懂 MLIR 的人要接手 → 從 §6 開始讀
> - 忘記某個指令 → §9
>
> **維護規則**：進度更新寫在 `TODO.md`，不要寫在這裡。
> 決策改變時，**不要刪掉舊決策**——在 §2.4 追加一筆並註明日期與理由。
> 未來的我們需要知道為什麼轉向，也需要知道當初為什麼那樣想。

最後更新：2026-09-05

---

## §1 目標

### 1.1 我們要什麼

兩個目標，**同時**達成，不是二選一：

1. **能力**：真正具備編譯器基礎建設 (compiler infrastructure) 的工程能力——不是「會用 MLIR」，
   而是「能改 MLIR 本身」。
2. **可驗證的證明**：一份外部無法造假、業界看得懂的履歷憑證。

第二點是設計整個計畫的約束條件。它排除掉很多「做起來很爽但沒人能驗證」的選項。

### 1.2 成功長什麼樣

最終履歷應該能寫出這樣的內容（這是設計目標，不是既成事實）：

```
LLVM / MLIR — Upstream Contributor
• 20+ commits merged into llvm/llvm-project across the arith and vector
  dialects — the layers every AI compilation pipeline (torch-mlir, IREE,
  XLA) lowers through. Work spans microscaling (MXFP4/FP8) quantization
  op folding, vector canonicalization, and folding-correctness fixes.
  github.com/llvm/llvm-project/commits?author=<you>
• Authored an RFC on <topic>, discussed and accepted on discourse.llvm.org.

mlir-verify — Semantic Validation for MLIR Transformations
• A fuzzing + SMT-based equivalence checker for MLIR passes. Randomly
  generates well-formed IR, executes it before/after transformation, and
  discharges folding rules to an SMT solver to prove semantic preservation.
• Found N defects in upstream MLIR (miscompiles + crashes); M fixed by me upstream.
```

### 1.3 專案定位

> ⚠️ **本節於 2026-08-08 修訂。** 舊定位保留在下方灰底區塊，理由見 §2.4 決策日誌。

**AI compiler 的中端 codegen 基礎建設**——用「正確性 / 形式驗證」當切入角度。

白話：**題目要長在 AI 模型真的會走過的那條路上**（`linalg` → tiling → `vector` →
GPU / 量化），但**做的事情**仍然是我們擅長的那種——folder、canonicalization、
語意正確性、可驗證的證據。

不是改行去做排程調優，是**把既有的強項搬到有人在乎的地段**。

明確**仍然不是**：
- ❌ 自己寫 model importer / 框架前端（那在 llvm-project 樹外，且是體力活）
- ❌ 硬體後端 / 特定加速器 ISA codegen（需要拿不到的硬體）

<details>
<summary>📜 舊定位（2026-08-06 ~ 2026-08-08，已被取代，保留供對照）</summary>

> **通用編譯器基礎建設** (compiler infrastructure)。
>
> 明確**不是**：AI/ML 編譯器（XLA、PyTorch compiler 那條路）、硬體後端 / 加速器 codegen。
> 這兩條也是好路，但這個專案不走。看到有趣的 ML 編譯題目時請記得這件事，避免被拉走。

**為什麼推翻**：這個定位讓題目全部落在 `arith` 的純量算術上。技術上紮實，
但履歷上寫出來的是「我修了幾個整數 folder」，跟 AI compiler JD 的關鍵字**零重疊**。
本人 2026-08-08 明確要求：之後每一題都要對應到 AI compiler 真正會用到的東西。
</details>

### 1.4 節奏

沒有 deadline，長期投入。因此**優先深度而非速度**——寧可一個 patch 花兩週做對，
不要一週送五個淺的。這個選擇的前提是沒有時間壓力；如果哪天有了 deadline，
策略要重新評估（見 §2.4）。

---

## §2 策略與決策紀錄

### 2.1 核心策略：Upstream 是主軸，工具是引擎

> **一句話**：建一台系統性找出 upstream bug 的機器，然後親手修掉它們。

這是一個閉環，兩個工作流互相餵養：

```
        ┌──────────────────────────────────────────┐
        │                                          │
        ▼                                          │
   自建工具 (fuzzer / verifier)                     │
        │                                          │
        │  找出 upstream 的 crash / miscompile       │
        ▼                                          │
   Upstream patch ──────────────────────────────────┘
        │              修 bug 的過程加深對 MLIR 的理解，
        │              讓工具能找到更深的問題
        ▼
   履歷憑證 + 真實能力
```

閉環的價值在於：**兩邊各自的致命傷剛好被對方補掉。**

### 2.2 為什麼不是「只做 upstream 貢獻」

訊號極強但天花板低。如果 commit 全是修 typo、補 verifier、加 test，
履歷上寫「LLVM contributor」但點進去是 5 個一行改動，**反而扣分**。
需要一個東西來提供「有份量的貢獻」的來源——那就是工具。

### 2.3 為什麼不是「只做自己的專案」

沒有任何外部驗證。沒人分得出你的 repo 是精品還是垃圾。
而且 MLIR 圈最不缺的就是「我擴充了 Toy tutorial 做了一個玩具語言」——
GitHub 上有上萬個，看到的第一反應是「他做完官方教學了」，這是**負分**。

**明確禁止的題目**（未來想到類似點子時請回來看這條）：
- ❌ Toy tutorial 的延伸
- ❌ 又一個自製語言前端 → LLVM
- ❌ 只有 dialect 定義、沒有 lowering 的「設計練習」
- ❌ 廣而淺：支援 40 個 op 但只到 IR 層，跑不出結果、沒有數字

判準：**深度優先**。「支援 3 個 op 但完整、正確、有驗證」遠勝「支援 40 個 op 但半殘」。

### 2.4 決策日誌

| 日期 | 決策 | 理由 |
|---|---|---|
| 2026-08-06 | 定位為「通用編譯器基礎建設」，非 ML 編譯 / 非硬體後端 | 個人興趣所在；且此定位的能力只能靠改 LLVM 本身證明，與 upstream 策略天然契合 |
| 2026-08-06 | 採用 upstream + 工具閉環，不做純專案也不做純貢獻 | 見 §2.2、§2.3 |
| 2026-08-06 | 主場 dialect 選 `arith`（後續擴 `vector`） | 見 §3 |
| 2026-08-06 | 開發環境固定在 WSL，不用 Windows | Windows 上要處理 MSVC、路徑長度限制、toolchain 差異，純粹浪費時間 |
| 2026-08-06 | LLVM source + build 放在 WSL 原生路徑 `~/`，**不放 `/mnt/e/`** | WSL2 存取 Windows 磁碟走 9p 協定，ninja 每次 stat 數萬檔案會慢到無法迭代 |
| 2026-08-06 | **所有東西一律放 WSL 原生檔案系統**：本 repo 由 `/mnt/e/Side_Project/MLIR` 遷移到 `~/Side_Project/MLIR` | 修正前一列的判斷。原本認為「repo 小，留在 Windows 磁碟無妨」——但橫跨兩個檔案系統會讓路徑、權限（9p 掛載強制 `0777`）、git 的 filemode 偵測、工具鏈設定全都變囉唆。統一在原生路徑一次省掉整類麻煩 |
| 2026-08-07 | **工作方式改為「能自己講清楚」導向**：每個 patch 送出前，必須做到不看筆記也能回答 reviewer 的提問 | 上游 review 就是這樣運作的——答不出來的 patch 進不去。而且它剛好逼出真實能力，正是 §1.1 第一個目標要的東西。連帶確立：`notes/` 的用途是**讓你能答辯**，不是存檔 |
| 2026-08-07 | **M2/M3 的 fuzzer 產出要分流**：crash 直接送，「漏最佳化」必須先論證真實世界價值才送 | `InstCombineContributorGuide.md` 明文：「fixes for fuzzer-generated missed optimization reports will likely be rejected if there is no evidence of real-world usefulness」。原本 §5 M2/M3 假設「找到就能送」，這個假設是錯的 |
| **2026-08-08** | **⭐ 定位改為「AI compiler 中端 codegen」**，取代原本的「通用編譯器基礎建設」（§1.3 已修訂，舊版保留） | 本人要求：之後每一題都要對應到 AI compiler JD 真正會用到的東西。舊定位讓題目全部落在純量算術，技術紮實但履歷關鍵字零重疊。**做的事情不變**（folder / 正確性 / 形式驗證），**換的是地段** |
| **2026-08-08** | 新增 **§8.7 選題四關過濾器**，每個候選題目都要過 | 光有「往 AI 走」的方向不夠——沒有明確的判準，下次還是會憑手感選到 `muli` 那種題目。第 1 關（「真實 AI pipeline 走得到嗎」）是這次新增的硬關卡 |
| **2026-08-08** | 主場路線定為 **`arith`（量化 op）→ `vector` → `linalg`/GPU**，不直接跳 linalg | ① `kuhar`（現有 reviewer）近一年在 Vector 10 個、Linalg 9 個 commit，往 vector 走是**延續**熟面孔而非重來；② vector 保得住 M2~M4 的 SMT 閉環，linalg 保不住（見 §5 註）；③ `arith` 的 MXFP 量化 op 讓我們**在已經熟的檔案裡**就能拿到 AI 關鍵字 |
| **2026-08-08** | 推翻 §3 原本「linalg 有一群全職 heavy hitter，PR 容易被搶先」的假設 | 實測近 12 個月：Linalg 183 commit / **69 位不重複作者**，最大作者僅佔 20%。那是**人多**不是**壟斷**。真正壟斷的反而是 Tosa（Luke Hutton 一人佔 51%）。原假設是憑印象寫的，沒有數據 |
| **2026-08-21** | **M1 完成條件達標後，主場正式從 `arith` 移到 `vector`**；動手前先對整個 `mlir/lib/Dialect/Vector/` ＋ `Conversion/VectorTo*/` 的 TODO 做一次四關掃描，產出排序過的候選清單（`notes/vector-patch-candidates.md`）再挑題 | 之前的題目是碰到就做，靠運氣。掃描一次的成本大約一個下午，換來的是每一題動手前就知道第 1 關證據在哪個整合測試、有沒有 open PR 撞車。前三名（i2 trunci、轉置 MMA store、`in_bounds` 看索引）09-04～09-05 全部送出，證明這種挑法比隨機碰快 |
| **2026-09-04** | **GPU codegen 的 patch 一律在本機 GPU 上真的跑過再送**；為此在 WSL2 裝了 CUDA redist 並把 build 打開 CUDA runner ＋ tensor core 整合測試 | 追 NVVM IR 裡的屬性只能證明「屬性有傳下去」，證明不了硬體真的照那個 layout 存。#221248 的整合測試在 RTX 3070 上印出 B = 2·Aᵀ，才是 reviewer 一眼能信的證據；送出當天就被 approve |
| **2026-09-04** | **等 review 期間不空等：多個 PR 並行**，每題獨立分支、獨立基準 commit；上游兩週沒回就 rebase 到當天 main、回掉所有 nit、再各 ping 一次（帶新資訊） | 08-21 → 09-04 三個 PR 兩週零回應。單線等待會讓整個計畫的節奏被 reviewer 的排程綁死。09-04 一次 rebase ＋ ping 之後 #215123 當天 merge、#221248 當天 approve，證明「帶新資訊的提醒」有效，而並行讓等待期仍有產出 |
| **2026-09-05** | **靜默錯值的題目先止血、再談完整支援**：能用前置條件擋掉的就先擋（#221293 的 `insert_slice` 只加兩個 bail），完整支援另開一題；bug fix 不順手清 dead code | 完整修法要動另一個 PR（#221268）正在改的 helper，會撞；而刪 dead code 會讓五個既有測試的 CHECK 位移，reviewer 要多看一倍的 diff。小而對的 PR 當天就能 approve，這是 09-04 之後的實證 |
| **2026-09-05** | **review 空檔用小題填**：等 review 的時間拿來送 8 行的 verifier 修正（#221298），不開新的大題 | 一天內送了四個 PR，reviewer 多半是同一批人（banach-space、dcaballe）；小題審得快、也讓他們一次看完，比堆一個大 PR 在隊伍裡等更有效 |

---

## §3 主場：`arith` → `vector` → `linalg` / GPU

長期投入最大的風險是散彈打鳥。**挑一個 dialect 當主場**，在那裡變成熟面孔，
遠勝在十個地方各改一行。但「主場」不等於「永遠只待一個」——**是有順序地往外擴**，
而且每一步都要跟上一步共用 reviewer 與技能。

### 3.1 路線（2026-08-08 定案）

```
arith 純量 folder        ← 已做（M0 / M1-a）。技術紮實，AI 關鍵字弱
   ↓  同一個檔案 ArithOps.cpp，同一個 reviewer
arith 的 MXFP 量化 op    ← M1-b。在熟悉的地方拿到第一個 AI 關鍵字
   ↓  scaling op 的 .td 範例本身就配 vector.broadcast，天然接得上
vector                   ← M1-c/d。AI codegen 的必經之路，138 個 TODO
   ↓  M2/M3 的 fuzzer 在這裡仍然成立
linalg / GPU             ← M5+。tiling / fusion / vectorization
```

### 3.2 為什麼是這個順序

1. **reviewer 關係可以延續，不必重新建立。**
   實測近 12 個月，`kuhar`（Jakub Kuderski，AMD——**我們兩個 PR 現在的 reviewer**）
   在 Vector 有 10 個 commit、Linalg 有 9 個。往 vector 走是**同一群人**。
2. **語意仍然可判定，M2~M4 的閉環保得住。**
   `arith` 與 `vector` 的 fold / canonicalization 都是「這個改寫保值嗎」的命題，
   SMT 可判定（vector 多一層 shape 要處理，但不改變性質）。
   **`linalg` 保不住**——那是排程問題（tiling 怎麼切、fusion 怎麼併），
   沒有等價性證明可做，oracle 要換成執行前後比對。所以 linalg 排在最後，
   而且到那裡時 M4 的定義要改寫（見 §5）。
3. **必經之路。** 幾乎所有 pipeline 都會經過 `arith` 與 `vector`，
   AI pipeline（torch-mlir / IREE / XLA）尤其如此：
   `linalg` → tiling → **vectorize** → `vector` → **量化 / GPU**。

### 3.3 一個被實測推翻的舊假設（留著當教訓）

> ❌ 原文：「不像 `linalg` / `transform` 那樣有一群全職 heavy hitter 高速迭代，
> PR 容易被搶先或被大改動衝掉。」

**數據不支持**（2026-08-08 實測，近 12 個月）：

| dialect | commits | 不重複作者 | 最大作者佔比 |
|---|---|---|---|
| Linalg | 183 | **69** | 20% |
| Vector | 157 | **57** | 12% |
| Tosa | 134 | 31 | **51%**（Luke Hutton） |
| Arith | 80 | 41 | — |

Linalg 是 69 個人分 183 個 commit，平均一人 2.6 個——人多不等於壟斷。
撞車風險較高的是 Tosa。

**方法**：判斷一個 dialect 有多競爭，用數的，不用印象：

```bash
git log --since="12 months ago" --pretty='%an' -- mlir/lib/Dialect/<D>/ | sort | uniq -c | sort -rn
```

> ✅ **已確認（2026-08-07）**：`smt` dialect 在上游，bitvector 理論齊全，
> 還附 SMT-LIB 匯出器可直接餵 z3。但**沒有浮點理論**（所以 rounding mode
> 那類題目得繞過它直接產 SMT-LIB），且 `ArithToSMT` conversion 只存在於一個
> 停擺 17 個月的 draft PR #131484（且該 PR 的 `ceildivsi` 轉換是錯的）。
> 詳見 [`notes/arith-to-smt-exploration.md`](notes/arith-to-smt-exploration.md)。

---

## §4 我們的 repo

**兩者都在 WSL 原生檔案系統。不要碰 `/mnt/*`（Windows 磁碟）。**

```
~/Side_Project/MLIR/               ← 本 repo
├── Goal.md                        ← 本文件（總綱）
├── TODO.md                        ← 交接／接續用的現況快照
├── mlir-dev.code-workspace        ← 用這個開 VS Code（同時掛上兩個資料夾）
├── notes/                         ← 讀 code 的筆記、bug 分析
│   ├── arith-patch-candidates.md
│   ├── ceildivsi-minint-analysis.md    ← M1 第一發的完整分析
│   ├── arith-to-smt-exploration.md     ← ArithToSMT 現況與 PR #131484 的缺陷
│   └── upstream-conventions.md         ← ⭐ 社群怎麼運作（含 AI 政策）
├── playground/                    ← 隨手試 IR 的地方（刻意不放上游樹裡）
├── patches/                       ← 送出去的 patch 的紀錄與說明
└── tools/                         ← fuzzer / verifier 的原始碼（M2 之後）

~/llvm-project/                    ← LLVM 上游 source（主要工作區）
└── build/                         ← 建置產物
~/llvm-explore/                    ← git worktree，分支 explore
                                     用來並行探查，不干擾主線的分支狀態
```

> **worktree 的用法**：`git worktree add ~/llvm-explore -b <branch> main`。
> 探查（讀 code、grep、跑既有的 `mlir-opt`）不需要另建 build；
> 只有要改 code 驗證時才需要第二個 build 目錄。
> ⚠️ **兩個 build 目錄不可以同時跑 ninja**，見 `TODO.md` 的坑 2。

---

## §5 里程碑

里程碑**不綁日期，綁完成條件**。

> **目前進行到哪，看 [`TODO.md`](TODO.md)**，不要在這裡記進度。

| # | 名稱 | 完成條件 | AI 關鍵字 |
|---|---|---|---|
| **M-1** | 環境就緒 | `ninja check-mlir` 全綠 | — |
| **M0** | 打通流程 | **任何一個** commit 進入 llvm-project main | — |
| **M1** | 在 arith / vector 站穩 | 3~5 個實質 patch merged。**其中至少 2 個要過 §8.7 第 1、2 關** | quantization、vectorization |
| **M2** | Fuzzer v1：crash 獵人 | 工具能自動找到 ≥1 個 upstream crash 並附最小 repro。**輸入涵蓋 `arith` + `vector`** | — |
| **M3** | Fuzzer v2：miscompile 獵人 | 加上執行 oracle，找到 ≥1 個語意錯誤（算錯，非 crash） | — |
| **M4** | 語意驗證（Alive2 for MLIR） | 能用 SMT 對 **`arith` + `vector`** 的 folding 規則做等價性證明 | mixed precision |
| **M5** | 進入 linalg / GPU 層 | ≥2 個 patch merged 在 `linalg` 或 `gpu`，題目與 tiling / fusion / vectorization 相關 | tiling、fusion、GPU codegen |
| **M∞** | Discourse RFC | 一篇主筆的 RFC 被社群認真討論 | — |

> ⚠️ **M4 → M5 的斷點（2026-08-08 記錄）**：M2~M4 的 fuzzer + SMT 引擎是為
> **語意可判定**的 dialect 設計的。`arith` 與 `vector` 都成立（fold 是
> 「這個改寫保值嗎」的命題）。**`linalg` 不成立**——那是排程問題（tiling 怎麼切、
> fusion 怎麼併），沒有等價性可證。
>
> 所以進 M5 時，M4 的工具**不會自動跟過去**。到那裡要嘛把 oracle 換成
> 「執行前後結果比對」（M3 那條腿還在），要嘛接受 M5 是純 upstream 貢獻、
> 不靠工具餵題。**現在不必解決，但別到時候才發現。**

### 各里程碑的重點說明

**M0 — 目標不是做出有價值的東西**，而是走完一次 `fork → PR → review → merge`，
把流程風險先清掉。刻意挑最小的：爛掉的 error message、缺的 verifier 檢查、沒覆蓋到的 test edge case。
**成功條件是有一個 commit 進 main，內容多小都無所謂。**
很多人卡死在這一步的原因是想第一發就打大的。

**M2 — 不要自己寫 test case reducer**，upstream 已經有 `mlir-reduce`，直接串。
這層技術含量不高但**產出穩定**：跑一晚上通常就有東西。每個 crash = 一個 issue + 一個 patch。

**M3 — crash 好找，算錯難找而且嚴重得多。** 找到一個 arith fold 的 miscompile，
是可以在 Discourse 上被認真討論的東西。

**M5 — 履歷關鍵字最密集的一層。**
`linalg` 有 184 個 TODO，但不是每個都在真實 pipeline 上，
所以第 1 關（§8.7）在這層的過濾強度最高。

**M4 — LLVM IR 有 Alive2**（Nuno Lopes / John Regehr 等人），MLIR 這邊沒有等價的成熟工具。
這層做出來不只是履歷，是**可以投 workshop paper 的東西**。

> ⚠️ **前提修正（2026-08-07）**：「MLIR 這邊什麼都沒有」不精確。
> 上游已有 `mlir/utils/verify-canon/verify_canon.py`（2024，Ivan Butygin）——
> 把 canonicalize 前後都 lower 到 LLVM IR，印成可貼進 Alive2 網頁的格式。
> 但那是 **90 行、要人工複製貼上、樹裡沒有任何東西用它**的 helper，不是工具。
> 差距在自動化、批次、fuzzer 輸入、CI，以及直接在 MLIR 層驗證（不必先降到 LLVM）。
> 機會仍然成立，但論述要誠實：是「把既有的手動橋接做成真正的工具」，不是從無到有。
> 詳見 [`notes/upstream-conventions.md`](notes/upstream-conventions.md) §5。

**M∞ — 說真的，一篇你主筆、社群認真討論過的 RFC，訊號強度不輸 20 個 commit**，
因為它證明的是設計能力與溝通能力，不只是實作能力。這件事貫穿全程，時機到就做。

---

## §6 MLIR 速成（給接手的人 / 給忘記的自己）

只講後續會用到的最小概念集。

### 6.1 MLIR 是什麼

LLVM IR 是**一種**中介表示法，層級固定（大約是「有型別的組語」）。
MLIR 是一個讓你**定義自己的中介表示法**的框架，並讓不同層級的 IR 共存於同一份檔案、
逐步下降 (progressively lower)。

一句話：**LLVM IR 是一種 IR；MLIR 是 IR 的元框架。**

### 6.2 核心名詞

| 名詞 | 意思 |
|---|---|
| **Dialect** | 一組相關 operation / type / attribute 的命名空間。例：`arith`（算術）、`scf`（結構化控制流）、`func`、`llvm`（對應 LLVM IR） |
| **Operation (Op)** | IR 的基本單位。**所有東西都是 op**——連 function、module 都是 op |
| **Region / Block** | Op 可以包含 region，region 包含 block，block 包含 op。這是巢狀結構的來源（`scf.for` 的 body 就是一個 region） |
| **Attribute** | 編譯期常數資料，掛在 op 上（例如 `arith.constant` 的值） |
| **Trait / Interface** | Op 的橫切性質。Trait 是靜態標記（如 `Commutative`）；Interface 是可呼叫的多型 API |
| **ODS** | Operation Definition Specification。用 TableGen (`.td` 檔) 宣告式地定義 op，自動生成 C++ |
| **Pass** | 對 IR 做一次轉換的單位 |
| **Pattern** | 局部改寫規則（match 一個 IR 形狀 → 換成另一個） |

### 6.3 兩組最容易搞混的概念

**(A) Folding vs. Canonicalization** — 這是我們主場的核心，一定要分清楚。

| | `fold()` | Canonicalization pattern |
|---|---|---|
| 能做什麼 | 只能回傳既有的 value 或常數 attribute | 可以建立 / 替換 op，改寫成完全不同的形狀 |
| 成本 | 極便宜，到處都會被呼叫 | 較貴，由 `-canonicalize` pass 驅動 |
| 宣告方式 | `.td` 裡 `let hasFolder = 1` | `.td` 裡 `let hasCanonicalizer = 1` 或獨立 pattern |
| 例子 | `arith.addi(x, 0) → x` | 需要引入新 op 的改寫 |

共同鐵律：**兩者都必須「永遠有益」且具正規化性質**——不能是「有時比較快」的啟發式最佳化，
那種東西屬於獨立的 optimization pass。這條鐵律是 review 時最常被打槍的點。

**(B) Transformation pass vs. Dialect conversion**

- **Transformation**：在同一批 dialect 內改寫（如 `-canonicalize`、`-cse`）。
- **Dialect conversion**：一套 legalization 框架，把 dialect A 換成 dialect B。
  牽涉 `TypeConverter`（型別怎麼對應）與 legality 宣告（哪些 op 合法 / 非法 / 動態合法），
  分 partial 與 full conversion。從高階 dialect 一路降到 `llvm` dialect 走的就是這條。

### 6.4 一個 op 的生命週期（實務上你會碰到的檔案）

以 `arith` 為例：

```
mlir/include/mlir/Dialect/Arith/IR/ArithOps.td   ← op 的宣告（ODS）：有沒有 folder / canonicalizer
mlir/lib/Dialect/Arith/IR/ArithOps.cpp           ← fold() / canonicalization pattern 的實作
mlir/test/Dialect/Arith/canonicalize.mlir        ← 對應的 lit test
```

### 6.5 lit test 怎麼讀

MLIR 的測試是「跑一個指令，用 FileCheck 比對輸出」：

```mlir
// RUN: mlir-opt %s -canonicalize | FileCheck %s

// CHECK-LABEL: func @add_zero
//       CHECK:   return %arg0
func.func @add_zero(%arg0: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %0 = arith.addi %arg0, %c0 : i32
  return %0 : i32
}
```

`// RUN:` 是實際執行的指令（`%s` = 本檔）。`// CHECK:` 是對輸出的斷言。
**沒有 test 的 PR 不會 merge，這是硬規定、沒有例外。**

---

## §7 環境設定

### 7.1 為什麼是 WSL

Windows 上 build LLVM 要處理 MSVC、路徑長度限制、toolchain 差異，純粹浪費時間。
這是刻意的環境選擇，不是將就。

### 7.2 取得原始碼

```bash
git clone --filter=blob:none https://github.com/llvm/llvm-project.git ~/llvm-project
```

`--filter=blob:none` 是 blobless partial clone：**保留完整 commit 歷史**（`git log` 考古能用，
這對找 reviewer 很重要，見 §8），但檔案內容按需下載。比完整 clone 快很多。

### 7.3 建置

```bash
cd ~/llvm-project && mkdir -p build && cd build

cmake -G Ninja ../llvm \
  -DLLVM_ENABLE_PROJECTS="mlir" \
  -DLLVM_TARGETS_TO_BUILD="host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DLLVM_ENABLE_LLD=ON \
  -DLLVM_CCACHE_BUILD=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DBUILD_SHARED_LIBS=ON

ninja mlir-opt
ninja check-mlir     # 全綠 = M-1 完成
```

**每個 flag 的理由**（不要隨便改）：

| Flag | 理由 |
|---|---|
| `LLVM_ENABLE_ASSERTIONS=ON` | **不可省**。MLIR 的 IR invariant 大量靠 assertion 守住；關掉的話 bug 會變成無聲的記憶體亂寫，會 debug 到懷疑人生 |
| `BUILD_SHARED_LIBS=ON` | 改一個 `.cpp` 的重連結時間從分鐘級降到秒級。**開發用，不要拿來發布** |
| `CMAKE_BUILD_TYPE=Release` | Debug build 的 `mlir-opt` 慢到不能跑 fuzzer，且吃掉 100GB+。真的要進 debugger 時另開一個 `RelWithDebInfo` build 目錄 |
| `LLVM_ENABLE_LLD=ON` | lld 連結遠快於 GNU ld |
| `LLVM_CCACHE_BUILD=ON` | 切分支重 build 時救命 |
| `LLVM_OPTIMIZED_TABLEGEN=ON` | TableGen 用最佳化版本建，減少 `.td` 改動後的等待 |
| `LLVM_TARGETS_TO_BUILD="host"` | 只建本機架構。不需要全部 target，省一半時間 |

### 7.4 依賴套件

```bash
sudo apt install -y build-essential ninja-build clang lld ccache z3 libz3-dev zlib1g-dev libzstd-dev
```

（`z3` / `libz3-dev` 是 M4 才會用到，先裝著。）

---

## §8 Upstream 貢獻 SOP

### 8.1 流程

LLVM **已於 2023 年底從 Phabricator 搬到 GitHub PR**。
看到叫你用 Phabricator 的教學一律是過期的。流程就是 fork + branch + PR。

### 8.2 硬規則

> 📄 實地調查（讀官方文件 + 統計真實 merged PR + 讀真實 review 往來）的完整結果見
> [`notes/upstream-conventions.md`](notes/upstream-conventions.md)。
> 這裡只列不可違反的。

1. **沒有 test 的 PR 不會 merge。** 沒有例外。
2. Commit title 格式：`[mlir][arith] Fold xxx when yyy`。前綴錯了會被要求改。
   動詞開頭；結尾的 `(#NNNNN)` 由 GitHub squash-merge 自動加，**自己不要打**。
3. 送出前跑 `git clang-format HEAD~1`。格式問題被 reviewer 抓到很浪費來回。
4. **GitHub 帳號的 email 必須公開**（`DeveloperPolicy.md` 明文要求，buildbot 要用它
   通知建置失敗）。到 https://github.com/settings/emails 關掉
   "Keep my email addresses private"。
5. **Alive2 證明是社群明文認可的品質訊號**，能附就附。
6. **「Extractive contribution」**：黃金法則是「貢獻的價值要大於別人 review 它的時間」。
   不合格會被貼 `extractive` 標籤。**這就是 M0 要挑最小題目的理由。**
7. **送出前你要自己讀過每一行，而且能當場回答 reviewer 的提問。**
   答不出來就還不能送——這是 `notes/` 存在的真正理由。

### 8.3 怎麼找 reviewer

對你改動的檔案，找最常出現的作者：

```bash
git log --format='%an' -- <file> | sort | uniq -c | sort -rn | head
```

在 PR 上 @ 他們。**一週沒回應可以禮貌 ping 一次**——review 延遲是常態，不是針對你。

### 8.4 怎麼找題目（尤其是第一個）

> 本節是「怎麼找到候選」。找到之後過 §8.7 的四關過濾器。
> 2026-08-08 以前用本節挖出來的候選，有一半過不了第 1 關。

**別去搶 `good first issue`**，MLIR 的通常幾小時內就被認領。用這幾招自己挖：

1. **挖 TODO / FIXME**：`grep -rn "TODO\|FIXME" mlir/lib/Dialect/Arith/`
   ——這些是開發者自己承認的技術債，修了幾乎不會被拒。
2. **找缺的 canonicalization**：打開 `ArithOps.td` 看哪些 op 有 `hasFolder` / `hasCanonicalizer`、
   哪些沒有。想一個明顯的代數恆等式，確認 upstream 沒做，補上 pattern + test。
   **這類 patch 自包含、好 review、社群真心想要。**

   > ⚠️ **實測修正（2026-08-06）**：這招在 `arith` **不管用**——54 個 op 幾乎全都有 folder，
   > 成熟 dialect 的這條路早被做掉了。真正的縫隙在**第 1 招**：既有 folder 裡被
   > 明確標註放棄的 case。
   >
   > **換到新 dialect 時的正確順序：先掃 TODO/FIXME，再看覆蓋率。**
   > 覆蓋率掃描的價值不在找到空缺，而在**判斷這個 dialect 有多成熟**——
   > 越成熟，就越該把力氣放在 TODO 上。
3. **爛的錯誤訊息**：拿奇怪的 IR 餵 `mlir-opt`，看哪些診斷訊息沒說清楚問題在哪。
   改善診斷是很受歡迎的貢獻。
4. **issue tracker 的 crash**：搜 `label:mlir crash`，挑沒人認領的，
   用 `mlir-reduce` 縮小 → 定位 → 修。

### 8.5 社群位置

- **討論設計 / 發 RFC**：`discourse.llvm.org`
- **快問快答**：LLVM Discord

### 8.7 ⭐ 選題四關過濾器（2026-08-08 新增，每一題都要過）

§8.4 講的是**怎麼找到**候選題目。這節講**找到之後憑什麼留下它**。

四關，缺一不可。任何一關過不了就換題。

---

**第 1 關（最硬，2026-08-08 新增）：這個 op / pass 在真實 AI pipeline 上會被走到嗎？**

不接受「理論上會經過」。必須能**指出具體位置**，例如：

> 「torch-mlir 把 `torch.aten.matmul` 降到 `linalg.matmul`，
> `-linalg-vectorize` 產生 `vector.contract`，這個 pattern 就在它的 lowering 上」

或

> 「`arith.scaling_extf` 是 OCP MXFP 規格的反量化 op，
> `ArithToAMDGPU` 把它降到 MI355 的硬體指令，
> `mlir/test/Integration/Dialect/XeGPU/WG/simple_mxfp_gemm_dequantizeB_F4.mlir`
> 是一個真的會跑的 MXFP GEMM 整合測試」

**怎麼查**（實際可執行，不是原則）：

```bash
# 這個 op 有哪些 conversion / 誰在用它
grep -rln "<OpName>" mlir/lib/Conversion/ mlir/lib/Dialect/
# 有沒有跑得起來的整合測試（= 有人真的在用）
grep -rln "<op_asm_name>" mlir/test/Integration/
```

答不出來就是**沒有第 1 關**，換題。

---

**第 2 關：題目本身說得出 JD 關鍵字嗎？**

寫進履歷的那一行，要包含至少一個：
`vectorization` / `tiling` / `fusion` / `bufferization` / `quantization` /
`GPU codegen` / `tensor layout` / `mixed precision`。

判準：這一行給不懂 MLIR 的 recruiter 看，認不認得出是 AI compiler。
「修了一個 folder」不算；「MXFP4 量化 op 的 constant folding」算。

---

**第 3 關（沿用 §8.2）：不看筆記能答辯嗎？**

reviewer 的提問要由你本人當場回答，答不出來就還不能送。

---

**第 4 關（沿用）：做得出可驗證的證據嗎？**

Alive2 證明 / 窮盡測試 / benchmark 數字，至少一項。
M1-a 的 `ceildivsi` 就是範本：Alive2 符號式證明 **+** i4/i8 窮盡 oracle 掃描，
兩份**刻意互補**（Alive2 只證「與 ExpandOps 一致」，oracle 才獨立於 LLVM 實作）。

---

**第 5 步：撞車查證**（每題必做，放在最後）：

```bash
curl -s "https://api.github.com/search/issues?q=repo:llvm/llvm-project+is:pr+is:open+<關鍵字>" \
  | grep -E '"(number|title)"' | paste - -
```

只搜本地 source tree 看不到未 merge 的 PR（`ArithToSMT` 的誤判即出於此，見 `TODO.md` Q3）。

---

## §9 指令速查

```bash
# 建置
cd ~/llvm-project/build && ninja mlir-opt

# 跑全部 MLIR 測試
ninja check-mlir

# 跑單一測試檔
./bin/llvm-lit -v ../mlir/test/Dialect/Arith/canonicalize.mlir

# 手動觀察某個 pass 的效果
./bin/mlir-opt input.mlir -canonicalize

# 看 IR 在 pass pipeline 中每一步的變化（debug 神器）
./bin/mlir-opt input.mlir -pass-pipeline='...' --mlir-print-ir-after-all

# 縮小一個會 crash 的輸入
./bin/mlir-reduce crash.mlir --test=<script>

# 送 PR 前
git clang-format HEAD~1
```

---

## §10 下一步

> **這一節已搬到 [`TODO.md`](TODO.md)。**
>
> 進度、待辦、未解問題一律寫在那裡，不要寫在本檔——
> 兩邊都記進度必然會漂移，而漂移的文件比沒有文件更糟。
>
> 本檔只在**決策改變**時更新（追加 §2.4 的一列），或**學到新的通則**時更新
> （例如 §8.4 那條實測修正）。
