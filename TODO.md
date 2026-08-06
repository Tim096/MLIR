# TODO / 現況快照

> **這份文件的用途**：接續工作用的交接文件。
> 換一個 session、換一台機器、或隔了一個月回來，讀這份就能接上，不必翻聊天紀錄。
>
> 分工：
> - **`Goal.md`** = 為什麼這樣做（策略、決策、MLIR 背景知識、貢獻 SOP）——**改動頻率低**
> - **`TODO.md`**（本檔） = 現在在哪、下一步做什麼、有什麼還沒確認——**每次有進展就更新**
>
> 新 session 開場建議直接說：「讀 Goal.md 和 TODO.md，然後接續」。

最後更新：2026-08-06 23:2x

---

## 一句話現況

環境剛建好，`ninja check-mlir` 還在跑。候選 patch 清單已產出，**還沒送出任何 patch**。
下一步是確認題目沒被別人做走，然後動手做 M0。

---

## 環境（全部在 WSL 原生檔案系統）

| 項目 | 位置／版本 |
|---|---|
| 本 repo | `~/Side_Project/MLIR` |
| LLVM 上游 | `~/llvm-project`，HEAD = `27f1aa4c9a42`（2026-08-06 的 main） |
| 建置目錄 | `~/llvm-project/build` |
| 機器 | 16 核 / 31GB RAM / 928GB 可用 |
| Toolchain | clang 14.0.0、lld 14、ninja 1.10.1、ccache 4.5.1、cmake 3.22.1、z3 4.8.12 |

**⚠️ 不要把任何東西放回 `/mnt/*`（Windows 磁碟）。** 理由見 `Goal.md` §2.4 決策日誌。

建置設定與每個 cmake flag 的理由：`Goal.md` §7.3。

---

## 進行中

- [ ] **`ninja check-mlir` 建置＋測試**（背景執行中，PID 5499）
      - 這是 **M-1 的完成條件**：全綠即達成
      - 冷啟動、ccache 空的，估計 30~90 分鐘
      - 檢查是否還活著：`pgrep -a ninja`
      - 如果中斷了，重跑：`cd ~/llvm-project/build && ninja check-mlir`
      - ⚠️ 用了 clang 14 當 host compiler（Ubuntu 22.04 內建）。如果編譯失敗抱怨
        C++ 標準或 host toolchain 版本，改用 gcc-11 或裝新版 clang 再試

---

## 下一步（依序）

### 1. 先確認沒撞車 ← **最優先，動手前一定要做**

到 `github.com/llvm/llvm-project/pulls` 搜 `arith`，
確認下面選定的題目沒有人已經開 PR 在做。順便搜 issue tracker。

### 2. M0 — 打通 PR 流程

**題目**：`mlir/lib/Dialect/Arith/IR/ArithOps.cpp:3134` 與 `:3229` 的過期 TODO。

兩處 switch 尾端寫著 `// TODO: Add remaining reduction operations.`，
但查證後 `AtomicRMWKind` 的 16 個 case 裡只缺 `assign`，而 `assign` 根本不是 reduction
（沒有單位元素、沒有對應的二元 op）。所以這個 TODO 是寫不完的，該收掉。

**做法**：把 `default:` 換成顯式的 `case AtomicRMWKind::assign:`，讓 switch 變窮盡——
未來有人加新 enum kind 時會得到**編譯錯誤**而不是執行期才靜默報錯。順手刪掉過期 TODO。

- commit title 要加 `[NFC]`
- 送出前確認沒有其他地方依賴原本 `default:` 的行為
- **M0 的目標是走完一次 `fork → PR → review → merge`，不是做出有影響力的東西。**
  內容多小都無所謂

### 3. M1 第一發 — `ceildivsi` 的 MININT folding gap

`mlir/lib/Dialect/Arith/IR/ArithOps.cpp:991`。實作用取負來做 ceiling 除法，
於是 `a = MININT` 時因取負溢位而整段放棄折疊。改成不取負的算法即可。

有實際行為改變、好寫 test（直接在 `mlir/test/Dialect/Arith/canonicalize.mlir` 加 case）、
不會引發設計爭論。

### 4. M1 主菜 — rounding mode 安全性（見下面「未解問題」）

---

## 未解問題（有結論就搬進 `notes/`）

### ⭐ Q1：三個 canonicalization 在 custom rounding mode 下到底安不安全？

`mlir/lib/Dialect/Arith/IR/ArithCanonicalization.td:562 / 575 / 588`
三個 pattern 都掛著同一句 upstream 自己寫的話：

```
// TODO: Verify if this canonicalization is safe when a rounding mode is
// specified. For the moment, bail on custom rounding modes.
```

這題跟本專案主軸最契合（見 `Goal.md` §3）：upstream 親口承認的未解問題，
而且是 SMT 可判定的命題。

**以下是手推的假設，全部尚未驗證，絕對不可直接當結論送出 PR。**

| Pattern | 改寫 | 初步判斷 |
|---|---|---|
| `MulFOfNegF` | `mulf(negf x, negf y) → mulf(x, y)` | 可能安全 |
| `DivFOfNegF` | `divf(negf x, negf y) → divf(x, y)` | 可能安全 |
| `SubFOfNegZero` | `subf(-0.0, x) → negf(x)` | **可能不安全，疑似有反例** |

**mul / div 可能安全的理由**：`negf` 只翻符號位，是精確運算、不做捨入。
而 `(-x) × (-y)` 與 `x × y` 的無窮精度真實值**完全相同**。
既然送進捨入的是同一個實數、捨入模式又相同，結果必然相同。除法同理。

**`subf` 的疑似反例**：取 `x = -0.0`、捨入模式為 round-toward-negative。
- IEEE 754：兩個同號運算元相減、結果恰為零時，該零的符號在所有捨入模式下是 `+0`，
  **唯獨 roundTowardNegative 下是 `-0`**
- 所以 `(-0) - (-0)` 在 RTN 下得 `-0`
- 但 `negf(-0)` 是 `+0`
- 兩者不一致 → 改寫在 RTN 下不保值

（另兩種零的情形推起來是相符的：`x = +0` 時兩邊在所有模式下都得 `-0`；
預設模式 RNE 下 `x = -0` 兩邊也都得 `+0`。所以**今天沒有實際 bug**，
因為 pattern 目前就是在 custom rounding mode 下放棄。）

**怎麼驗證**：先用實際執行比對（最快），再用 SMT 形式化。
**這題是 M4 驗證器的完美第一個練習題**——如果工具能自動吐出這個 `-0` 反例，
就是工具有效的第一個證據。

**價值**：即使結論是「不能放寬」，把反例與理由寫進註解、讓後人不必重推，也是實在的貢獻。

### Q2：`arith.muli` 的 overflow TODO 到底想講什麼？

`ArithOps.cpp:654` 的 `// TODO: Handle the overflow case.`。
推測跟 `nsw` / `nuw` flag 有關，但**還沒查清楚**。要先搞懂再決定值不值得做。

### Q3：MLIR 的 `smt` dialect 現在還在嗎？

聽說近年從 CIRCT 移入 upstream。若在，M4 的驗證器可以建在它之上，
不必自己接 Z3 binding。**M4 開始前確認。**（z3 已經裝了，兩條路都走得通。）

### Q4：`scaling_extf` / `scaling_truncf` 有沒有 fold 機會？

這兩個是全 `arith` 裡**唯二**完全沒有 folder 也沒有 canonicalizer 的 op
（microscaling 浮點格式相關，較新）。是唯一還空著的地方，值得看一眼有沒有
round-trip 之類的機會。優先度低。

---

## 已完成

- [x] 決定策略：upstream 為主軸 + 自建 fuzzer/verifier 當引擎（`Goal.md` §2）
- [x] 選定主場 dialect：`arith`（`Goal.md` §3）
- [x] 建立 repo 與 `Goal.md`
- [x] 安裝建置依賴
- [x] clone LLVM（blobless partial clone，保留完整 commit 歷史供找 reviewer 用）
- [x] cmake 配置成功
- [x] 掃描 `arith` 產出候選 patch 清單 → `notes/arith-patch-candidates.md`
- [x] 全部遷移到 WSL 原生檔案系統

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
