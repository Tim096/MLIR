# M0 與 M1 完整解說（由淺入深）

寫給未來的自己：**送 PR 前重讀一次，確認每一節都能不看字自己講出來。**
這是上游 `AIToolPolicy.md` 的硬性要求，也是 `Goal.md` §1.1 的第一個目標。

---

## 第 0 層：這一切在幹嘛

編譯器把你寫的程式碼變成機器能跑的東西。中間會經過好幾種「中介表示法 (IR)」。

**MLIR 不是一種 IR，是「用來定義 IR 的框架」。** 你可以在裡面定義自己的一套指令集，
叫做 **dialect**（方言）。

我們的主場是 **`arith` dialect** —— 管加減乘除的那一組。裡面的指令長這樣：

```mlir
%r = arith.ceildivsi %a, %b : i8
```

讀作：把 `%a` 除以 `%b`（往上取整），結果放進 `%r`，型別是 8 位元整數。

---

## 第 1 層：什麼是「fold」

編譯器看到兩邊都是**已知常數**時，沒必要留到程式執行時才算，**當場算掉**：

```mlir
%a = arith.constant 7 : i8
%b = arith.constant 2 : i8
%r = arith.ceildivsi %a, %b : i8     ← 折疊成 arith.constant 4
```

這叫**常數折疊 (constant folding)**。程式變小、變快。

實作它的函式就叫 `fold()`。我們兩個 patch 都在 `mlir/lib/Dialect/Arith/IR/ArithOps.cpp`
這個檔案裡，那是 `arith` 所有 `fold()` 的家。

> **fold 的鐵律**：只能**保值**。折疊後的結果必須跟原本執行的結果**完全一樣**，
> 在所有輸入下都是。做不到就必須**放棄折疊**（回傳原本的 op）。
> 「不確定就放棄」永遠是安全的；「猜錯」則是 miscompile，是編譯器最嚴重的 bug。

---

## 第 2 層：M0 — 讓 switch 變窮盡

**PR #214622**：`[mlir][arith][NFC] Make AtomicRMWKind switches exhaustive`

### 2.1 背景：什麼是 reduction

把一長串數字**歸約**成一個數字，叫 reduction。例如「把陣列全部加起來」。

做 reduction 需要一個**起始值**，而且這個起始值必須「加了等於沒加」：

| 運算 | 起始值（單位元素） | 為什麼 |
|---|---|---|
| 加法 | `0` | `x + 0 = x` |
| 乘法 | `1` | `x × 1 = x` |
| 取最大 | `-∞` | `max(x, -∞) = x` |
| 位元 AND | 全部都是 1 | `x & 111…1 = x` |

這個起始值叫**單位元素 (identity element)**。

### 2.2 問題在哪

MLIR 有個 enum 叫 `AtomicRMWKind`，列出 16 種運算（編號 0~15）：
`addf` `addi` `andi` **`assign`** `maximumf` `maxnumf` … `xori`

有兩個函式要處理它：

| 函式 | 做什麼 |
|---|---|
| `getIdentityValueAttr` | 給一種運算，回傳它的單位元素 |
| `getReductionOp` | 給一種運算，建出對應的二元 op |

兩個函式各自用 `switch` 處理了 **15 種**，剩下的丟給 `default:`，上面掛一句：

```cpp
// TODO: Add remaining reduction operations.
default:
  (void)emitOptionalError(loc, "Reduction operation type not supported");
  break;
```

意思是「剩下的還沒做，以後補」。

### 2.3 關鍵洞察：這個 TODO 永遠補不完

漏掉的只有一個：**`assign`**。而 `assign` 根本不是 reduction。

`assign` 的意思是「直接覆蓋」：`assign(舊值, 新值) = 新值`，完全不理舊值。所以：

- **沒有單位元素。** 單位元素 `e` 要滿足 `assign(x, e) = x`。
  但 `assign(x, e) = e`，要它等於 `x` 就得 `e = x` —— 那會隨 `x` 變，**不是常數**。
  單位元素必須是固定的值，所以不存在。
- **沒有對應的二元 op。** 沒有 `arith.assign` 這種東西。覆蓋不是算術運算。

⚠️ **但 `assign` 不是垃圾。** 它在別的地方有效且被使用 ——
`memref.atomic_rmw` 用它表示「原子覆蓋」，會 lower 成 `xchg`（原子交換指令）。

所以正確的講法是：**`assign` 是另一種東西，只是被放進同一個 enum，
所以在這兩個 reduction 專用的函式裡本來就處理不了。**

TODO 不是「還沒做完」，是**要求一件不存在的事**。

### 2.4 怎麼確定「只缺 assign」

**不要用眼睛數。讓編譯器窮舉。**

把 `default:` 整段拿掉再編譯一次。`-Wswitch` 這個警告會**逐一點名**所有沒處理的值：

```
ArithOps.cpp:3078: warning: enumeration value 'assign' not handled in switch [-Wswitch]
ArithOps.cpp:3194: warning: enumeration value 'assign' not handled in switch [-Wswitch]
2 warnings generated.
```

兩則，都只講 `assign`。如果漏了三個，它會列三則。

> **這招記起來**：想知道 switch 漏了哪些 enum → 拿掉 `default:` 編一次。
> 任何 C++ 專案都能用。而且 **reviewer 可以自己重跑驗證**，
> 比「我數過了」強一個量級。

### 2.5 改法

```cpp
  // `assign` is not a reduction and has no identity element.
  case AtomicRMWKind::assign:
    break;
  }
  (void)emitOptionalError(loc, "Reduction operation type not supported");
  return nullptr;
```

兩個改動：
1. `default:` → 顯式的 `case AtomicRMWKind::assign:`
2. 錯誤訊息從 switch **裡面**移到 switch **後面**

### 2.6 換到了什麼

| | 三個月後有人加了第 17 種運算、忘了更新 switch |
|---|---|
| **有 `default:`** | 悄悄編譯過。要等執行時跑到才吐錯誤訊息 |
| **窮盡 switch** | **當場編譯警告**，CI 的 `-Werror` 組態下直接是編譯錯誤 |

**把一個執行期的靜默失敗，換成一個編譯期的硬性錯誤。** 這就是整個 patch 的價值。

### 2.7 最細緻的地方：錯誤訊息為什麼要搬出去

這是 reviewer 最可能問的。

現在的 `default:` 會接住**兩種**東西：
1. `assign`
2. **超出 0~15 範圍的非法值**（例如從外部 attribute 硬塞進一個爛數字）

如果把錯誤訊息留在 `case assign:` 裡面，第 2 種就會**靜默回傳 `nullptr`**，
不再有診斷 —— 那就**不是 NFC 了**。

搬到 switch 後面，兩種都還是走到同一行錯誤訊息，**行為逐字不變**。

> `[NFC]` = Non-Functional Change，行為完全不變。標了就要真的做到。

### 2.8 為什麼這段 code 能存在這麼久

因為它剛好從兩個警告的**中間漏下去**：

| 警告 | 為什麼沒響 |
|---|---|
| `-Wswitch`（有漏 case 就叫） | 被 `default:` 壓住了 |
| `-Wcovered-switch-default`（多餘的 default 就叫） | 只在**完全涵蓋**的 switch 才適用，而這個 switch 缺 `assign`，不算完全涵蓋 |

兩個警告互相抵消。而 LLVM 的 `CodingStandards.md` 有一整節叫
**"Don't use default labels in fully covered switches over enumerations"**，
還為此專門做了 `-Wcovered-switch-default` 這個警告（我們的 build 實際開著）。

**所以這不是誰的決定，是機制的死角。** 我們的 patch 是在落實上游自己寫下的規範。

---

## 第 3 層：M1 — 讓 ceildivsi 在 MININT 也能折疊

**PR #214637**：`[mlir][arith] Fold ceildivsi with MININT operands`

### 3.1 `ceildivsi` 是什麼

除法，但**往上取整**（ceiling）：

```
 7 ÷ 2 = 3.5   →   4     （往上）
-7 ÷ 2 = -3.5  →  -3     （往上；-3 比 -4 大）
```

名字拆開：`ceil`（天花板／往上）+ `div`（除）+ `s`（signed，有正負號）+ `i`（integer）。

### 3.2 必備前提：負數比正數多一個

這是理解整個 patch 的關鍵，一定要記牢。

8 位元有號整數 `i8` 的範圍是 **-128 到 127**。

注意**不對稱**：負的到 -128，正的只到 127。**負數多一個。**

（原因是二補數表示法，256 個位置要分給正負與零，零佔掉一個正的位置。）

所以：

```
-(-128) = 128     ← 128 放不進 i8（最大 127）→ 溢位！
```

**負數取負，可能爆掉。** 這就是問題的根源。
（`i16`、`i32` 一樣：MININT 分別是 -32768、-2147483648。）

### 3.3 舊實作的做法與它的死角

舊版用一個技巧：**先把負數變正，算完再變回來**。

```
ceil(-9 / -2)  →  先算 ceil(9 / 2) = 5     ← 兩邊都取負
```

技巧本身正確。但只要 `-128` 出現，取負那一步就溢位，**整個折疊直接放棄**。

而真正的答案根本沒問題：

```
ceil(-128 / 7) = -18        ← -18 明明放得進 i8
```

**答案是好的，只是中間過程算壞了。**

打個比方：要算 `1000000 - 999999`，你先把兩數各乘一百萬 —— 中間爆掉了，
但答案其實就是 1。

### 3.4 ⚠️ 這不是 bug，是「漏做最佳化」

**非常重要，reviewer 第一個會問的就是這個。**

舊版遇到溢位就**放棄折疊**，回傳原本的 op。程式照樣正確執行，只是少了一次最佳化。

**它從來沒算錯過。** 我實測過：改動前後，折出錯誤答案的組數**都是 0**。

（歷史上確實有過真的算錯——issue #89382，`ceildivsi -128, 7 : i8` 得到 `18`。
但那個已經修掉了，修法就是加上這套「溢位就放棄」的偵測。
**洞沒補完，只是從「算錯」降級成「漏折」。**）

### 3.5 新做法：完全不取負

關鍵是理解**機器的整數除法往哪個方向取整**。

`sdiv`（有號除法）是**往零的方向截斷**：

```
 7 / 2 =  3.5  →  3     （往零 = 往下）
-7 / 2 = -3.5  →  -3    （往零 = 往上！）
```

**注意第二行**：答案是負的時候，往零截斷**剛好就等於往上取整** —— 我們要的 ceiling
自動就有了，免費。

所以只有**答案是正的**（也就是兩個運算元同號）**而且除不盡**時，才需要補 1：

```
ceil(7/2):   q = 3， 除不盡、同號（答案為正）→ 補 1 → 4    ✅
ceil(-7/2):  q = -3，除不盡、異號（答案為負）→ 不補 → -3   ✅
ceil(8/2):   q = 4， 除得盡              → 不補 → 4    ✅
```

程式碼：

```cpp
APInt quotient = a.sdiv_ov(b, overflowDiv);       // 除
if (overflowDiv) bail;                            // MININT / -1
if (a.srem(b).isZero() ||                         // 除得盡 → 不用補
    a.isNegative() != b.isNegative())             // 異號（答案為負）→ 不用補
  return quotient;
return quotient.sadd_ov(one, overflowOrDiv0);     // 否則補 1
```

（`srem` 是取餘數。餘數是 0 就代表除得盡。）

**全程沒有取負，`-128` 就不再是問題。**

### 3.6 唯一真的該放棄的情況

```
ceil(-128 / -1) = 128       ← 答案本身放不進 i8
```

這個**必須**維持不折疊。**注意這跟前面的問題性質不同** ——
不是中間過程爆掉，是**答案真的塞不下**。這種情況沒有正確的常數可以折，只能放棄。

（加上 `b == 0` 除以零，總共就這兩種。）

### 3.7 為什麼新演算法「剛好」正確

`sdiv` 只在兩種情況溢位：`b == 0`、`MININT / -1`。

而這**剛好就是**語意上必須放棄的那兩種。

**溢位偵測與語意需求完全對齊** —— 這是這個寫法最漂亮的地方，也是為什麼
新版比舊版短 50 行（舊版四個象限各寫一套、四個溢位旗標）。

### 3.8 怎麼確定是對的：兩份互補的證據

#### 證據一：窮盡測試

不抽樣，**測所有可能的組合**，拿 Python 算的精確答案當標準：

| 位寬 | 組數 | 結果 |
|---|---|---|
| `i4` | 240（全部） | 全對，未折疊 1 組 = `-8 / -1` |
| `i8` | 65280（全部） | 全對，未折疊 1 組 = `-128 / -1` |

**折疊了所有放得下的，且恰好只放棄那個放不下的。不多不少。**

改動前後對比（同一份 i8 窮盡測試）：

| | 未折疊 | 折錯 |
|---|---|---|
| 改動前 | 507 | **0** |
| 改動後 | **1** | **0** |

「折錯 = 0」這欄很重要，它證明了 §3.4 那句話：**舊版是保守，不是有 bug。**

#### 證據二：Alive2 形式化證明

Alive2 是 LLVM 圈驗證改寫正確性的工具，用 SMT solver **符號式地**證明
「對所有可能輸入，改寫前後等價」。

我證的命題**選得有講究**：不是「某組常數算對」（太弱，而且 Alive2 指南明說
證明要用泛化的變數），而是：

> **我們新 folder 的演算法，與上游 `arith-expand` 本來就在用的展開公式，等價。**

兩者唯一差別是判斷「除不盡」的方式（`srem != 0` vs `a != q*b`），其餘逐行相同。

結果：**`Transformation seems to be correct!`**
連結 https://alive2.llvm.org/ce/z/Chnon4

#### 為什麼要兩份

**Alive2 只證「跟 ExpandOps 一致」。萬一 ExpandOps 本身也錯，兩個就一起錯。**

窮盡測試是拿**數學上的精確答案**當標準，獨立於任何 LLVM 程式碼。

**主動說出自己證據的侷限，比讓 reviewer 自己發現好。** PR 描述裡有寫這段。

### 3.9 意外發現：`b` 那一側從沒人記錄過

上游的 TODO 只寫「`a`（被除數）是 MININT 時會漏折」。

但實測發現 **`b`（除數）是 MININT 時也一樣會漏** —— 因為 `b` 也會被取負。

而且在那 507 組裡：

| | 組數 |
|---|---|
| `a` = MININT | 253 |
| **`b` = MININT** | **254** ← 超過一半 |

**這是本 patch 比 2024 年那個停擺的舊 PR #90855 多做到的部分。**

### 3.10 為什麼這個題目值得做

- **上游自己在測試檔裡寫著這該修**：
  `// TODO: The folder should be able to fold the following by avoiding
  intermediate operations that overflow.`
  → 不是我們自作主張，是完成別人寫下的意圖
- **正確公式上游早就有**（`ExpandOps.cpp` 的展開），我們只是把它補進 folder
- 有真實行為改善、有窮盡驗證、不引發設計爭論
- 淨減 50 行

---

## 第 4 層：這次用到的社群慣例

### 4.1 Precommit tests（M1 用了）

PR 應該有**兩個 commit**：

1. **只加測試**，CHECK 反映**改動前**的行為
2. **功能改動 + CHECK 的 diff**

> 「If the second commit in your PR does not contain test diffs, you did
> something wrong.」——`InstCombineContributorGuide.md`

好處：reviewer 一眼看得出**哪些行為真的變了**，不必自己比對。

### 4.2 Negative tests

一定要測「**不該**套用」的情況，而且每個測試**剛好只違反一個前提**。
我們的是 `MININT / -1` 與 `b == 0`。

### 4.3 動到既有測試要主動點名

M1 改了 `@simple_arith.ceildivsi_overflow`（它原本斷言不折疊，現在會折了）。
**PR 描述裡主動講出來**，別讓 reviewer 自己發現。

### 4.4 `[NFC]` 標籤

純重構、行為完全不變才能標。標了就要真的做到（見 §2.7）。

---

## 第 5 層：答辯手冊

**送 PR 後 reviewer 可能問這些。要能不看筆記回答。**

### M0（#214622）

| 提問 | 答案 |
|---|---|
| 怎麼確定只缺 `assign`？ | 拿掉 `default:` 編一次，`-Wswitch` 逐一點名。實測兩處各一則、都只有 `assign` |
| 真的是 NFC 嗎？ | 診斷移到 switch 之後，`assign` 與超出範圍的值**都**照舊得到同一個診斷 |
| 為何不用 `llvm_unreachable`？ | 那會把超出範圍的值從「診斷」變成「abort」，就不是 NFC 了。想改成那樣是另一個議題，該分開送 |
| `assign` 為什麼存在？ | 它在 `memref.atomic_rmw` 有效，lower 成 `xchg`。只是不是 reduction |
| 這種寫法有前例嗎？ | 有，`OpenACCUtilsReduction.cpp` 已經是同樣結構 |

### M1（#214637）

| 提問 | 答案 |
|---|---|
| 這是修 bug 嗎？ | **不是。** 舊版正確但保守，是漏折疊。折錯數改動前後都是 0 |
| 為什麼舊版會漏？ | 它先把負數取負變正。`i8` 負數比正數多一個，`-(-128) = 128` 放不進去就溢位放棄 |
| 新演算法為什麼對？ | `sdiv` 往零截斷，答案為負時就等同往上取整；只有同號（答案為正）且除不盡才補 1 |
| 還有什麼不折？ | 只剩 `b == 0` 與 `MININT / -1`（後者答案 `-MININT` 本身放不進型別） |
| 怎麼確定沒漏？ | i4 240 組、i8 65280 組**全窮盡**比對數學精確值，不是抽樣 |
| 有形式化證明嗎？ | 有，Alive2 證明與 `arith-expand` 的展開等價 |
| 那個證明夠嗎？ | 不夠，所以還有窮盡測試。Alive2 只證「跟 ExpandOps 一致」，oracle 掃描才獨立於 LLVM 實作 |

---

## 第 6 層：一句話總結

- **M0**：把一個永遠做不完的 TODO 收掉，順便讓編譯器以後幫我們守住這兩個 switch。
  **價值：把執行期的靜默失敗，換成編譯期的硬性錯誤。**
- **M1**：拿掉一個會在邊界溢位的中間步驟，讓 506 個本來就算得出來的答案真的被算出來。
  **價值：修掉一個上游自己標記、但沒人做完的漏最佳化。**
