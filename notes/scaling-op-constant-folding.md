# M1-b：`arith.scaling_extf` / `scaling_truncf` 的常數折疊

> 這份文件的用途：**讓你不看筆記也能回答 reviewer**。
> 不是存檔，是答辯稿。每一節的標題就是 reviewer 可能問的問題。

分支：`arith-scaling-fold`，基準 `main` = `27f1aa4c9a42`（與前三發同一個基準）。
狀態：**實作完成，驗證中**。

---

## 1. 這兩個 op 是什麼？（一句話版本）

MXFP（microscaling）低精度推論的**反量化 / 量化** op。

一個 block（通常 32 個元素）共用一個 8-bit 的指數 scale（`f8E8M0FNU`），
元素本身存成 4-bit（`f4E2M1FN`）或 8-bit。

- `scaling_extf(in, scale)` = 反量化：把 4-bit 值乘上 `2^scale` 還原成 f16/f32
- `scaling_truncf(in, scale)` = 量化：把 f32 除以 `2^scale` 再壓成 4-bit

`f8E8M0FNU` **只有指數、沒有符號也沒有尾數**，所以它存的就是一個 2 的冪次。
這件事是後面所有推理的基礎。

---

## 2. 為什麼這是個縫隙？（第 1 關的具體證據）

實測，不是推測。同一份輸入跑兩條 pipeline：

```bash
mlir-opt scaling-probe.mlir -canonicalize                 # 七個案例全部原封不動
mlir-opt scaling-probe.mlir -arith-expand -canonicalize   # 常數案例全部折成常數
```

**意義**：折疊能力只存在於「先展開成 `extf`/`mulf`/`divf`/`truncf`」的路徑上。
但走硬體的 pipeline（`ArithToAMDGPU` → MI300/MI355、`XeGPUToXeVM` → Intel）
**不會展開**——它們直接把 scaling op 降成硬體指令。
那條路上，常數運算就一路留到後端。

`arith` 全部 54 個 op 裡，這兩個是**唯二完全沒有 folder 也沒有 canonicalizer 的**。
`canonicalize.mlir` 與 `constant-fold.mlir` 對它們的覆蓋率是 **0**。

---

## 3. 折疊成什麼？為什麼是這個答案？

**不是我發明的語意**——直接複製 `ExpandOps.cpp` 已經在做的展開：

| op | 展開鏈（`ExpandOps.cpp`） |
|---|---|
| `scaling_extf(in, scale)` | `mulf(extf(in), extf(scale))` |
| `scaling_truncf(in, scale)` | `truncf(in / extf(scale))` |

⚠️ **兩者不對稱，這是最容易答錯的地方**：

- `scaling_extf` 把 scale 加寬到**結果**型別
- `scaling_truncf` 把 scale 加寬到**輸入**型別

理由用想的就通：truncf 的除法要在還沒壓縮的寬型別上做，所以 scale 得配合輸入；
extf 的乘法發生在已經加寬之後，所以 scale 配合結果。

---

## 4. 為什麼有些情況故意不折？

三種，每一種都有上游既有的依據，不是我的保守偏好。

### 4.1 轉換有損就不折

`convertFloatValue()`（`ArithOps.cpp`）在 `losesInfo` 時回傳 `failure`。
`ExtFOp::fold` / `TruncFOp::fold` 都是這樣用的，而且 `canonicalize.mlir` 裡
`@truncFPConstantRounding` 這個既有測試的註解就直說
「Test that cases with rounding are NOT propagated」。

我照抄這條慣例。**推論**：`roundingmode` 屬性因此對折疊結果沒有影響
——會折的都是無損的，無損就與捨入模式無關。上游自己的
`@truncFPDownwardConstant` 等六個測試也全部用 `1.0` 這種精確值，同一個道理。

### 4.2 scale 不是 `f8E8M0FNU` 就不折

`ExpandOps` 對 f16/f32 的 scale 是**先 truncf 成 `f8E8M0FNU`**（取最接近的 2 的冪）；
`ArithToAMDGPU` 則是**直接讀它的指數欄位**。兩者對 `scale = 1.6 : f16` 會給出
不同答案（2.0 vs 1.0）。

這是上游尚未解決的不一致。**折疊不該替它選邊**，所以限制在 scale 本來就是
`f8E8M0FNU` 的情況。

### 4.3 結果型別放不下 NaN 就不折

`f4E2M1FN` 的 `fltNonfiniteBehavior` 是 **`FiniteOnly`**（`APFloat.cpp:115`）
——沒有 inf 也沒有 NaN。所以 NaN scale 配上 f4 結果時，**沒有任何值可以正確表示答案**，
只能放棄折疊。

---

## 5. NaN 那一段為什麼要特別寫？（reviewer 最可能問這題）

`.td` 白紙黑字：

> It propagates NaN values. Therefore, if either scale or the input element
> contains NaN, then the output element value will also be a NaN.

但如果照著展開鏈用 `APFloat::convert` 去加寬一個 `f8E8M0FNU` 的 NaN，
**今天的上游會得到 infinity**。

原因：`f8E8M0FNU` 的 `precision = 1`，NaN payload 是 **0 個位元**。
加寬之後 significand 全零，而「NaN 指數 ＋ 全零 significand」在目標格式裡
正好就是 infinity 的編碼。

→ 這就是 **[PR #214919](https://github.com/llvm/llvm-project/pull/214919)**
（見 [`e8m0-nan-becomes-inf.md`](e8m0-nan-becomes-inf.md)）。

### 5.1 ⚠️ 一個我先推錯、實測才修正的地方

我原本推論：`scaling_truncf(6.0, NaN) to f4E2M1FN` 走展開路徑會折成 `0.0`
（`6.0 / inf = 0.0`）。**實測是錯的**，展開路徑得到的是正常的 qNaN。

實際機制（用兩個案例隔離出來的）：

```mlir
// A：加寬後的 NaN 單獨落地
extf(0xFF : f8E8M0FNU) : f8E8M0FNU to f32   →  0x7F800000   ← inf 的位元（bug）

// B：同一個加寬，後面接一個乘法
mulf(extf(0xFF : f8E8M0FNU), 3.0)           →  0x7FC00000   ← 正常 qNaN
```

`APFloat` 物件的 category 一直都是 `fcNaN`，錯的只有**編碼**：significand 全零，
所以 `bitcastToAPInt()` 吐出來的位元剛好是 infinity。而**任何算術運算都會呼叫
`makeQuiet()`**，把 quiet bit 設起來 → significand 非零 → 位元就對了。

**結論**：兩個運算元都是常數時，展開路徑會被後面那個乘/除法**意外救回來**。
bug 只在「加寬後的 NaN 自己就是最終常數」時顯現——那正是 #214919 回報的案例。

**這件事怎麼影響這個 patch**：folder 的 NaN 特判因此不是「修正一個錯誤結果」，
而是**不要去依賴那個意外**。附帶好處是它能折得更多——NaN scale 之下結果必為 NaN，
與輸入無關，所以即使輸入加寬有損也照樣能折。

> 教訓（同 M1-b0 那次）：從機制推出來的結論，送出前一定要實測隔離。
> 這次如果沒測，PR 描述裡就會寫一句可以被 reviewer 一秒推翻的話。

---

## 5.2 poison 為什麼要傳播？

`arith` 其他 cast op 走的 `constFoldCastOp`（`CommonFolders.h:368-371`）
會把 `ub::PoisonAttr` 直接傳到結果。新 folder 如果不做，就與同 dialect 的兄弟 op
行為不一致——這種不一致 reviewer 會抓。

同時抄了 `constFoldCastOp` 的另一個檢查：**`hasStaticShape()`**
（`CommonFolders.h:391`）。少了它，結果型別是動態形狀 tensor 時
`DenseElementsAttr::get` 會直接 assert 崩潰。

---

## 6. 實作上一個非顯而易見的地方

`CommonFolders.h` 的 `constFoldBinaryOpConditional` **不能用**。

它在 `LElementValueT == RElementValueT`（這裡兩邊都是 `APFloat`）時，
會強制檢查 `lhs.getType() == rhs.getType()` 才繼續（`CommonFolders.h:69-71`、
`87-89`、`104-106` 三處）。

而 scaling op 的 `in` 與 `scale` **型別必然不同**（`f4E2M1FN` vs `f8E8M0FNU`），
所以那個 helper 一定會直接 bail。因此自己寫了 `foldScalingCastOp`，
處理 scalar / splat×splat / 逐元素三種情況。

（splat×splat 特別處理，是為了不要把一個大權重張量展開成逐元素再折回去。）

---

## 7. 驗證（第 4 關）

兩份**刻意互補**的證據，沿用 M1-a 的做法。

工具：[`tools/verify-scaling-fold/verify.py`](../tools/verify-scaling-fold/verify.py)

| 證據 | 是什麼 | 補到對方的什麼弱點 |
|---|---|---|
| 對照 `-arith-expand -canonicalize` | 上游自己的展開 ＋ 既有 folder | 抓「與上游慣例不一致」 |
| Python 獨立 oracle | 直接照 OCP 規格解碼位元、算數學答案，**完全不經過 LLVM** | 抓「展開本身就錯」的情況 |

**輸入空間小到可以真的窮盡**，不需要 SMT：

三項檢查（第三項是這次比 M1-a 多做的）：

1. 折出來的值 vs `-arith-expand -canonicalize`
2. 折出來的值 vs Python oracle
3. **「該不該折」的決定** vs 無損規則 → 這項抓的是**漏折**，不只是折錯

| 掃描 | 組合數 | 折疊數 | ①值vs展開 | ②值vsPython | ③折疊決定 |
|---|---|---|---|---|---|
| `scaling_extf` f4E2M1FN×f8E8M0FNU → f16 | 4,096 | 656 | 0 | 0 | 0 |
| `scaling_extf` f4E2M1FN×f8E8M0FNU → f32 | 4,096 | 4,096 | 0 | 0 | 0 |
| `scaling_truncf` f16×f8E8M0FNU → f4E2M1FN | 16,777,216 | 33,390 | 0 | 0 | 0 |
| **合計** | **16,785,408** | — | **0** | **0** | **0** |

`check-mlir`：4450 tests，**3838 passed / 0 failed**（611 unsupported、1 expectedly failed 都是預期內）。

### 7.1 兩個數字要能解釋，不然看起來像沒做事

**extf → f16 只折 656/4096，→ f32 折滿 4096。**
差在 f16 的指數只有 5 bit，放不下 `f8E8M0FNU` 大部分的 `2^e`（f16 只能精確表示
`e ∈ [-24, 15]`，共 40 個，40×16=640，再加 NaN scale 那 16 組 = 656）。
scale 加寬有損就不折——正是無損規則要的保守行為。

**truncf 只折 33,390/16,777,216（約 0.2%）。**
因為結果型別 `f4E2M1FN` 只有 **8 個非負值**（0, 0.5, 1, 1.5, 2, 3, 4, 6），
絕大多數 f16 除完之後根本落不到這 8 個值上，一律有損、一律不折。
**這不是漏折**——第 ③ 項檢查逐一驗證過每一組「不折」的決定都是對的。

### 7.2 ⚠️ 一個差點做出無效驗證的坑

第一版的 truncf 掃描用 `f8E4M3FN` 當輸入型別（256 個值，想讓組合數小一點）。
`-arith-expand` 直接報錯：

```
'arith.extf' op operand type 'f8E8M0FNU' and result type 'f8E4M3FN' are cast incompatible
```

展開鏈裡有一步是 `extf(scale : f8E8M0FNU → 輸入型別)`，所以**輸入型別必須嚴格寬於 8 bit**。
`f8E4M3FN` 也是 8 bit，展開不合法——雖然 op 自己的 verifier 過得了。
所以輸入只能用 `f16`，組合數就從 65536 變成 16,777,216。

---

## 8. reviewer 若提問，要能不看筆記回答

| 提問 | 答案 |
|---|---|
| 折疊的語意從哪來？ | 抄 `ExpandOps.cpp` 的展開鏈，不是自己定義的 |
| extf 和 truncf 為什麼不對稱？ | truncf 的除法在寬型別上做，scale 要配輸入；extf 的乘法在加寬後做，scale 配結果 |
| 為什麼有損就不折？ | 照 `ExtFOp::fold` / `TruncFOp::fold` 的既有慣例，`@truncFPConstantRounding` 就是測這件事 |
| 那 `roundingmode` 不就沒用了？ | 對，會折的都是無損的。上游的 truncf 捨入模式測試也全用精確值 |
| 為什麼 NaN 要特別寫？ | E8M0 的 NaN payload 是 0 個位元，加寬後會變成 inf 的編碼（#214919）。`.td` 規定要傳播 NaN，所以直接照契約產生 |
| 為什麼不順便支援 f16/f32 的 scale？ | `ExpandOps` 與 `ArithToAMDGPU` 對非 E8M0 scale 語意不一致，折疊不該選邊 |
| 為什麼不用 `constFoldBinaryOp`？ | 它要求兩個運算元同型別，而 `in` 與 `scale` 必然不同型別 |
| 怎麼確定沒漏 / 沒錯？ | 輸入空間全窮盡，不是抽樣；而且用兩個互相獨立的 oracle 對照 |
| 折疊大權重張量會不會讓 IR 爆掉？ | 與 `arith.extf` 既有行為一致（它也折 dense 常數）；splat 走專門路徑不展開 |

---

## 8.5 為什麼是一個 commit，不是 precommit test ＋ 修正兩個 commit？

TODO.md 原本規劃分兩發。改成一發，理由：

precommit test 的價值是讓 reviewer 看出**哪些既有行為改變了**。
M1-a 動到既有測試（`@simple_arith.ceildivsi_overflow`），所以值得。
**這一發的測試全部是新增的**，而且 diff 裡 `hasFolder = 1` 本身就說明
先前完全沒有 folder——「改動前不折」是從 diff 直接讀得出來的，不需要另一個 commit 證明。

成本那一側：要做出可信的 precommit commit，必須把 `.td` 還原後重建一次。
`.td` 一動就是 1085 個目標、約 1.5 小時，來回三小時。不划算。

---

## 9. 還沒做的（follow-up，不放進這一發）

- `scale = 2^0`（＝ 1.0）時退化成單純的 `extf` / `truncf`。
  那是 **canonicalization**（會建立新 op），與 folder 是不同機制，另開一發。
- round-trip：`scaling_truncf(scaling_extf(x, s), s) → x`。**未驗證**，
  truncf 會捨入，不保證回得去。
- 非 `f8E8M0FNU` scale 的語意不一致——那是 RFC 題目，不是 patch。
