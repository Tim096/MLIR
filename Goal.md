# MLIR 專案總綱 (Goal.md)

> **這份文件是什麼**：這個專案的唯一真實來源 (single source of truth)。
> 它同時是四件事——目標宣言、決策紀錄、MLIR 入門教材、以及「下一步做什麼」的看板。
>
> **怎麼用**：
> - 隔了兩週回來忘記在幹嘛 → 讀 §1 和 §5
> - 想知道「為什麼是這樣做，不是那樣做」 → 讀 §2（含被否決的方案）
> - 完全不懂 MLIR 的人要接手 → 從 §6 開始讀
> - 今天要動手 → 直接跳 §5 的「當前狀態」和 §10
>
> **維護規則**：每次有進展就更新 §5 的狀態表與 §10 的下一步。決策改變時，不要刪掉舊決策，
> 在 §2.4 追加一筆並註明日期與理由——未來的我們需要知道為什麼轉向。

最後更新：2026-08-06

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
• 20+ commits merged into llvm/llvm-project, focused on the arith and vector
  dialects: folding correctness fixes, missing canonicalization patterns,
  op verifiers, and diagnostic quality.
  github.com/llvm/llvm-project/commits?author=<you>
• Authored an RFC on <topic>, discussed and accepted on discourse.llvm.org.

mlir-verify — Semantic Validation for MLIR Transformations
• A fuzzing + SMT-based equivalence checker for MLIR passes. Randomly
  generates well-formed IR, executes it before/after transformation, and
  discharges folding rules to an SMT solver to prove semantic preservation.
• Found N defects in upstream MLIR (miscompiles + crashes); M fixed by me upstream.
```

### 1.3 專案定位

**通用編譯器基礎建設** (compiler infrastructure)。

明確**不是**：AI/ML 編譯器（XLA、PyTorch compiler 那條路）、硬體後端 / 加速器 codegen。
這兩條也是好路，但這個專案不走。看到有趣的 ML 編譯題目時請記得這件事，避免被拉走。

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
| 2026-08-06 | LLVM source + build 放在 WSL 原生路徑 `~/`，**不放 `/mnt/e/`** | WSL2 存取 Windows 磁碟走 9p 協定，ninja 每次 stat 數萬檔案會慢到無法迭代。本專案 repo 留在 `/mnt/e/` 沒問題，因為它小 |

---

## §3 主場：`arith` dialect

長期投入最大的風險是散彈打鳥。**挑一個 dialect 當主場**，在那裡變成熟面孔，
遠勝在十個地方各改一行。

選 `arith` 的三個理由：

1. **語意明確且可判定**。`arith` 的每一條 folding / canonicalization 規則，都是一個
   可以用 SMT solver 驗證的命題（「這個改寫在所有 input 下都保值嗎？」）。
   這讓工具能從「看它有沒有 crash」升級成「**證明**它改寫錯了」——後者價值差一個量級。
   這是把 §2.1 閉環真正接起來的關鍵。
2. **門檻友善但不無聊**。不像 `linalg` / `transform` 那樣有一群全職 heavy hitter 高速迭代，
   PR 容易被搶先或被大改動衝掉。
3. **必經之路**。幾乎所有 pipeline 都會經過 `arith`，改動影響面大，patch 容易被認為有價值。

> 待確認：MLIR 近年 upstream 了 `smt` dialect（從 CIRCT 移入）。若現況仍在，
> 驗證工具可以建在它之上，不必自己接 Z3 binding。**M4 開始前先確認。**

---

## §4 我們的 repo

```
/mnt/e/Side_Project/MLIR/          ← 本 repo（小、放 Windows 磁碟無妨）
├── Goal.md                        ← 本文件
├── notes/                         ← 讀 code 的筆記、bug 分析
├── patches/                       ← 送出去的 patch 的紀錄與說明
└── tools/                         ← fuzzer / verifier 的原始碼（M2 之後）

~/llvm-project/                    ← LLVM 上游 source（大、必須放 WSL 原生路徑）
└── build/                         ← 建置產物
```

---

## §5 里程碑與當前狀態

里程碑**不綁日期，綁完成條件**。

| # | 名稱 | 完成條件 | 狀態 |
|---|---|---|---|
| **M-1** | 環境就緒 | `ninja check-mlir` 全綠 | 🔵 進行中 |
| **M0** | 打通流程 | **任何一個** commit 進入 llvm-project main | ⚪ 未開始 |
| **M1** | 在 arith 站穩 | 3~5 個實質 patch merged，皆在 arith/vector | ⚪ 未開始 |
| **M2** | Fuzzer v1：crash 獵人 | 工具能自動找到 ≥1 個 upstream crash 並附最小 repro | ⚪ 未開始 |
| **M3** | Fuzzer v2：miscompile 獵人 | 加上執行 oracle，找到 ≥1 個語意錯誤（算錯，非 crash） | ⚪ 未開始 |
| **M4** | 語意驗證（Alive2 for MLIR） | 能用 SMT 對 arith 的 folding 規則做等價性證明 | ⚪ 未開始 |
| **M∞** | Discourse RFC | 一篇主筆的 RFC 被社群認真討論 | ⚪ 未開始 |

### 各里程碑的重點說明

**M0 — 目標不是做出有價值的東西**，而是走完一次 `fork → PR → review → merge`，
把流程風險先清掉。刻意挑最小的：爛掉的 error message、缺的 verifier 檢查、沒覆蓋到的 test edge case。
**成功條件是有一個 commit 進 main，內容多小都無所謂。**
很多人卡死在這一步的原因是想第一發就打大的。

**M2 — 不要自己寫 test case reducer**，upstream 已經有 `mlir-reduce`，直接串。
這層技術含量不高但**產出穩定**：跑一晚上通常就有東西。每個 crash = 一個 issue + 一個 patch。

**M3 — crash 好找，算錯難找而且嚴重得多。** 找到一個 arith fold 的 miscompile，
是可以在 Discourse 上被認真討論的東西。

**M4 — LLVM IR 有 Alive2**（Nuno Lopes / John Regehr 等人），MLIR 這邊沒有等價的成熟工具。
這層做出來不只是履歷，是**可以投 workshop paper 的東西**。

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

1. **沒有 test 的 PR 不會 merge。** 沒有例外。
2. Commit title 格式：`[mlir][arith] Fold xxx when yyy`。前綴錯了會被要求改。
3. 送出前跑 `git clang-format HEAD~1`。格式問題被 reviewer 抓到很浪費來回。

### 8.3 怎麼找 reviewer

對你改動的檔案，找最常出現的作者：

```bash
git log --format='%an' -- <file> | sort | uniq -c | sort -rn | head
```

在 PR 上 @ 他們。**一週沒回應可以禮貌 ping 一次**——review 延遲是常態，不是針對你。

### 8.4 怎麼找題目（尤其是第一個）

**別去搶 `good first issue`**，MLIR 的通常幾小時內就被認領。用這幾招自己挖：

1. **挖 TODO / FIXME**：`grep -rn "TODO\|FIXME" mlir/lib/Dialect/Arith/`
   ——這些是開發者自己承認的技術債，修了幾乎不會被拒。
2. **找缺的 canonicalization**：打開 `ArithOps.td` 看哪些 op 有 `hasFolder` / `hasCanonicalizer`、
   哪些沒有。想一個明顯的代數恆等式，確認 upstream 沒做，補上 pattern + test。
   **這類 patch 自包含、好 review、社群真心想要。**
3. **爛的錯誤訊息**：拿奇怪的 IR 餵 `mlir-opt`，看哪些診斷訊息沒說清楚問題在哪。
   改善診斷是很受歡迎的貢獻。
4. **issue tracker 的 crash**：搜 `label:mlir crash`，挑沒人認領的，
   用 `mlir-reduce` 縮小 → 定位 → 修。

### 8.5 社群位置

- **討論設計 / 發 RFC**：`discourse.llvm.org`
- **快問快答**：LLVM Discord

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

> **這一節是活的看板。每次有進展就改這裡。**

### 現在的狀態
- [x] 建立本 repo 與 Goal.md
- [ ] `apt install` 建置依賴（需要 sudo 密碼，由使用者手動執行）
- [ ] LLVM clone 完成
- [ ] 首次建置成功、`ninja check-mlir` 全綠 → **M-1 達成**
- [ ] 產出 `arith` 候選 patch 清單 → 挑一個最小的當 M0

### 接下來要做的事（依序）
1. 完成環境建置（M-1）
2. 從候選清單挑**最小**的題目做 M0——目標是打通流程，不是做大事
3. M0 merged 之後，再挑 3~5 個實質題目做 M1

### 給未來的自己的提醒
- 覺得某個 ML 編譯 / 硬體後端的題目很有趣時 → 回去看 §1.3，我們不走那條路
- 想做「又一個玩具語言」時 → 回去看 §2.3
- 想一次送很多淺 patch 時 → 回去看 §1.4，深度優先
