# TODO / 現況快照

> **這份文件的用途**：接續工作用的交接文件。
> 換一個 session、換一台機器、或隔了一個月回來，讀這份就能接上，不必翻聊天紀錄。
>
> 分工：
> - **`Goal.md`** = 為什麼這樣做（策略、決策、MLIR 背景知識、貢獻 SOP）——**改動頻率低**
> - **`TODO.md`**（本檔） = 現在在哪、下一步做什麼、有什麼還沒確認——**每次有進展就更新**
>
> 新 session 開場建議直接說：「讀 Goal.md 和 TODO.md，然後接續」。

最後更新：2026-08-07

---

## 一句話現況

🎉 **M0 的 PR 已送出：https://github.com/llvm/llvm-project/pull/214622**
（2026-08-07 開，等 review 中。reviewer 自動指派到 **`kuhar` = Jakub Kuderski**，
`ArithOps.cpp` 的第一大作者，最理想的人選。）

**現在開始 M1 第一發：`ceildivsi` 的 MININT folding gap。**

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

- [ ] **M1 第一發：`ceildivsi` MININT folding gap** ← **現在做這個**
      見下面「下一步」與 [`notes/ceildivsi-minint-analysis.md`](notes/ceildivsi-minint-analysis.md)

- [ ] **等 M0 的 review** — PR #214622，無需動作，等 `kuhar` 回應。
      一週沒動靜再禮貌 ping 一次。

- [ ] **決定 ArithToSMT 要怎麼走** — 見 `notes/arith-to-smt-exploration.md` §5。
      建議：先在 PR #131484 留一則有憑有據的意見（具體反例＋上游既有正解位置＋
      指出零測試），看作者反應再決定要不要徵求接手。
      ⚠️ 對外公開動作，送出前要本人確認。

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
第一次跑沒加，Claude Code session 結束時整個 build 被帶走。
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

### 3. M1 第一發 — `ceildivsi` 的 MININT folding gap

`mlir/lib/Dialect/Arith/IR/ArithOps.cpp:973`（`CeilDivSIOp::fold`，TODO 在 :991）。
實作用取負來做 ceiling 除法，於是 `a = MININT` 時因取負溢位而整段放棄折疊。

> 📄 **完整分析已寫成 [`notes/ceildivsi-minint-analysis.md`](notes/ceildivsi-minint-analysis.md)。
> 動手前讀那份，不要只看這裡的摘要。**（裡面所有結論目前都還是推導，尚未實測。）

摘要三點：

1. **這不是 miscompile，是漏折。** 現行行為正確、只是保守。歷史上的 miscompile 是
   issue #89382，已用「溢位就 bail」修掉——洞只是從「算錯」降級成「漏折」。
2. **upstream 自己說這該修。** 除了 `ArithOps.cpp` 的 TODO，
   `constant-fold.mlir:487` 的測試裡也寫著
   `// TODO: The folder should be able to fold the following by avoiding
   intermediate operations that overflow.`
   ——**測試檔本身就記著這些 case 應該要能折疊**。這不是提新設計，是完成既有意圖。
3. **範圍比原本以為的大。** 原始 TODO 只提 `a = MININT`，但 `b = MININT`
   同樣會漏折（如 `ceildivsi(7, -128) : i8` 答案是 `0`，放得下卻不折）。
   `b` 側沒有任何人記錄過，**這是我們比舊 PR #90855 做得完整的地方**。

⚠️ 這個 patch **會動到既有測試** `@simple_arith.ceildivsi_overflow`
（它現在斷言 MININT 不折疊）。PR 描述要主動點名，別讓 reviewer 自己發現。

**舊 PR #90855 是機會不是撞車** — 停擺兩年、base 漂掉，卡在 reviewer
**banach-space（Andrzej Warzyński）** 要求的分析始終沒補上。詳見筆記 §8。

**Reviewer 候選**（`git log --format='%an' -- <file> | sort | uniq -c | sort -rn`）：
Jakub Kuderski (21)、Ivan Butygin (7)、Victor Perez (6)、Mehdi Amini (6)、
Matthias Springer (5)、**Andrzej Warzyński (5) ← 這題直接找他**

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
