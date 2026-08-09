# 三個掛著 rounding mode TODO 的 canonicalization — 分析

最後更新：2026-08-08　　狀態：**已用 z3 的 IEEE-754 浮點理論證明**（f16 / f32 / f64 三種寬度）

> 這份筆記回答 `TODO.md` 的 **Q1**。原本那三列「初步判斷」是手推的，
> 現在有機器證明，結論**與手推完全相符**。
>
> 證明腳本：`notes/rounding-mode-proofs/`

相關檔案：
- pattern 定義：`mlir/lib/Dialect/Arith/IR/ArithCanonicalization.td`
  - `SubFOfNegZero`（~:563）
  - `MulFOfNegF`（~:576）
  - `DivFOfNegF`（~:589）

---

## 1. 一句話

三個 pattern 掛著同一句 upstream 自己寫的 TODO：

```
// TODO: Verify if this canonicalization is safe when a rounding mode is
// specified. For the moment, bail on custom rounding modes.
```

答案是：**mul / div 安全，subf 不安全**，而且 subf 的不安全只由**單一一組輸入**造成。

## 2. 為什麼「放寬」在程式碼上是一行

三個 pattern 的改寫式**本來就把 `$rm` 原封不動傳給結果**：

```tablegen
def MulFOfNegF :
    Pat<(Arith_MulFOp (Arith_NegFOp $x, $_), (Arith_NegFOp $y, $_), $fmf, $rm),
        (Arith_MulFOp $x, $y, $fmf, $rm),          // ← $rm 照原樣帶過去
        [(TypesMatch $x, $y),
         (Constraint<CPred<"$0 == nullptr">, "default rounding mode"> $rm)]>;
```

所以「允許 custom rounding mode」＝**刪掉最後那行 constraint**，不需要動改寫邏輯。
這也是為什麼這個 TODO 值得做：真正的成本全在**論證**，不在實作。

## 3. mul / div 為什麼安全（要能不看筆記講出來）

三步：

1. **`negf` 是精確運算。** 它只翻符號位，不做任何捨入，所以它**不看 rounding mode**
   （ODS 裡 `arith.negf` 也確實只有 fastmath、沒有 rounding mode 參數）。
2. **翻兩個符號，實數乘積不變。** `(-x) × (-y)` 與 `x × y` 的**無窮精度真值完全相同**。
   除法同理：`(-x) / (-y)` 與 `x / y` 真值相同。
3. **IEEE-754 的 mul / div 是 correctly rounded**：結果 = `round_rm(真值)`。
   既然送進捨入的是同一個實數、捨入模式又是同一個，結果必然逐位元相同。

特殊值也一併成立，因為 IEEE 的特殊值規則對「兩個運算元同時翻號」是對稱的：
`(-inf) × (-y) = inf × y`、`(-0) × (-0) = +0 = 0 × 0`、NaN 兩邊都是 NaN。

**注意 NaN 的符號位不必相符也沒關係**——SMT 的浮點理論把所有 NaN 視為同一個值，
而 IEEE 也不保證 NaN 的符號位，MLIR 這裡同樣不依賴它。

## 4. subf 為什麼不安全

`subf(-0.0, x) → negf(x)`。

除了 `x` 是零的情形，`(-0) - x` 的真值就是 `-x`，而 `-x` 一定可表示（只是翻符號位），
**沒有捨入發生**，所以兩邊相同。問題全部集中在 `x` 是零的時候：

| `x` | `(-0) - x` | `negf(x)` | 相符？ |
|---|---|---|---|
| `+0` | `-0`（所有模式） | `-0` | ✅ |
| `-0`，非 RTN | `+0` | `+0` | ✅ |
| `-0`，**roundTowardNegative** | **`-0`** | `+0` | ❌ |

關鍵是 IEEE-754 那條規則：**兩個同號運算元相減、結果恰為零時，
該零的符號在所有捨入模式下是 `+0`，唯獨 roundTowardNegative 下是 `-0`。**

所以反例是：`x = -0.0`、`rm = roundTowardNegative`。

### 今天沒有實際 bug

因為 pattern 現在就是在 custom rounding mode 下放棄。
預設模式（RNE）下 `x = -0` 兩邊都得 `+0`，相符。
**這是「不能放寬」的證據，不是「現在有錯」的證據**——寫 PR 描述時不要講成後者。

## 5. 證明

用 z3 的 `QF_FP`（IEEE-754 理論）。`rm` 宣告成**自由變數**，所以是對**所有**捨入模式一次證完，
不是逐一列舉。

```smt2
; mul：找得到反例嗎？
(set-logic QF_FP)
(declare-const x Float32)
(declare-const y Float32)
(declare-const rm RoundingMode)
(assert (not (= (fp.mul rm (fp.neg x) (fp.neg y)) (fp.mul rm x y))))
(check-sat)     ; → unsat
```

`unsat` = 「找不到任何 `x, y, rm` 讓兩邊不同」= **改寫在所有捨入模式下保值**。

用 `=` 而非 `fp.eq` 是刻意的：`=` 是值相等（`+0 ≠ -0`），
`fp.eq` 會把 `+0` 和 `-0` 視為相等，那樣會**漏掉我們正要找的那個反例**。

### 結果

| 型別 | `MulFOfNegF` | `DivFOfNegF` | `SubFOfNegZero`（排除 `x=-0` ∧ RTN 後） |
|---|---|---|---|
| `Float16` | unsat ✅ | unsat ✅ | unsat |
| `Float32` | unsat ✅ | unsat ✅ | unsat |
| `Float64` | unsat ✅ | unsat ✅ | unsat |

subf 那欄是**反向的用法**：先讓 z3 自己吐出反例（`sat`，給出 `x = -zero`、
`rm = roundTowardNegative`），再把那一組排除掉重跑 → `unsat`。

這代表**整個輸入空間裡就只有這一組反例**，不是一整類。
這件事很重要：它讓「為什麼不能放寬」的註解可以寫得非常具體。

## 6. 建議的 patch 形狀

一個 PR 解掉同一句 TODO 的三個出處：

1. **`MulFOfNegF` / `DivFOfNegF`**：刪掉 `default rounding mode` constraint 與 TODO，
   補上各捨入模式的 lit test。
2. **`SubFOfNegZero`**：constraint **保留**，但把 TODO 換成實際的反例與理由——
   讓後人不必再推一次。

論述的重點是：這不是「我猜它安全」，是「upstream 問了一個問題，這裡是答案，
連反例都給你」。§5 的腳本 reviewer 可以自己跑。

## 7. ⚠️ 撞車查證的結果：這題不能照 §6 直接送

**PR [#209287](https://github.com/llvm/llvm-project/pull/209287)
`[mlir][arith][RFC] Add new strict FP handling in Arith`（`andykaylor`，2026-07-14 開）
動到的正是這三個 pattern。**

它替每個浮點 op 加了一個 `$fenv`（floating-point environment）運算元，
三個 pattern 都改成同時 bail：

```tablegen
def MulFOfNegF :
    Pat<(Arith_MulFOp (Arith_NegFOp $x, $_), (Arith_NegFOp $y, $_), $fmf, $rm,
                      $fenv),
        (Arith_MulFOp $x, $y, $fmf, $rm, $fenv),
        [(TypesMatch $x, $y),
         (Constraint<CPred<"$0 == nullptr">, "default rounding mode"> $rm),
         (Constraint<CPred<"$0 == nullptr">,
                     "default floating-point environment"> $fenv)]>;   // ← 新增
```

**而且那句 TODO 被原封不動留著。**

更關鍵的是 PR 描述裡這句：

> This is intended to **replace the existing rounding-mode handling** in the Arith
> dialect. I have left the old handling in place here but added comments that it
> should be considered **deprecated**.

### 這代表什麼

1. **一定會有文字衝突。** 我們改那三行，跟 #209287 改同樣那三行。
2. **論述前提可能被抽掉。** 對一個上游打算 deprecate 的機制送「放寬」patch，
   reviewer 很合理會回「這個要被換掉了，別花力氣」。
3. 但 **#209287 自己也還沒被接受**（RFC 階段，作者說 "If this direction is accepted"），
   而且 2026-07-14 之後就沒動靜。

### 我們的結果反而對那個 PR 有價值

因為 #209287 **保留了 TODO，還多加了一道 bail**——代表作者也沒去驗證這件事。
我們手上有的東西正好補這個缺：

- mul / div 在**所有捨入模式**下保值（z3 證明，三種寬度）
- subf 的反例是**唯一的一組**（`x = -0.0` ∧ RTN）

**另外還有一個 §3–§4 沒涵蓋、但因為 `$fenv` 才浮現的獨立理由：**
`$fenv` 管的不只捨入，還有**例外旗標**。而 `negf` 依 IEEE-754 是
non-arithmetic 運算，**對 signaling NaN 不引發 invalid**；`subf(-0, x)` 會。
所以 `SubFOfNegZero` 在嚴格例外語意下**還有第二個、與 `-0` 無關的不安全理由**。
⚠️ 這一條是推導，**尚未用 z3 驗**（SMT-LIB 的 FP 理論不建模例外旗標，
要驗得換方法）。

### 建議的走法（**對外動作，送出前要本人確認**）

不要照 §6 直接開 PR。改成先在 #209287 留一則有憑有據的意見：
帶上 z3 腳本、mul/div 的 unsat、subf 的唯一反例、以及 sNaN 那條。

理由：那是**別人正在推的設計**，我們提供的是他缺的驗證。
這比在他底下開一個會衝突的 PR 有價值，也符合 `Goal.md` M∞（RFC 參與）的方向。
若 #209287 最後沒被接受，§6 的 patch 形狀隨時可以拿回來用。

## 8. 還沒確認的事

- [ ] `arith.mulf` / `divf` 的 rounding mode 在**下游真的被尊重**嗎？
      （若某條 lowering 路徑根本忽略 `rm`，論述要提到）
- [ ] pattern 把兩個 `negf` 的 fastmath flag（`$_`）丟掉了——這是既有行為，
      但 reviewer 可能會問，要有答案
- [ ] lit test 怎麼寫出帶 rounding mode 的 `arith.mulf`（assembly format 要照 ODS 查）
- [ ] sNaN / 例外旗標那條要怎麼驗（z3 的 QF_FP 不建模例外）
