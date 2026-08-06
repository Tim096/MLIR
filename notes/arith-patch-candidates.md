# `arith` 候選 patch 清單

掃描日期：2026-08-06
掃描基準：`llvm-project` @ `27f1aa4c9a42`（2026-08-06 的 main）

## 掃描方法

1. `grep -rn "TODO\|FIXME" mlir/lib/Dialect/Arith/ mlir/include/mlir/Dialect/Arith/`
2. 解析 `ArithOps.td`，列出每個 op 是否有 `hasFolder` / `hasCanonicalizer` / `hasVerifier`

## 掃描結論（重要）

**`arith` 的 folding 覆蓋率已經很高**：54 個 op 裡幾乎全都有 folder。
所以《Goal.md》§8.4 講的「找缺的 canonicalization」這條路，在 `arith` 裡**大部分已經被做掉了**。

唯二完全沒有 folder 也沒有 canonicalizer 的 op：
- `arith.scaling_extf`
- `arith.scaling_truncf`

（這兩個是較新的 microscaling 浮點格式相關 op，是唯一還空著的地方，值得看一眼有沒有
round-trip 之類的 fold 機會。）

真正的縫隙不在「缺 folder」，而在**既有 folder 裡被明確標註放棄的 case**。下面依難度排序。

---

## M0 級（目標是打通流程，不是做大事）

### 候選 1 ⭐ 收掉一個過期的 TODO，順便讓 switch 變 exhaustive

**位置**：`mlir/lib/Dialect/Arith/IR/ArithOps.cpp:3134` 與 `:3229`

兩個函式 `getIdentityValueAttr()` 與 `getReductionOp()` 的 switch 尾端都寫著：

```cpp
  // TODO: Add remaining reduction operations.
  default:
    (void)emitOptionalError(loc, "Reduction operation type not supported");
```

**查證結果**：`AtomicRMWKind` 共 16 個 case（`ArithBase.td:88-103`）。兩個 switch 各自
已覆蓋 15 個，唯一缺的是 **`assign`**。

而 `assign` 根本不是 reduction——它是 `x = y`，沒有單位元素、也沒有對應的二元 op。
所以這個 TODO 是**寫不完的**，它該被收掉而不是被補完。

**建議做法**：把 `default:` 換成顯式的 `case AtomicRMWKind::assign:`，讓 switch 變成窮盡的。
好處是**未來有人在 enum 加新 kind 時會得到編譯錯誤，而不是執行期才靜默地報錯**。
順手刪掉過期的 TODO。

- 難度：低
- 風險：低。屬於 NFC，commit title 要加 `[NFC]`
- 弱點：NFC 不好寫 test（LLVM 接受 NFC patch 不附 test）。所以**影響力小——但這正是 M0 要的**
- 提醒：送出前先確認沒有其他地方依賴 `default:` 的行為

### 候選 2 `arith.select` 改用 declarative assembly format

**位置**：`mlir/include/mlir/Dialect/Arith/IR/ArithOps.td:2064`

```tablegen
  // FIXME: Switch this to use the declarative assembly format.
  let hasCustomAssemblyFormat = 1;
```

- 難度：中。卡點是 `arith.select` 的型別語法有兩種形式（`vector<42xi1>, vector<42xf32>`
  與只有 `vector<42xf32>`），要處理 optional type，不是純機械替換
- 風險：中。改 assembly format 會牽動大量測試；也可能引發設計討論而讓 PR 卡住
- **不建議當 M0**，理由是卡住的機率不低，而 M0 的目的是快速走完一次流程

---

## M1 級（實質貢獻，有行為改變、寫得出 test）

### 候選 3 ⭐⭐ 解掉 upstream 明說「沒驗證」的 rounding mode 安全性問題

**位置**：`mlir/lib/Dialect/Arith/IR/ArithCanonicalization.td:562 / 575 / 588`

三個 pattern 都掛著同一句話：

```
// TODO: Verify if this canonicalization is safe when a rounding mode is
// specified. For the moment, bail on custom rounding modes.
```

也就是說 upstream 自己**不確定這些改寫在非預設 rounding mode 下是否保值**，
於是保守地讓它們在有 custom rounding mode 時直接放棄。

**這是整份清單裡跟本專案主軸最契合的題目**——這正是《Goal.md》§3 說的
「`arith` 的改寫規則是可以用 SMT 判定的命題」的實例，而且是 upstream 親口承認的未解問題。

三個 pattern 分別是：

| Pattern | 改寫 | 我的初步判斷 |
|---|---|---|
| `MulFOfNegF` | `mulf(negf x, negf y) → mulf(x, y)` | **可能是安全的** |
| `DivFOfNegF` | `divf(negf x, negf y) → divf(x, y)` | **可能是安全的** |
| `SubFOfNegZero` | `subf(-0.0, x) → negf(x)` | **可能是不安全的，疑似有反例** |

> ⚠️ 以下是我手推的論證，**尚未驗證**。這正是 M3/M4 工具該回答的問題，
> 在送 patch 前必須用實驗或 SMT 確認。

**為什麼 mul / div 可能安全**：`negf` 在 IEEE 754 下只翻轉符號位，是**精確運算**、不做捨入。
而 `(-x) × (-y)` 與 `x × y` 的**無窮精度真實值完全相同**。既然送進捨入的是同一個實數、
捨入模式也相同，結果就必然相同。除法同理。若成立，patch 就是拿掉那個
`default rounding mode` 的 constraint，並補上涵蓋各 rounding mode 的測試。

**為什麼 subf(-0, x) 可能不安全**——疑似反例：取 `x = -0.0`，rounding mode 為
round-toward-negative：
- IEEE 754 規定：當兩個同號運算元相減、結果恰為零時，該零的符號在所有捨入模式下是 `+0`，
  **唯獨 roundTowardNegative 下是 `-0`**。
- 於是 `(-0) - (-0)` 在 RTN 下得到 `-0`。
- 但 `negf(-0)` 是 `+0`。
- 兩者不一致 → 改寫在 RTN 下不保值。

（另外兩個零的情形我推過是相符的：`x = +0` 時兩邊在所有模式下都得 `-0`；
預設模式 RNE 下 `x = -0` 兩邊也都得 `+0`——所以**今天沒有實際 bug**，
因為 pattern 目前就是在 custom rounding mode 下放棄。）

**這題的價值**：即使結論是「不能放寬」，把反例與理由寫進註解、
讓後人不用再重推一次，也是實在的貢獻。而且它是 **M4 SMT 驗證器的第一個練習題**——
如果工具能自動吐出這個反例，那就是工具有效的第一個證據。

- 難度：中高（難在論證，不在寫 code）
- 風險：中。要準備好被浮點數專家挑戰，所以 PR description 必須嚴謹
- **強烈建議**：M0 完成、熟悉流程之後再碰這題

### 候選 4 `ceildivsi` 在 MININT 時折不掉

**位置**：`mlir/lib/Dialect/Arith/IR/ArithOps.cpp:991`

```cpp
  // TODO: This hook won't fold operations where a = MININT, because
  // negating MININT overflows. This can be improved.
```

實作用取負來處理 ceiling 除法，於是 `a = MININT` 時因為取負會溢位而整段放棄折疊。
可以改寫成不取負的算法。

- 難度：中。純 `APInt` 邊界處理，要對有號除法語意很小心
- 風險：低。自包含、好寫 test（直接在 `canonicalize.mlir` 加 MININT 的 case）
- 優點：**這是本清單裡「有實際行為改變 + 好寫 test + 不會引發設計爭論」的最佳平衡點**

### 候選 5 `arith.muli` 的 overflow TODO

**位置**：`mlir/lib/Dialect/Arith/IR/ArithOps.cpp:654`

```cpp
OpFoldResult arith::MulIOp::fold(FoldAdaptor adaptor) {
  // muli(x, 0) -> 0
  // muli(x, 1) -> x
  // TODO: Handle the overflow case.
```

推測是指 `nsw` / `nuw` overflow flag 的處理。**需要先搞清楚這個 TODO 到底想講什麼**，
再決定值不值得做。列在這裡是為了不遺漏。

- 難度：未知（需先調查）

---

## RFC 級（有設計爭議，不要當練習題）

### 候選 6 除以零 / 位移超界 → `poison`

**位置**：共 10 處
- `divui`(812) `divsi`(864) `ceildivui`(932) `ceildivsi`(974) `floordivsi`(1055)
  `remui`(1090) `remsi`(1126) → `(x, 0) -> poison`
- `shli`(2981) `shrui`(3008) `shrsi`(3039) → 位移量超過位寬時 `-> poison`

註解都寫著除以零是 UB、理應折成 poison，但目前沒做。MLIR 有 `ub` dialect 提供
`ub.poison`，技術上做得到。

**但這是跨越整個 dialect 的語意決策，幾乎確定需要先在 Discourse 發 RFC。**
不要當成第一批 patch——但它是《Goal.md》§M∞「發一篇 RFC」的**現成題目**，
先記在這裡。

---

## 建議路徑

```
候選 1（M0，打通流程，NFC）
   ↓
候選 4（M1 第一發，有實際行為改變，好寫 test）
   ↓
候選 3（M1 主菜，同時是 M4 工具的第一個驗證目標）
   ↓
候選 6（M∞，等有社群信用之後發 RFC）
```

## 待辦

- [ ] 逐一確認這些 TODO 是否已有他人開 PR 在做（避免撞車）：
      到 github.com/llvm/llvm-project/pulls 搜 `arith`
- [ ] 候選 3 的兩個論證需要實驗或 SMT 驗證，**不可直接當結論送出**
- [ ] 候選 5 需要先調查 TODO 的原意
- [ ] 看一眼 `scaling_extf` / `scaling_truncf` 有沒有 round-trip 之類的 fold 機會
