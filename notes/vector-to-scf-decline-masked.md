# `convert-vector-to-scf` 對 `vector.mask` 包住的 transfer op 產生不合法 IR

**檔案**：`mlir/lib/Conversion/VectorToSCF/VectorToSCF.cpp`（`checkPrepareXferOp`、`UnrollTransferReadConversion`、`UnrollTransferWriteConversion`、`TransferOp1dConversion`、`ScalableTransposeTransferWriteConversion`）
**測試**：`mlir/test/Conversion/VectorToSCF/vector-to-scf.mlir`
**開工**：2026-09-05
**分支**：`vector-to-scf-decline-masked`，commit `af0e5de00d82`，base `f6a369fa4a57`

---

## 一句話

`vector.mask` 的 region 只准放一個 op。`convert-vector-to-scf` 的五個 transfer pattern 都沒看自己是不是在 `vector.mask` 裡，
照樣把 transfer op 拆成 `memref.alloca` ＋ `scf.for` ＋ 低一階的 transfer op，全部塞進 mask region，verifier 報
`'vector.mask' op expects only one operation to mask`，整個 pass 失敗。修法是每個 pattern 入口加 `isMasked()` 檢查就拒收。

---

## 兩種 mask 長相，要分清楚

| 形式 | 例子 | VectorToSCF 支不支援 |
|---|---|---|
| **mask operand**（op 自己帶） | `vector.transfer_read %m[...], %pad, %mask : ...` | 支援。`xferOp.getMask()` 非空，pattern 會 `vector.extract` 一片一片切下去 |
| **`vector.mask` region**（外面包一層） | `vector.mask %mask { vector.transfer_read ... }` | **不支援**，這題就是它 |

- `xferOp.getMask()` 看的是 operand，region 形式下它是空的，所以 pattern 以為「沒有 mask」，拆出來的低階 transfer op 一個 mask 都沒帶。
- `xferOp.isMasked()` 是 `MaskableOpInterface` 的方法，看的是 parent 是不是 `vector.mask`。`TransferReadOp`／`TransferWriteOp` 都實作這個 interface（`VectorOps.td`），所以直接呼叫就行。
- 兩種形式之間靠 `-lower-vector-mask`（`populateVectorMaskLoweringPatternsForSideEffectingOps`）轉換：把 region 形式改成 operand 形式。in-tree 所有整合測試都是先跑 `-lower-vector-mask` 再跑 `-convert-vector-to-scf`（`test-matmul-masked-vec.mlir`、`ArmSVE/1d-depthwise-conv.mlir`、`pack-unpack-scalable-inner-tile.mlir` 等），這就是預期的順序。

---

## 五條路徑全部重現過（build 於 `f6a369fa4a57` 前的 binary）

| 路徑 | 觸發 | 結果 |
|---|---|---|
| 預設 progressive（`PrepareTransferRead/Write` → `TransferOpConversion`） | 2-D read／write 在 mask 裡 | `expects only one operation to mask`，region 裡多了 `memref.store`、`vector.type_cast`、`scf.for` |
| `full-unroll=true`（`UnrollTransferRead/Write`） | 同上 | 同上 |
| 1-D（`TransferOp1dConversion`） | `vector<8xf32>`、map `(d0, d1) -> (d0)` | `expects a MaskableOpInterface within the mask region`（region 裡變成 `scf.for`） |
| `lower-scalable=true`（`ScalableTransposeTransferWriteConversion`） | `vector<4x[4]xf32>` 轉置寫 | `expects only one operation to mask` |
| `lower-tensors=true` | tensor 的 2-D write | `expects only one operation to mask` |

先跑 `-lower-vector-mask` 再跑 pass，五個都正常。

---

## 為什麼是拒收而不是「順手把 mask 折進去」

1. **精神一致**：`LowerVectorTransfer.cpp` 的 `TransferWritePermutationLowering` 遇到 `maskOp` 就 `notifyMatchFailure(op, "Masked case not supported")`；`VectorDropLeadUnitDim.cpp:230`／`:284`、`ArmSVE/LegalizeVectorStorage.cpp:338` 都是 `isMasked()` 就退。
2. **分工**：`vector.mask` 的 lowering 是獨立的 pass（dcaballe 設計時就把它拆開），pattern set 也被 `transform.apply_patterns.vector.transfer_to_scf` 和 sparse／GPU pipeline 拿去用，在 pattern 裡偷跑 mask lowering會讓這些使用者的輸出無預警改變。
3. **最小**：五個地方各三行，沒有新 helper，和上週 `ecb980e51e37`（alepot55，#216947）在 `checkPrepareXferOp` 加 allocation-scope 檢查是同一種修法。

### 為什麼是五個地方而不是一個
pattern 入口不共用：progressive 路徑走 `checkPrepareXferOp`（free function），unroll 兩個 pattern 各自 `matchAndRewrite`，1-D 與 scalable transpose 也各自獨立。
`VectorToSCFPattern` 基底只有 `checkLowerTensors`，且 `checkPrepareXferOp` 不是它的成員。與其為此加一個 helper，不如照既有慣例 inline。

### 檢查放的位置
- `checkPrepareXferOp`：緊接在 `kPassLabel` 檢查後（都是「這個 op 現在不能碰」類）。
- unroll 兩個：`checkLowerTensors` 之後、element type 檢查之前。
- scalable transpose：`checkLowerTensors` 之後。
- 1-D：0-d 檢查之後、取 permutation map 之前。

---

## 測試

四個負向測試，三個 RUN 前綴（`CHECK`、`FULL-UNROLL`、`TARGET-RANK-ZERO`）都比對「`vector.mask %{{.*}} { vector.transfer_*` 還在」＋ `CHECK-NOT: scf.for`／`vector.extract`：

| 測試 | 覆蓋的 pattern |
|---|---|
| `masked_transfer_read` | Prepare／Unroll read |
| `masked_transfer_write` | Prepare／Unroll write |
| `masked_transfer_read_1d_strided` | `TransferOp1dConversion` |
| `masked_scalable_transpose_store` | `ScalableTransposeTransferWriteConversion`（FULL-UNROLL 那條 RUN 有 `lower-scalable=true`） |

踩到一個 FileCheck 細節：`vector.mask` 與裡面的 op 印在**同一行**，`CHECK-NEXT` 會報 `is on the same line as previous match`，所以用單行 `vector.mask %{{.*}} { vector.transfer_read`。

---

## Reviewer 可能問

- **「為什麼不直接支援？」** 支援等於在 VectorToSCF 裡重做 `-lower-vector-mask`；pattern 已經完整處理 operand 形式的 mask，先轉再降是設計好的分工。可以補一句 pass 文件說明順序。
- **「`isMasked()` 對 tensor 版的 transfer op 也成立？」** 是，interface 在 op 上，與 shaped type 無關；`lower-tensors=true` 的案例也重現且修好。
- **「有沒有人在 pipeline 裡不先跑 lower-vector-mask？」** in-tree 沒有；GPU 三條 pipeline（NVVM／ROCDL／XeVM）與 sparse pipeline 都直接 `createConvertVectorToSCFPass()`，但它們的輸入沒有 `vector.mask`。這個 patch 只把「verifier 失敗」改成「留著不動，後面的 conversion 給出清楚的 legalize 錯誤」。
- **「1-D 路徑那個錯誤訊息不一樣？」** `TransferOp1dConversion` 把整個 op 換成 `scf.for`，region 裡剩一個非 maskable op，所以 verifier 走的是另一條訊息。根因相同。
- **相關 issue**：#99662（open，bufferization 對 masked xfer op 也出錯）是同一類「pass 沒考慮 `vector.mask`」的問題，不是重複。
