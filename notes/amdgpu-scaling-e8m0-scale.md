# #221386：`ArithToAMDGPU` 只在 scale 是 `f8E8M0FNU` 時走 `cvt.scalef32`

分支 `amdgpu-scaling-e8m0-scale`，base `f6a369fa4a57`，head `3cc500a59ae0`，3 個檔案 +134/−30。#217892 的 AMDGPU 側，#215295 的 krzysz00 建議照做。

## 問題

`ArithToAMDGPU.cpp` 的 `ScalingExtFRewritePattern`／`ScalingTruncFRewritePattern` 對 scale 型別零檢查：任何 float scale 都 extf／truncf 到 f32 丟給 `amdgpu.scaled_ext_packed`／`packed_scaled_trunc`，而硬體 `v_cvt_scalef32_*` 只讀 f32 的 bits 31:23（exponent）。scale 是 E8M0 時「值＝exponent」，指令精確；其他型別（f32／f16／bf16／E5M3）尾數被硬體吃掉，等於一種 toward-zero 的捨入。這種 scale 的語意就是 #215295 沒定案的東西——我的 folder #215123 因此只認 E8M0，`arith-expand` 也是先 truncf 到 E8M0（rounding 未定義）。

## 修法

- helper `getF32Scale(rewriter, loc, scale) -> FailureOr<Value>`：
  1. element type 不是 `Float8E8M0FNUType` → failure，兩個 pattern 都 `notifyMatchFailure("scale is not f8E8M0FNU")`。pass 是 greedy rewrite，match 失敗 op 就原樣留下（gfx1100 測試本來就靠這個）。
  2. scale 是 `arith.truncf %x toward_zero : f32 to f8E8M0FNU` → 直接回 `%x`（peephole，krzysz00 講的「fold in a truncf toward_zero」）。為什麼精確：E8M0 的 byte k 代表 2^(k−127)，f32 exponent field k 也是 2^(k−127)，硬體讀 bits 30:23 就是在讀那個 byte；toward_zero 截斷＝丟尾數＝硬體行為。只認 f32 來源（f64 不算）、只認 `toward_zero`（預設 rounding 不折，測試 `@scale_truncf_default_rounding_not_folded`）。
  3. 否則 `arith.extf` 到 f32（原本的路）。
- 兩個 pattern 各刪掉 `scaleType`／`scaleVecType`／`f32` 三個變數（不刪會 `-Wunused-variable`，ninja log 確認 0 warning）。

## 測試

- 四個 `long_*_broadcast`（extf／truncf 各兩個）本來用 f32 scale，是 `blockSize == 32` 多 slice 迴圈的唯一覆蓋；改成 E8M0 argument ＋ E8M0 broadcast，形狀不變，CHECK-COUNT 照舊。
- 新負向：extf 的 `vector<4xf32>`、`f16`；truncf 的 `vector<4xf32>`、`bf16`。`CHECK-NOT: amdgpu.*` 夾住 `CHECK: arith.scaling_*`。
- 新 peephole：extf／truncf 各一個 scalar 案例，`CHECK-NOT: arith.truncf`／`arith.extf`，指令直接吃 `%arg1`。
- ArithToAMDGPU 8 個檔全過。樹裡其他用 scaling op 的測試（XeGPU 整合、Linalg）都不跑這個 pass。

## 答辯

- **這是行為改變，不是純 bug fix**：f32 scale 的使用者原本能拿到硬體指令，現在拿到留在原地的 `arith.scaling_*`，要自己在後面接 `arith-expand`（XeVM pipeline 就是這樣接，`includeF8E8M0 = true`）。樹內沒有任何 pipeline 跑這個 pass，所以樹內零影響；樹外（IREE）要問 krzysz00。PR body 與 ping 都主動講了，並提出替代方案：pass 自己展開成 mulf／divf（他在 issue 上的原話是 "reject ... then fold away"，所以先做 reject）。
- **為什麼不在這裡展開**：展開的語意就是 #217892 在改的東西（`in / scale` 用整個值），放進 conversion pass 等於在兩個地方定義 arith 語意；留給 `arith-expand` 一處決定。
- **與 #217892 的關係**：#217892 讓 generic expansion 用 scale 的值；那之後硬體路徑對非 E8M0 就會跟 generic 路徑算出不同的值，這個 PR 就是把硬體路徑限制在它精確的型別上。兩個 PR 獨立可 merge：這個先進，現況（truncf-to-E8M0 語意）下也是「不在 conversion 裡替 #215295 定案」。
- **truncf toward_zero 目前 `arith-expand` 會拒收**（`ExpandOps.cpp:640` 遇到 roundingmode attr 就 bail）：所以走 generic 路徑的人現在還寫不了 `toward_zero`。這是另一個小 patch（bit-extract 本來就是 toward zero，該接受），列入候選。
