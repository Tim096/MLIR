# M1-c'：`vector.transfer` permutation lowering 支援 masked 情況

> 這份文件的用途：**讓你不看筆記也能回答 reviewer**。標題就是 reviewer 可能問的問題。

分支：`vector-masked-transfer-lowering`，基準 `origin/main`。
狀態：**實作完成，等建置驗證**。

---

## 1. 縫隙是什麼？

`mlir/lib/Dialect/Vector/Transforms/LowerVectorTransfer.cpp` 裡有 **6 個** pattern
繼承 `MaskableOpRewritePattern`——這個基礎設施存在的唯一目的，就是讓 pattern
能處理包在 `vector.mask` 裡的 op。

**六個全部第一件事就是 bail：**

```cpp
// TODO: Support transfer_read inside MaskOp case.
if (maskOp)
  return rewriter.notifyMatchFailure(op, "Masked case not supported");
```

也就是說：這個檔案用了 maskable 基礎設施，卻從來沒有真的改寫過一個 masked op。

### 但其中兩個是「應該」bail 的

| pattern | 該不該做 |
|---|---|
| `TransferReadPermutationLowering` | ✅ 本發處理 |
| `TransferWritePermutationLowering` | ✅ 本發處理 |
| `TransferWriteNonPermutationLowering` | 🟡 follow-up（加 unit dim，mask 要用 `extendMaskRank`） |
| `TransferOpReduceRank` | 🟡 follow-up（降 rank，mask 要砍 leading 維，不是單純重排） |
| `TransferReadToVectorLoadLowering` | ⛔ **不該做**——目標是 `vector.load`，該 op 沒有 mask 運算元 |
| `TransferWriteToVectorStoreLowering` | ⛔ **不該做**——同上，`vector.store` 沒有 mask |

> 這個區分是查證來的，不是猜的。回答「為什麼只做兩個」時要能講出後面兩個是
> **原理上不可能**（除非改用 `maskedload`/`maskedstore`，那是另一個題目）。

---

## 2. ⭐ 核心洞見：mask **不需要**任何變換

這是整個 patch 的關鍵，也是最容易答錯的地方。

直覺會這樣想：pattern 把 permutation 從 transfer 搬到 `vector.transpose`，
所以 mask 也要跟著轉置。**這是錯的。**

`vector::inferTransferOpMaskType`（`VectorOps.cpp`）定義了 transfer op 的 mask 型別：

```cpp
AffineMap invPermMap = inversePermutation(compressUnusedDims(permMap));
SmallVector<int64_t, 8> maskShape = invPermMap.compose(vecType.getShape());
```

＝ 把向量形狀**經由 permutation map 的反函數映回「記憶體維度順序」**。

**所以 mask 不是活在結果的座標系，是活在記憶體的座標系。**
而這兩個改寫**只重排結果的維度順序，完全不改變碰到哪些記憶體維度**
——因此 mask 型別是不變的，原封不動傳過去就對。

### 用既有測試的具體數字驗證

| 案例 | 原本 | 改寫後 | mask |
|---|---|---|---|
| write：`(d0,d1,d2,d3) -> (d3,d2)`，值 `vector<4x8xi16>` | mask `vector<8x4xi1>` | 值轉置成 `vector<8x4>`、map 變 minor identity → 推導 mask = `vector<8x4xi1>` | **相同** |
| read：`(d0,d1) -> (0,d1,d0)`，結果 `vector<8x4x2xf32>` | mask `vector<2x4xi1>`（`8` 那維是 broadcast，不進 mask） | 只重排結果維度 | **相同** |

> **這個假設如果錯了會怎樣？** `vector.mask` 的 verifier 會直接擋下來——
> 它會拿 `inferTransferOpMaskType` 去核對。所以錯了是大聲失敗，不是靜默錯誤。
> 這是選擇這個做法的另一個理由。

---

## 3. passthru 為什麼要轉置，mask 卻不用？

因為兩者活在不同座標系：

- **mask**：記憶體維度順序 → 不變
- **passthru**：它是「被遮蔽的 lane 要拿什麼值」，型別＝**結果**的型別 → 跟著結果一起重排

所以 read 那一側，passthru 要用 `invertPermutationVector(transposePerm)` 轉置後
餵給新的 read；最後整個結果再轉置回去時，passthru 的 lane 也跟著轉回正確位置。

write 沒有 passthru 的問題（寫入沒有「結果 lane」）。

---

## 4. 為什麼是一個 commit，不用 precommit test？

因為**「改動前」的行為已經寫在既有測試裡了**：

```mlir
// Masked version is not supported
// CHECK-LABEL: func @xfer_read_minor_identity_transposed_masked(
//   CHECK-NOT:   vector.transpose
```

上游已經有 7 個 `..._masked` 測試在斷言「不支援」。本發會改到其中 **3 個**
（另外 4 個屬於沒動的 pattern，應維持不變——**這本身就是一項驗證**）。
測試檔的 diff 直接顯示哪些行為變了，不需要另一個 commit 來證明。

⚠️ 動到既有測試，PR 描述要主動點名。

---

## 5. reviewer 若提問，要能不看筆記回答

| 提問 | 答案 |
|---|---|
| mask 為什麼不用轉置？ | transfer 的 mask 是記憶體維度順序（`inferTransferOpMaskType` 用 inverse permutation 映回去），這兩個改寫只動結果的順序 |
| 那 passthru 為什麼要？ | passthru 的型別是結果型別，活在結果座標系 |
| 怎麼確定 mask 型別真的沒變？ | `vector.mask` 的 verifier 會核對；錯了測試就紅。另外用兩個既有測試的實際形狀手算過 |
| 為什麼只做兩個 pattern？ | 另外兩個 permutation 無關（一個加 unit dim、一個降 rank），mask 的變換不同，各自要獨立論證；最後兩個目標是 `vector.load`/`store`，那兩個 op 根本沒有 mask |
| 會不會多產生一個 transpose？ | mask 完全沒有新增 op。只有 passthru 存在時才多一個 transpose，而 passthru 本來就少見 |

---

## 6. 撞車狀況（2026-08-10 實查）

**PR [#200703](https://github.com/llvm/llvm-project/pull/200703)（open）
「[mlir][vector][NFC] Drop 0-d guards in transfer permutation lowering」
動的是同一批函式**——處理的是 0-d guard，不是 mask，但**行號相鄰**。

搜過的關鍵字：`vector+mask+transfer_read+lowering`、`TransferReadPermutationLowering`、
`vector.mask+transfer`，沒有其他重疊。

**做法**：PR 描述主動點名 #200703，說明兩者不衝突（它拿掉 0-d 的 early return，
我們拿掉 mask 的 early return），必要時等它先進再 rebase。
