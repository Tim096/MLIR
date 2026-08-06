# ArithToSMT 探查 — 上游現況與我們的切入點

最後更新：2026-08-07　　worktree：`~/llvm-explore`（分支 `explore`）

> 起因：查 TODO.md 的 Q3 時發現「上游沒有 `ArithToSMT` conversion」，
> 判斷這是個夠份量又跟 M4 同向的題目。深入查證後發現**已經有人做了一半**——
> 但那半成品有可證明的錯誤。

---

## 1. 結論先講

| 問題 | 答案 |
|---|---|
| 上游有 `ArithToSMT` 嗎？ | **合併進 main 的：沒有。但有一個 open 的 draft PR #131484。** |
| 那個 PR 活著嗎？ | **實質上死了。** 2025-03-16 開的 draft，17 個月、**零留言零 review**。 |
| 誰開的？ | `makslevental`（Maksim Levental）——**同一個人**在 #131480 把 SMT dialect 上游化。 |
| 品質如何？ | 骨架合理，但 `ceildivsi` 的轉換**數學上是錯的**，而且**零測試覆蓋**。 |

⚠️ **這代表「上游完全沒有這東西」的判斷要修正。**
第一次掃只用 `ls mlir/lib/Conversion/ | grep -i smt` 看本地 source tree，
**看不到還沒 merge 的 PR**。
教訓：判斷「有沒有人做過」不能只看 source tree，一定要搜 open PR。

---

## 2. PR #131484 是什麼

`https://github.com/llvm/llvm-project/pull/131484` — 「[mlir][smt] add arith-to-smt」

- Draft，1 commit，8 檔，+498/-0，描述只有一句「see #131480」
- 檔案：`mlir/{include,lib}/Conversion/ArithToSMT/` + `mlir/test/Conversion/ArithToSMT/arith-to-smt.mlir`

**已覆蓋**：`constant(int)` `cmpi` `subi` `addi` `muli` `andi` `ori` `xori`
`shli` `shrui` `shrsi` `divsi` `divui` `remsi` `remui` `ceildivsi`

**未覆蓋**（我們若接手要補的）：`select` `extsi` `extui` `trunci` `index_cast`
`ceildivui` `floordivsi` `maxsi/minsi/maxui/minui` `addui_extended` 等，
以及 vector / tensor / `index` 型別、poison 語意。

幾個設計上還可以的地方：
- 除以零用 `smt.declare_fun` 產生無約束的符號值來模擬 UB——標準做法，合理
- `remsi → smt.bv.srem` 正確（兩者的餘數都取被除數的符號；取除數符號的是 `bvsmod`）
- type converter 對 `i1 ↔ smt.bool ↔ smt.bv<1>` 的來回轉換處理得算細

作者自己留的未解點：
- `// TODO(max): signed/unsigned/signless semenatics`（原文有 typo）
- type converter 註解裡對 poison 語意明顯沒想清楚：
  「the integer type also carries poison information (which we don't have in MLIR?)」

---

## 3. 🔴 已證實的缺陷：`CeilDivSIOpConversion` 算錯

### 3.1 它做了什麼

把 `ceildivsi(a, b)` 改寫成 **`(a + b - 1) / b`**，其中除法是 `arith.divsi`。

而且它**確實是活的**——在主轉換之前用獨立的 pre-pass 跑：

```cpp
RewritePatternSet patterns(&getContext());
patterns.add<CeilDivSIOpConversion>(&getContext());
walkAndApplyPatterns(getOperation(), std::move(patterns));
```

### 3.2 為什麼錯

`(a + b - 1) / b` 是**非負數**版本的 ceiling 除法恆等式，前提是除法要**往下取整 (floor)**。
但 `arith.divsi` 是**往零截斷 (truncate toward zero)**。
兩者只在被除數非負時一致，所以這個改寫只在 `a > 0 且 b > 0` 可靠。

### 3.3 實測（`mlir-opt --canonicalize` 常數折疊，10 取樣錯 6）

| a | b | `arith.ceildivsi`（正解） | PR 的 `(a+b-1)/b` | ExpandOps 公式 |
|---:|---:|---:|---:|---:|
| 7 | 2 | 4 | 4 | 4 ✅ |
| **7** | **-2** | **-3** | **-2** ❌ | -3 ✅ |
| -9 | 2 | -4 | -4 | -4 ✅ |
| **-9** | **-2** | **5** | **6** ❌ | 5 ✅ |
| 8 | 2 | 4 | 4 | 4 ✅ |
| **-8** | **-2** | **4** | **5** ❌ | 4 ✅ |
| **1** | **-3** | **0** | **1** ❌ | 0 ✅ |
| -1 | 3 | 0 | 0 | 0 ✅ |
| **5** | **-5** | **-1** | **0** ❌ | -1 ✅ |
| **-128** | **7** | **-18** | **-17** ❌ | -18 ✅ |

⚠️ **注意最後一列：`b > 0` 也會錯。**
所以「只有 `b < 0` 才錯」是不對的說法（我第一輪就是這樣誤判，取樣太少）。
準確講法：**只在 `a > 0 且 b > 0` 可靠**；其他象限只有剛好整除時才碰巧對。

重現腳本：`/tmp/.../scratchpad/cmp3.mlir`（產生器見本文件 git 歷史對應的 session）。
做法是同時算三種寫法再讓 `--canonicalize` 折疊，直接比常數。

### 3.4 上游早就有正確版本

`mlir/lib/Dialect/Arith/Transforms/ExpandOps.cpp:91`：

```
/// Expands CeilDivSIOp (a, b) into
/// z = a / b
/// if (z * b != a && (a < 0) == (b < 0)) {
///   return z + 1;
/// } else {
///   return z;
/// }
```

實測 10/10 全對。**PR 大可直接沿用這個既有實作，不必自己另寫一個錯的。**

### 3.5 而且零測試

`mlir/test/Conversion/ArithToSMT/arith-to-smt.mlir` 測了
divsi / divui / remsi / remui / subi / addi / muli / andi / ori / xori / cmpi——
**唯獨沒有 `ceildivsi`**。所以這個錯誤從來沒被任何測試碰到過。

---

## 4. 這跟我們的 M1 有什麼關係

**ExpandOps 那個正確公式，跟我們在
[`ceildivsi-minint-analysis.md`](ceildivsi-minint-analysis.md) §6 獨立推導出來的演算法
結構完全一致**（先 `sdiv`，再依「有餘數且同號」決定 +1）。

也就是說：我們那份 M1 分析的核心演算法，**被上游自己的既有實作背書了**。
這在寫 M1 的 PR 描述時是很有力的一句——不是我們發明的新算法，
是把 `ExpandOps` 已經在用的正確做法，補進 folder 裡。

---

## 5. 可能的下一步（尚未決定，需要人決策）

按「侵入性」由低到高：

**A. 在 PR #131484 留一則有憑有據的 review 意見。**
成本低、訊號好：具體反例 + 上游既有正解的位置 + 指出零測試。
對一個 17 個月沒人看的 draft，這是有實質幫助的。
⚠️ 這是對外公開動作，要先問過本人。而且**是 draft，語氣要拿捏**——
作者知道它沒完成，重點該放在「我想看到這個 landing，這裡有個具體問題」，
不是「你寫錯了」。

**B. 徵得作者同意後接手完成。**
若作者無意繼續，這是很理想的 M2/M3 級題目：範圍清楚、有現成骨架、
而且做完就直接是 M4 驗證器的地基。禮貌上必須先問，不能直接另開 PR 蓋過去。

**C. 完全自己重做。** 最沒禮貌，除非作者明確放棄，否則不該走。

**建議走 A**，看作者反應再決定要不要 B。

---

## 6. 對 M4 的影響

原本 TODO.md Q3 的結論是「要自己從零寫 ArithToSMT」。修正為：
**有一份 498 行的骨架可以當起點**，但要修正錯誤、補齊 op 覆蓋、加測試。
工作量比從零小，但比「直接拿來用」大很多——尤其 poison / signless 語意
作者自己都標了 TODO 沒解決，那才是真正難的部分。
