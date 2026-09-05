# #221384：`complex` 三個 fold 沒查 fastmath 就無條件做

分支 `complex-fold-fastmath`，base `f6a369fa4a57`，head `378e96fe4dfd`，2 個檔案 +74/−14。

## 問題

`ComplexOps.cpp` 的 `AddOp::fold`／`SubOp::fold`／`ExpOp::fold`：

- `complex.add(complex.sub(a, b), b) → a`、`complex.add(b, complex.sub(a, b)) → a`
- `complex.sub(complex.add(a, b), b) → a`
- `complex.exp(complex.log(a)) → a`

全部不看 `fastmath`。浮點下這些等式不成立：

- 中間結果會捨入：`a = 1.0, b = 1e30`，`(1.0 - 1e30) + 1e30 = 0.0`，不是 `1.0`。
- 帶號零：`a = -0.0, b = +0.0`，`(-0.0 - 0.0) + 0.0 = +0.0`，不是 `-0.0`。
- `exp(log(a))` 只是 `a` 的近似。

重現：兩個 SSA 參數丟進 `-canonicalize`，整個函式變 `return %a`。

## 修法（照 LLVM 的規則）

| fold | 要求 | LLVM 對應 |
|---|---|---|
| add／sub 那三個 | 外層 op 有 `reassoc` **且** `nsz` | `InstructionSimplify.cpp` `simplifyFAddInst`／`simplifyFSubInst`：`FMF.noSignedZeros() && FMF.allowReassoc()` |
| exp(log) | exp 與 log **都**有 `afn` | `SimplifyLibCalls.cpp` `optimizeLog`：`Log->isFast() && Arg->isFast()`（LLVM 要求全 fast，我只要 `afn`，比它鬆一點但語意對：afn 就是「允許用近似取代函式」） |

為什麼 `reassoc` 不夠要加 `nsz`：帶號零那個例子跟結合律無關，是零的符號被吃掉。LLVM 兩個都要，跟著要。

程式碼：`arith::bitEnumContainsAll(getFastmath(), reassoc | nsz)` 包住原本的判斷；exp 那個要查 `logOp.getFastmath()`。檔案裡 `DivOp::fold` 已經用同一個寫法查 `nnan`（#176249），風格對得上。

## 脈絡

- 三個 fold 是 lewuathe 2022 年加的（`036a6996750d`、`5148c685e3bb`），那時 complex 還沒有 `fastmath`（2023-08 才加）。
- 2026-08 Bryth 修了隔壁兩個：#212751 把 `add(a, +0) → a` 改成只認 `-0`，#212781 直接刪掉 `log(exp(a)) → a`（|Im| > π 就錯）。那兩個 PR 都是 JDPailleux approve。這題是同一批 fold 剩下的三個，PR body 寫「same direction as #212751/#212781」。
- `add(a, -0) → a`、`sub(a, +0) → a`、`neg(neg(a))`、`conj(conj(a))` 都是精確的，不用動。

## 測試

既有三個正向測試加上 flag（`fastmath<reassoc,nsz>`／`fastmath<afn>`），各補一個 `_without_fast_math`：只給 `reassoc`、只給 `nsz`、只給 exp 的 `afn`、什麼都不給，四種缺法各佔一個。注意 canonicalize 會把常數換到右邊，rhs 那個測試的 CHECK 要寫 `complex.add %[[SUB]], %{{.*}}`。

Complex／ComplexToStandard／ComplexToLLVM／Arith／Math 共 51 個 lit 全過。

## 答辯

- 「為什麼不直接刪掉」：有 flag 時這些 fold 是合法且有用的，arith 對 `addf(x, +0)` 也是有 `nsz` 才折，刪掉是過度反應。
- 「為什麼 exp/log 只要 afn 不要 fast」：LLVM 的 `isFast()` 是歷史包袱，`afn` 的定義就是這件事；如果 reviewer 要 `fast` 我可以改，一行。
- 「要不要也查內層 op 的 flag」：LLVM 只查外層（fadd／fsub 自己的 FMF），reassoc 授權的是「這個運算可以跟它的 operand 重新結合」。exp/log 例外，因為近似的是 log 那一步的結果。
