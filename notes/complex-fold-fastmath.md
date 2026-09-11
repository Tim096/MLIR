# #221384：`complex` 三個 fold 沒查 fastmath 就無條件做

09-11：matteo-rm（complex dialect 近期主要貢獻者，#212199／#213259 作者）09-07 review 四點，已全部處理，fixup commit `eb99a882d843`。

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
| exp(log) | exp 有 `reassoc`（09-11 改，原本是兩邊 `afn`） | `InstructionSimplify.cpp:6660` `simplifyUnaryIntrinsic`：`case Intrinsic::exp: if (FMF.allowReassoc() && match(Op0, m_Intrinsic<Intrinsic::log>(...))) return X;`。第一版引的 `SimplifyLibCalls.cpp` `optimizeLog` 是 `log(exp)` 那條，引錯地方 |

為什麼 `reassoc` 不夠要加 `nsz`：帶號零那個例子跟結合律無關，是零的符號被吃掉。LLVM 兩個都要，跟著要。

程式碼：`arith::bitEnumContainsAll(getFastmath(), reassoc | nsz)` 包住原本的判斷；exp 那個只查自己的 `reassoc`，不看 log。檔案裡 `DivOp::fold` 已經用同一個寫法查 `nnan`（#176249），風格對得上。

## 脈絡

- 三個 fold 是 lewuathe 2022 年加的（`036a6996750d`、`5148c685e3bb`），那時 complex 還沒有 `fastmath`（2023-08 才加）。
- 2026-08 Bryth 修了隔壁兩個：#212751 把 `add(a, +0) → a` 改成只認 `-0`，#212781 直接刪掉 `log(exp(a)) → a`（|Im| > π 就錯）。那兩個 PR 都是 JDPailleux approve。這題是同一批 fold 剩下的三個，PR body 寫「same direction as #212751/#212781」。
- `add(a, -0) → a`、`sub(a, +0) → a`、`neg(neg(a))`、`conj(conj(a))` 都是精確的，不用動。

## 測試

既有三個正向測試加上 flag（`fastmath<reassoc,nsz>`／exp 的 `fastmath<reassoc>`），各補一個 `_without_fast_math`：只給 `reassoc`、只給 `nsz`、`reassoc` 放在 log 不放在 exp、什麼都不給，四種缺法各佔一個。09-11 起 operand 全改成函式引數（matteo-rm 的 nit）：常數會被 canonicalize 換邊，引數不會，CHECK 就能寫死 `%[[A]]`／`%[[B]]`。

Complex／ComplexToStandard／ComplexToLLVM／Arith／Math 共 51 個 lit 全過。

## 答辯

- 「為什麼不直接刪掉」：有 flag 時這些 fold 是合法且有用的，arith 對 `addf(x, +0)` 也是有 `nsz` 才折，刪掉是過度反應。
- 「為什麼 exp/log 是 `reassoc` 不是 `afn`」：matteo-rm 09-07 指出 `afn` 不夠：`log((NaN, 1.0))` 的虛部是 `atan2(1, NaN)` = NaN，不折得 (NaN, NaN)，折了得 (NaN, 1.0)；零和 inf 同理，log 在那裡沒有有限值。`afn` 只授權「用近似取代函式」，管不到定義域。LLVM 實數版 `exp(log(x))` 只查 exp 的 `reassoc`（`InstructionSimplify.cpp:6660`），x < 0 時同樣把 NaN 折成 x，所以 `reassoc` 在 LLVM 的慣例裡就涵蓋這件事。回覆裡留了退路：他要更嚴可以再加 `nnan`／`ninf`。
- 「要不要也查內層 op 的 flag」：matteo-rm 09-07 也問了這題。LLVM 只查外層：`simplifyFAddInst` 查 `FMF.noSignedZeros() && FMF.allowReassoc()` 後直接 match 內層 `fsub`，不看它的 flag（`InstructionSimplify.cpp:6061`）。reassoc 授權的是「這個運算可以跟它的 operand 重新結合」。arith dialect 的 folder 沒有任何 `reassoc` 用法可比。回覆說明了這點並表示他要加也可以。
- 第一版錯在哪：exp/log 那條引了 `SimplifyLibCalls.cpp` `optimizeLog`（那是 `log(exp)`，且它要求 `isFast()`），把「兩邊都 fast」翻成「兩邊都 afn」。正確的對應是 `InstructionSimplify.cpp` 的 `exp(log(x))`，只查 exp 的 `reassoc`。教訓：引 LLVM 規則前先確認方向（exp(log) 與 log(exp) 是兩條不同規則）。
