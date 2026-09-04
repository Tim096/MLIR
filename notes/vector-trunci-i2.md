# `arith.trunci` 到 `i2`：補上 sub-byte 重寫缺的那一半

> 分支 `vector-trunci-i2`，基準 `eac210e8d174`（2026-09-04），commit `a00b482bb9bc`。
> 這份筆記的用途是**讓你不看它也能答辯**，不是存檔。

---

## 1. 一句話

`VectorEmulateNarrowType.cpp` 的 `RewriteAlignedSubByteIntTrunc` 只會把 `trunci` 到 `i4`
重寫成 deinterleave＋位元運算，碰到 `i2` 直接 `return failure()`（留了一行 TODO）。
放大方向（`RewriteAlignedSubByteIntExt`）i4／i2 兩種都做了。**i2 權重解得開、包不回去**，這個 patch 補上包回去。

## 2. 為什麼值得做（reviewer 會問「誰用」）

- i2 ext 是 #121298（`ziereis`，2025-01）加的，commit 訊息說他用在 **i6 量化模型**、dequant-matmul 快 2 倍，
  並明講「i8→i2 truncation 我沒加，需要的話可以加」。這個 patch 就是那句話的續集。
- 缺口是**不對稱的**：同一個檔案、同一組 pattern、同一個 transform op（`apply_patterns.vector.rewrite_narrow_types`），
  只有縮小方向少一種寬度。
- 上游自己留了負向測試 `@aligned_trunci_i8_to_i2_no_match` 指名這個缺口——patch 把它翻成正向。

## 3. 做法（一句話講清楚位元怎麼走）

輸入 `vector<Nxi8>`，輸出 `vector<Nxi2>`，每 4 個 i8 包成 1 個 byte，**第 0 個放最低兩位**（little-endian，
和 `vector.bitcast` 的語意、以及 ext 那邊 `extractNBitsPerByteAndExtendToI8(bitIdx=0)` 一致）。

```
in       = [0,1,2,3,4,5,6,7]
deinterleave → even=[0,2,4,6] odd=[1,3,5,7]
deinterleave even → vec0=[0,4] vec2=[2,6]
deinterleave odd  → vec1=[1,5] vec3=[3,7]
byte = (vec0 & 3) | ((vec1 & 3) << 2) | ((vec2 & 3) << 4) | (vec3 << 6)
bitcast vector<N/4 x i8> → vector<N x i2>
```

- 兩層 deinterleave 是因為 `vector.deinterleave` 一次只能分奇偶；ext 那邊用兩層 interleave，這裡是鏡像。
- `vec3` 不用 mask：左移 6 之後高位自己掉出去（和 i4 版的 high 不 mask 是同一個理由）。
- `vec0` 不用 shift。所以是 3 個 `andi`、3 個 `shli`、3 個 `ori`、1 個 `bitcast`。

## 4. 為什麼不用 switch

`alignedConversionPrecondition` 在前面已經只放行 2 和 4 兩種寬度，所以 dispatch 寫成三元運算子
（`== 2 ? I2 : I4`），沒有到不了的 `default`。ext 那邊有 `default: return failure()` 是因為它在建任何 op 之前就 switch；
trunc 這邊 switch 之前已經建了 `arith.trunci` 到 i8，在那之後 `return failure()` 會留下孤兒 op，所以不能照抄。

## 5. 驗證（第 4 關證據，可重現）

| 項目 | 結果 |
|---|---|
| `vector-rewrite-subbyte-ext-and-trunci.mlir` | PASS（新增 4 個 case：i8→i2、i32→i2、2-D、unaligned `vector<6xi8>`） |
| `rewrite-narrow-types.mlir` 整合測試（`mlir-runner`，兩條 RUN 都手動跑） | PASS，新增 `@ftrunc_i2` 印出 16 個 bit |
| **窮舉**：256 個 byte 值 → `trunci` → `bitcast` 成 512 個 i1 印出，重寫路徑 vs 不重寫路徑 vs 手算 | **三者相同**，1-D i8／2-D i8／i32 來源各一次（`scratchpad/i2-exhaustive.mlir`） |
| `Dialect/Vector` ＋ `Dialect/Arith` lit | 130/130 |
| `git clang-format HEAD~1` | 乾淨 |

「重寫有沒有真的發生」也查了：重寫後的 IR 裡有 9 個 `vector.deinterleave`（3 個函式 × 3 層）。

## 6. 邊界

- unaligned（尾維不是 4 的倍數）由既有 `alignedConversionPrecondition` 擋掉，patch 沒改它；測試 `@unaligned_trunci_i8_to_i2` pin 住。
- 來源比 i8 寬（i32）先走原本的 `trunci` 到 i8，再進新 helper；測試 `@aligned_trunci_i32_to_i2` pin 住「只剩一個 trunci」。
- n-D：`vector.deinterleave` 只切尾維，所以 2-D 直接可用；測試 `@aligned_trunci_i8_to_i2_2d`。
- scalable vector 由 `commonConversionPrecondition` 擋掉，沒動。
