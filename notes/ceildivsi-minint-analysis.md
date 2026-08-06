# `arith.ceildivsi` MININT folding gap — 分析

最後更新：2026-08-07　　狀態：**§4 的現況表已用 `mlir-opt` 實測驗證**（M-1 完成後補測）

> ✅ §4 那張「哪些 case 現在漏折」的表，每一列都已用
> `mlir-opt --canonicalize` 跑過，實測與推導逐條相符（實測輸出見 §4 末）。
> 對照組（不含 MININT 的四象限）確認會正常折疊，排除「其實整個 fold 都沒作用」的可能。
>
> ⚠️ 但 §6 的**新演算法本身還沒實作、沒驗證**——那部分仍是推導。

相關檔案：
- 實作：`mlir/lib/Dialect/Arith/IR/ArithOps.cpp`，`CeilDivSIOp::fold`（~line 973，TODO 在 ~991）
- 測試：`mlir/test/Transforms/constant-fold.mlir`，`@simple_arith.ceildivsi`（:443）
  與 `@simple_arith.ceildivsi_overflow`（:481）

---

## 1. 一句話

`CeilDivSIOp::fold` 用「先取負、再算非負除法、再取負回來」實作 ceiling 除法。
只要 `a` 或 `b` 任一個是 `MININT`，取負就溢位，整段放棄折疊——
**即使真正的答案完全放得進目標型別**。

## 2. 這不是 miscompile

必須講清楚，免得重蹈 PR #90855 的覆轍（見 §6）：
**現在的行為是正確的，只是保守。** 溢位偵測到就 bail，回傳原 op，不會算錯。
我們要修的是**漏掉的折疊機會 (missed optimization)**，不是正確性 bug。

歷史上確實有過 miscompile：issue **#89382**（`ceildivsi -128, 7 : i8` 得到 `18`），
但那個已經 closed as completed，修法就是加上現在這套溢位偵測。
**洞沒補完，只是從「算錯」降級成「漏折」。**

## 3. upstream 自己說這該修

兩處白紙黑字：

`ArithOps.cpp` 的實作裡：
```cpp
// TODO: This hook won't fold operations where a = MININT, because
// negating MININT overflows. This can be improved.
```

`constant-fold.mlir` 的測試裡（`@simple_arith.ceildivsi_overflow` 內）：
```
// TODO: The folder should be able to fold the following by avoiding
// intermediate operations that overflow.
```

第二條特別有價值：**測試檔本身就記著「這些現在斷言不折疊的 case，其實應該要折疊」。**
所以這個 patch 不是在提出新設計，是在完成 upstream 已經寫下的意圖。

## 4. 現況：哪些 case 漏折

`fold` 早期路徑（`b == 1`、`a == 0`、`a == b`）先擋掉一部分，剩下進四象限分支。
四個分支裡有三個會取負：

| 分支 | 條件 | 現在的做法 | 何時溢位 |
|---|---|---|---|
| 1 | `a > 0, b > 0` | `signedCeilNonnegInputs(a, b)` | 不取負，**沒問題** |
| 2 | `a < 0, b < 0` | `ceil(-a, -b)` | `a == MININT` 或 `b == MININT` |
| 3 | `a < 0, b > 0` | `-((-a) / b)` | `a == MININT` |
| 4 | `a > 0, b < 0` | `-(a / (-b))` | `b == MININT` |

**⚠️ 比原本以為的更廣**：`ArithOps.cpp` 的 TODO 只提 `a = MININT`，
但分支 2 與 4 在 **`b == MININT`** 時同樣會溢位放棄。
`b` 側的漏折沒有任何人記錄過。

漏折的具體例子（皆為真實答案放得進型別、卻沒被折的情況）：

| 運算式 | 型別 | 真實答案 | 現況 | 放得下嗎 |
|---|---|---|---|---|
| `ceildivsi(-128, 7)` | `i8` | `-18` | 不折 | ✅ |
| `ceildivsi(-32768, 7)` | `i16` | `-4681` | 不折 | ✅ |
| `ceildivsi(-2147483648, 7)` | `i32` | `-306783378` | 不折 | ✅ |
| `ceildivsi(7, -128)` | `i8` | `0` | 不折 | ✅ ← `b` 側，沒人記錄過 |
| `ceildivsi(-9, -128)` | `i8` | `1` | 不折 | ✅ ← `b` 側 |
| `ceildivsi(-128, -2)` | `i8` | `64` | 不折 | ✅ |

**✅ 上表六列已於 2026-08-07 用 `mlir-opt --canonicalize` 實測**，全部確認「現況不折」。
同批測的對照組 `ceil(7,2)=4`、`ceil(7,-2)=-3`、`ceil(-9,2)=-4`、`ceil(-9,-2)=5`
四個都正常折疊，證明 fold 本身有作用、不折是 MININT 專屬問題。
必須 bail 的兩個（`MININT / -1`、`x / 0`）也確認維持不折。

驗算（`ceil` 是往 +∞ 取整）：
- `-128 / 7 = -18.2857…` → `-18`。檢查：`7 × -18 = -126 ≥ -128` ✓、`7 × -19 = -133 < -128` ✓
- `-32768 / 7 = -4681.1428…` → `-4681`。檢查：`7 × -4681 = -32767 ≥ -32768` ✓
- `-2147483648 / 7 = -306783378.2857…` → `-306783378`。檢查：`7 × -306783378 = -2147483646 ≥ -2147483648` ✓

## 5. 真正必須放棄折疊的只有兩種

這是 PR 描述裡最需要說清楚的一段——**「什麼時候該 bail」要窮盡**：

1. **`b == 0`** — 除以零。（現行 fold 已用 `overflowOrDiv0` 擋住，且上面有註解說明
   之所以不折成 poison，是因為那會讓 `arith` 相依於 `ub` dialect。維持現狀。）
2. **`a == MININT && b == -1`** — 真實答案是 `-MININT = 2^(n-1)`，**放不進去**。
   這是唯一一個「答案本身溢位」的 case。

除此之外**全部都可折**。理由：ceiling 除法的結果絕對值不會超過 `|a|`
（因為 `|b| ≥ 1`），所以只要不是上面那個符號翻轉的邊界，結果必定落在型別範圍內。

## 6. 改法：不取負

用 `sdiv` 的截斷語意直接湊 ceiling，全程不做取負：

```
q = a sdiv b        // 往 0 截斷
r = a srem b
if (r != 0 && sign(a) == sign(b))   // 真實商為正且有餘數 → 往上補 1
    q = q + 1
```

`sdiv` 只在 `b == 0` 與 `MININT / -1` 溢位，剛好就是 §5 那兩種必須 bail 的情況——
**溢位偵測與語意需求完全對齊，這是這個寫法最漂亮的地方。**

`q + 1` 會不會溢位？**不會**，但要在 PR 裡論證：
補 1 只發生在真實商為正（`a`、`b` 同號）且有餘數時，此時 `|a| ≥ |b| ⋅ q + 1` 且 `|b| ≥ 2`
（`|b| == 1` 不會有餘數），所以 `q ≤ (|a| - 1) / 2 < MAXINT`。
`|b| == 1` 的情形無餘數，走不到補 1。
→ 雖然推導上不會溢位，實作仍應用 `sadd_ov` 保險，成本為零。

## 7. 測試要怎麼改

**這個 patch 會動到既有測試，PR 描述必須主動點名，不要讓 reviewer 自己發現。**

1. `@simple_arith.ceildivsi_overflow`（`constant-fold.mlir:481`）
   目前斷言三個 MININT case **不折疊**。改完後它們會折成
   `-18` / `-4681` / `-306783378`。
   → 這個測試要改寫，函式名也該換（它已經不再是在測「不折疊」了），
     順手刪掉裡面那條已完成的 TODO 註解。
2. **新增** 真正該 bail 的 case，取代原本的角色：
   `ceildivsi(MININT, -1)` 對 i8/i16/i32，斷言維持原 op 不折。
3. **新增** `b == MININT` 側的 case（§4 表格後三列）——這是本 patch 獨有的覆蓋，
   也是「我們比 #90855 做得完整」的具體證據。

## 8. 舊 PR #90855：不是撞車，是機會

- 2024-05 由 `bviyer` 開，測資正是 `-128 / 7 : i8`，期望 `-18`。
- **停擺兩年**，base 已嚴重漂移（當年在 line 652、單一 `overflowOrDiv0` flag；
  現在在 991、拆成 `overflowNegA/NegB/Div/NegRes` 四個）。
- 被 reviewer **banach-space（Andrzej Warzyński，本檔第 5 大作者）** 擋下，原話：

  > "the current logic _does work_ for negative values. It breaks when using MININT"
  >
  > "This PR is missing some analysis explaining what the actual issue is.
  >  Without that, the proposed update seems rather arbitrary"

- 作者始終沒補上分析。

**它的補丁本身可能也有問題**：`APInt posA = aGtZero ? a : zero.ssub_ov(a, …)`
——`a == MININT` 時這行照樣溢位，那它自己那個 `-128 / 7` 的測試怎麼會過？
**待查**（可能是當年 base 的 `signedCeilNonnegInputs` 語意不同，或測試根本沒真的驗到）。
這條不確定，**不要寫進 PR，也不要拿去說別人的補丁有 bug**——沒查清楚就講會很難看。

**對我們的意義**：已有資深 reviewer 公開表態他懂這題、在乎這題，只是嫌沒人給分析。
那份缺的分析就是這份文件。禮貌上 PR 描述應提一句 #90855 曾嘗試過，並考慮 @ `bviyer`。

## 9. 待辦

- [x] 用 `mlir-opt` 實測確認 §4 表格每一列現況真的不折 ✅ 2026-08-07
- [ ] 實作 §6 演算法
- [ ] 實測確認折疊結果與 §4 的「真實答案」欄逐一相符
- [ ] 確認 `MININT / -1` 與 `b == 0` 仍然不折
- [ ] 跑 `ninja check-mlir`，確認沒有其他測試被連帶打爛
  （`ceildivsi` 出現在 10 個測試檔，見 TODO.md）
- [ ] 查清楚 §8 那個「#90855 自己的測試為何會過」的疑問（純為自己搞懂，不進 PR）
