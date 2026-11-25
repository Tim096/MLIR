# Review 草稿一批：#233860、#245655、#245951、#233536

狀態：#245655 於 2026-11-25 已貼（pullrequestreview-6057468062）；#233860、#245951、#233536 未貼。

本機分支 `review/batch-1125`（`376f04dd8bdb`＋自己的 `31ad4548426c`＋四個 PR 的 diff，一次 build）。
四個 PR 的 lit 測試一起跑：`mlir/test/Dialect/{Arith,EmitC}`、`Conversion/{ArithToLLVM,ArithToEmitC}`、新增的 integration 測試，共 54 個全過。
驗證腳本：`scratchpad/batch/verify.py`、`mm.py`。

---

## #233860 `[mlir][arith] fold valid int2fp2int round trips for canonicalizations`（dashygo097，+133/−2，零 review）

白話：`fptosi(sitofp(x))`（整數轉浮點再轉回整數）在浮點格式放得下所有整數值時，直接換回 `x`。

查證：
- 整數寬度 1～13 × 14 種浮點型別（含 f4／f6／f8 系列）× 有號／無號，共 364 組。PR 會折的有 159 組。
- 對這 159 組，把該寬度的**每一個**整數值做 `XitofP` 再 `fptoXi` 到較寬的整數（寬度不同，PR 的 fold 不會介入），常數折疊後每個值都原樣回來。零反例。
- diff 裡留著 `// NOTE: TO BE WRITTEN` 的區塊標題；另外刪了 `NarrowExtremum` 前後兩個空行，與本改動無關。

要貼的內容：

I ran this locally and the tests pass. To check the exactness condition I took every pair it accepts for integer widths 1 to 13 and 14 float types (159 pairs, including the f4/f6/f8 formats) and constant-folded the round trip for every value of the integer type, through a wider result type so that this fold does not apply. Every value comes back unchanged.

Two small things: the new section header still says `NOTE: TO BE WRITTEN`, and the two blank-line removals around `namespace {` near `NarrowExtremum` are unrelated to this change.

#233536 adds `isExactIntToFPCast` with the same precision and exponent test. Whichever lands second could reuse the other's helper.

---

## #245655 `[mlir][Arith] Add xori(cmpf, true) canonicalization`（matteo-rm，+204/−2，零 review）

白話：`not(a < b)` 直接改成一個相反的比較。浮點有 NaN，所以 `<` 的相反是「大於等於**或無序**」（`uge`），不是 `oge`。

查證：
- 16 個 predicate 逐一餵進 PR 的 pattern，讀出它換成哪個 predicate。
- 對每一對（原 predicate、換成的 predicate），在 {1.0, 2.0, NaN} 的 9 組輸入上常數折疊：兩個結果每次都相反。零反例。
- `fastmath<nnan>` 會帶到新的 `cmpf`；向量的 `dense<true>` 不會折（跟既有的 `cmpi` 版一樣）；`cmpf` 有別的 use 時會多留一個 `cmpf`（也跟 `cmpi` 版一樣）。

要貼的內容：

I ran this locally and the tests pass. I also checked the predicate table: for each of the 16 predicates I constant-folded `cmpf p` and `cmpf invertPredicate(p)` on every pair from {1.0, 2.0, NaN}, and the two results are complementary in all cases. LGTM.

---

## #245951 `[mlir][arith] Preserve signed zeros in floating-point min/max expansion`（yuanyiboyyb，+236/−15，零 review，標 `Assisted-By: GPT-6.1`）

白話：`maximumf(+0, -0)` 應該是 `+0`，原本的展開會回傳 `-0`。PR 多加一段：兩邊相等時看正負號來挑。

查證：
- {+0, −0, 1, −1, NaN, +inf, −inf} 的 49 組輸入 × max／min 共 98 個結果，用 `mlir-runner` 實跑，展開版與直接降成 `llvm.maximum`／`llvm.minimum` 的版本逐 bit 比對（NaN 只比是不是 NaN）：零差異。
- 展開從 4 個 op 變 11 個，會產生 `math.copysign`；動態形狀的 tensor 另外產生 `tensor.dim`＋`tensor.splat`。
- **unranked tensor 退步**：`arith.maximumf` on `tensor<*xf32>` 原本可以展開（`cmpf`＋`select` 不需要常數；同一個 binary 上 `maxnumf` 仍可展開，舊的 `maximumf` 程式碼就是那四個 op）。套 PR 後 pattern 直接 bail，`-arith-expand=include-min-max-f=true` 報 `failed to legalize operation 'arith.maximumf'`。

要貼的內容：

I ran this locally and the tests pass. I also compared the expansion with the `llvm.maximum`/`llvm.minimum` lowering in `mlir-runner` on every pair from {+0, -0, 1, -1, NaN, +inf, -inf}: the 98 results have the same bits (NaN payloads aside).

One regression: unranked tensors. Before this change the expansion needed no constants, so this went through:

```mlir
func.func @u(%a: tensor<*xf32>, %b: tensor<*xf32>) -> tensor<*xf32> {
  %r = arith.maximumf %a, %b : tensor<*xf32>
  return %r : tensor<*xf32>
}
```

With the patch, `-arith-expand=include-min-max-f=true` fails with `failed to legalize operation 'arith.maximumf' that was explicitly marked illegal`. `arith.maxnumf` on the same type still expands.

---

## #233536 `[mlir][arith] Only fold truncf(sitofp(x)) to sitofp(x) when the first conversion is exact`（kodlan，+107/−4，零 review，11-23 ping 過 kuhar）

白話：整數→寬浮點→窄浮點，原本一律化簡成整數→窄浮點。但第一步如果放不下（要捨入），兩步會捨入兩次，結果可能跟一步不同。PR 加條件：第一步保證精確才化簡。

查證（`scratchpad/batch/vb.py`、`e8.mlir`）：
- 整數寬度 1～12 ×（寬浮點、窄浮點）所有組合（14 種浮點型別）× 有號／無號，共 1632 組；PR 會折 1169 組、保留 463 組。
- 會折的 1169 組裡，490 組兩邊都能常數折疊：每個整數值的兩步結果＝一步結果，零差異。**其餘 679 組比不了**（`truncf` 的常數折疊遇到會失真的值就不折），沒有驗到。
- **角落情況：中間型別是 `f8E8M0FNU`**（沒有零、沒有負數）。`isExactIntToFPCast` 對 `i1` 與有號 `i2` 回傳 true，所以 `truncf(sitofp(%x : i2) : f8E8M0FNU) : f6E3M2FN` 被折成 `sitofp %x : i2 to f6E3M2FN`。但 0、−1、−2 在 `f8E8M0FNU` 都表示不了：常數折疊把 `sitofp 0` 變成 `5.877470e-39`，負數則不折。#233860 用同一組精度／指數條件，另外多查 `semanticsHasZero` 與 `semanticsHasSignedRepr`。
- 沒有量到這個角落在執行期會算出不同的值（兩步那條路徑的常數折疊不折，沒有可比的數字）。

要貼的內容：

I ran this locally and the tests pass. For integer widths 1 to 12 and every (wider, narrower) pair out of 14 float types I compared the two-step and the one-step conversion by constant folding every value. Wherever the fold applies and both sides fold (490 pairs), they agree.

One corner: `f8E8M0FNU` as the intermediate type. It has no zero and no negative values, but `isExactIntToFPCast` accepts `i1` and signed `i2`, so this is folded to `sitofp %x : i2 to f6E3M2FN`:

```mlir
func.func @s(%x: i2) -> f6E3M2FN {
  %0 = arith.sitofp %x : i2 to f8E8M0FNU
  %1 = arith.truncf %0 : f8E8M0FNU to f6E3M2FN
  return %1 : f6E3M2FN
}
```

0, -1 and -2 are not representable in `f8E8M0FNU` (the constant folder turns `sitofp 0` into `5.877470e-39` and does not fold the negative ones). #233860 has the same precision and exponent test and also checks `APFloat::semanticsHasZero` and `semanticsHasSignedRepr`; those two checks would cover it here as well.
