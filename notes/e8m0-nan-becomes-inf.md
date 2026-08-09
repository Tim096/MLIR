# `f8E8M0FNU` 的 NaN 在 constant folding 時變成 Infinity

發現日期：2026-08-08
基準：`llvm-project` @ `9ea23028e763`（本地 `arith-exhaustive-atomicrmwkind-switch` 分支之上）
起因：做 M1-b（`arith.scaling_extf` / `scaling_truncf` 折疊）時，探測邊界案例撞到的。
PR：[#214919](https://github.com/llvm/llvm-project/pull/214919)
面試講法（給不熟這個專案的人聽的版本）：`notes/e8m0-interview-qa.md`

---

## 一句話

`arith.extf` 把一個 `f8E8M0FNU` 的 NaN 常數折成 **+Infinity**，不是 NaN。
根因在 `llvm::APFloat::convert`，不在 MLIR。

---

## 症狀（可重現）

```mlir
func.func @e8m0_nan_to_f32() -> f32 {
  %c = arith.constant 0xFF : f8E8M0FNU     // E8M0 的 NaN 編碼是 all-ones
  %0 = arith.extf %c : f8E8M0FNU to f32
  return %0 : f32
}
```

```
$ mlir-opt x.mlir -canonicalize
%cst = arith.constant 0x7F800000 : f32     // ← +inf，不是 NaN
```

f16 得到 `0x7C00`、bf16 得到 `0x7F80`、f64 得到 `0x7FF0000000000000` —— 全都是 inf 的編碼。

**先確認 `0xFF` 真的是 NaN**（不是我誤讀編碼）：

```mlir
%c = arith.constant 0xFF : f8E8M0FNU
%0 = arith.cmpf ord, %c, %c : f8E8M0FNU    // 折成 false  → 是 NaN
%c2 = arith.constant 0xFE : f8E8M0FNU
%1 = arith.cmpf ord, %c2, %c2 : f8E8M0FNU  // 折成 true   → 是有限值 2^127
```

---

## 根因

`llvm/lib/Support/APFloat.cpp`：

```cpp
constexpr fltSemantics APFloatBase::semFloat8E8M0FNU = {
    127, -127, /*precision=*/1, /*sizeInBits=*/8,
    fltNonfiniteBehavior::NanOnly, fltNanEncoding::AllOnes, ...};
```

`precision = 1` 表示**沒有任何 significand 存放位元**（只有指數）。
`APFloat::hasSignificand()` 就是專門為它寫的：`return &Sem != &Float8E8M0FNU();`

於是在 `makeNaN()` 裡：

```cpp
fill_storage = APInt::getAllOnes(semantics->precision - 1);   // getAllOnes(0) → 空的
```

E8M0 的 NaN **payload 是 0 個位元**。

接著 `IEEEFloat::convert()` 走 `category == fcNaN` 的一般路徑：把 significand
左移 `toSemantics.precision - fromSemantics.precision` 位。0 左移還是 0。
結果是「指數 = NaN 指數、significand = 全 0」——在有 infinity 的目標格式裡，
**那正好是 infinity 的位元編碼**。

`APFloat` 物件內部 `category` 仍然是 `fcNaN`（所以 `isNaN()` 回 true），
但 `bitcastToAPInt()` 吐出 inf 的位元。MLIR 的 `FloatAttr` 存的就是這串位元，
所以折出來的常數是 inf。

C++ 層直接驗證（`APFloat::convert` 回報 `opOK` 且 `losesInfo == false`）：

```
src E8M0 0xFF : isNaN=1 bits=0xff
  -> f16  isNaN=1 isInf=0 bits=0x7c00      ← 修復前
  -> f32  isNaN=1 isInf=0 bits=0x7f800000  ← 修復前
```

同一段程式對 f16 qNaN → f32 的對照組是正常的（`0x7E00` → `0x7FC00000`），
所以問題只出在「來源格式沒有 significand」這一種。

---

## 修法

`llvm/lib/Support/APFloat.cpp`，`IEEEFloat::convert()` 的 `fcNaN` 分支裡，
接在既有的 `nanEncoding::NegativeZero` 修正之後：

```cpp
// If the source has no significand, there are no payload bits to carry
// over, and an all-zero significand would encode an Inf. Create a new NaN.
if (!APFloat::hasSignificand(fromSemantics))
  makeNaN(false, sign);
```

註解刻意寫短、句型對齊它正上方那段既有註解
（`// If NaN is negative zero, we need to create a new NaN to avoid converting NaN to -Inf.`），
因為那兩段做的是同一類事情：偵測某種來源格式會讓 NaN 掉成別的東西，就重建一個 NaN。

`makeNaN` 在 IEEE 目標上會設 QNaN bit，得到該格式的標準 qNaN。

上面那個 `nonFiniteBehavior::NanOnly` 的提前 return 已經處理了「目標也是 NanOnly」
的情形，所以這段只會在目標格式有 infinity 時執行。

只有 `semFloat8E8M0FNU` 的 `precision` 是 1（掃過整張 `fltSemantics` 表確認），
所以影響面就是 E8M0 → {f16, bf16, f32, f64, f128} 這一條。

---

## 驗證

**1. 窮盡掃描**（`APFloat` C++ 層，整個 8-bit 定義域）

256 個 E8M0 值 × 5 個目標格式（f16 / bf16 / f32 / f64 / f128），每個檢查：

- category 在轉換後不變
- NaN 不得變成 inf（category 層）
- NaN 的位元圖樣用目標語意讀回來仍然是 NaN（這才是 `FloatAttr` 真正存的東西）
- 有限值在指數範圍夠大的目標上必須無損，且轉回 E8M0 得到原值

修復後：`all checks passed (0 failures)`。
腳本在 `scratchpad/apf.cpp`（連 `libLLVMSupport.so` 編譯即可跑）。

**2. 測試在沒有修復時會失敗**（確認測試抓得到這個 bug）

把 `APFloat.cpp` 的修改 revert、重編 `libLLVMSupport.so`、重連 `ADTTests`：

```
Value of: APFloat(*Sem, bits).isNaN()
  Actual: false
Expected: true
[  FAILED  ] APFloatTest.Float8E8M0FNUNaNConvert
```

把修改放回去：186 個 `APFloatTest` 全過；`ADTTests` 全部 2187 個測試全過。

**3. 迴歸**

`ninja check-mlir`：3841 passed / 0 failed（修復前後都跑過）。

---

## 這題過 `Goal.md` §8.7 四關的情況

| 關卡 | 判定 | 依據 |
|---|---|---|
| ① 真實 AI pipeline 走得到 | ✅ | `f8E8M0FNU` 就是 OCP MXFP 的 block scale 型別；`ArithToAMDGPU`（MI300/MI355）、`XeGPUToXeVM` 都在用。NaN scale 在 MXFP 規格裡代表「這個 block 無效」 |
| ② JD 關鍵字 | ✅ | `quantization` / `mixed precision` / MXFP4-FP8 |
| ③ 能不看筆記答辯 | ✅ | 因果鏈短且完整：precision=1 → NaN payload 0 bit → 左移仍是 0 → 全零 significand + NaN 指數 = inf 編碼 |
| ④ 可驗證證據 | ✅ | 整個 8-bit 定義域窮盡掃描（不是抽樣），外加「拿掉修復測試就會紅」 |
| 撞車 | 無 | `E8M0+NaN`、`Float8E8M0FNU+convert` 兩組關鍵字搜 open PR / issue，沒有相關的 |

比 M1-b 原訂的「補折疊」強的地方：這是 **miscompile**（值算錯），不是「少一個最佳化」。

---

## 對 M1-b 的影響

原本規劃的 `scaling_extf` / `scaling_truncf` 折疊，語意是
「scale truncf 成 f8E8M0FNU → extf 成 result type → mulf」。
中間那個 extf 正是出問題的那一步，所以**這個 bug 必須先修，折疊才能建在正確的基礎上**。

順序：先送 APFloat 修復，再回頭做 M1-b 的折疊。

---

## M1-b 本身的探測結果（順手記下，還沒動工）

`-arith-expand -canonicalize` 會折，單獨 `-canonicalize` 不會折。也就是說：
**走 `ArithToAMDGPU` / `XeGPUToXeVM` 這種硬體 lowering 的 pipeline 拿不到這些折疊。**
這是第 1 關的具體證據。

| 案例 | `-canonicalize` | `-arith-expand -canonicalize` |
|---|---|---|
| `scaling_extf(%x, cst 1.0 : f8E8M0FNU)` | 不動 | `arith.extf %x` |
| `scaling_truncf(%x, cst 1.0)` + rounding/fastmath | 不動 | `arith.truncf %x toward_zero fastmath<fast>` |
| 兩個 operand 都是常數（scalar / vector） | 不動 | 折成常數 |
| scale = 2^127、result 是 f16 | 不動 | 不折（`convertFloatValue` 在溢位時放棄）—— 正確 |

**已知的語意分歧（折疊時要避開）**：
`ExpandOps` 把非 E8M0 的 scale 用 `truncf`（round-to-nearest）降成 E8M0；
`ArithToAMDGPU` 則是把 scale 轉成 f32 交給硬體，硬體只取指數欄位（等於截斷）。
scale = 1.6 : f16 時，前者得 2.0、後者得 1.0。
→ 折疊要限制在 **scale 的 element type 已經是 `f8E8M0FNU`** 的情況。
