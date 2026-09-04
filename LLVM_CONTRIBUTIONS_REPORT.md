# LLVM / MLIR 貢獻報告

> 統計日期：2026-09-04  
> 貢獻者：Hung-Kuan Tseng（GitHub：[`Tim096`](https://github.com/Tim096)）

## 結論先看

我目前向 LLVM 官方專案提出過 **9 個程式碼修改**：

- **5 個已正式合併**，成為 LLVM／MLIR 的一部分。
- **2 個已通過 maintainer review**，測試也全部通過，正在等待合併。
- **2 個正在 review**：一個處理不同硬體轉換路徑對 MXFP scale 的解讀分歧，一個補上 2-bit 量化的向量截斷重寫。
- 另外提出過 **2 個技術問題報告**；其中 1 個已由我自己修好並合併。

這些工作主要處理 AI compiler 在量化、向量運算和數值轉換時可能遇到的錯誤，包括：

- FP8／MXFP 量化數值被錯誤轉換；
- 極端整數值算出錯誤結果；
- 帶 mask 的向量操作無法經過最佳化流程；
- 同一段程式經過不同硬體轉換流程，可能得到不同答案。

## 成果總覽

| 狀態 | 數量 | 代表成果 |
|---|---:|---|
| 已合併進 LLVM | **5** | FP8、整數邊界、Vector mask、LLVM 浮點核心 |
| 已通過 review | **2** | MXFP 常數最佳化、跨後端整數正確性 |
| Review 中 | **2** | MXFP scale 語意統一、2-bit 向量截斷 |
| 技術 Issue | **2** | 浮點 crash、MXFP 不同 lowering 結果不一致 |

## 已正式合併的 5 項貢獻

### 1. 讓未來新增運算類型時，更容易被編譯器檢查抓到

- [PR #214622](https://github.com/llvm/llvm-project/pull/214622)｜[upstream commit](https://github.com/llvm/llvm-project/commit/78e17e70bd52058add1b8bfaeafa696b1e4e4cf5)
- 修改範圍：MLIR 算術基礎設施

原本的程式碼會把未處理的運算類型全部放進同一個預設分支。這會讓開發者未來新增類型時，即使忘記更新相關程式碼，編譯器也不一定會警告。

我改成明確列出目前唯一的特殊情況，讓未來的漏接問題能在編譯階段被發現。這是我第一個完整走完 LLVM 提交、review 與合併流程的貢獻。

### 2. 修正 FP8 的 NaN 被錯誤轉成 Infinity

- [PR #214919](https://github.com/llvm/llvm-project/pull/214919)｜[upstream commit](https://github.com/llvm/llvm-project/commit/794aa0fd923acc744f7086d2c77a336dcca6256d)
- 修改範圍：LLVM 浮點函式庫與 MLIR

在特定 FP8 格式 `f8E8M0FNU` 中，NaN 代表資料無效。但 LLVM 在轉換浮點格式時，會把它錯誤轉成 Infinity。

對 AI 量化而言，兩者意義完全不同：NaN 表示該資料區塊無效，Infinity 則可能繼續參與計算並污染後續結果。

我修正 LLVM 的共用浮點轉換邏輯，並枚舉該 FP8 格式全部 **256 種 bit pattern**，確認轉換到 f16、bf16、f32、f64、f128 時都能保留正確的數值類別。

### 3. 修正 signed ceiling division 的極端整數問題

- [PR #214637](https://github.com/llvm/llvm-project/pull/214637)｜[upstream commit](https://github.com/llvm/llvm-project/commit/2a0c335d4538ed8a2739c9b5e006b47652a6a8b0)
- 修改範圍：MLIR 整數運算與數值範圍分析

Signed integer 的最小值（例如 i8 的 `-128`）沒有對應的正值，因此直接把它取負會 overflow。原本 MLIR 的 ceiling division 實作依賴取負，導致許多本來可以計算的常數無法被最佳化。

我重新推導不需要取負的演算法，並同步修正過期的數值範圍分析邏輯。

驗證方式包括：

- 使用 Alive2 做符號層級的正確性驗證；
- 枚舉所有 i4 和 i8 輸入組合；
- i8 無法最佳化的案例由 **507 個降到 1 個**，剩下的是數學結果本身無法用 i8 表示的情況。

### 4. 讓帶 mask 的向量讀寫也能經過 lowering

- [PR #215318](https://github.com/llvm/llvm-project/pull/215318)｜[upstream commit](https://github.com/llvm/llvm-project/commit/1ccdf48548ed47c4e95ed52f4b07796d96a892c6)
- 修改範圍：MLIR Vector

AI compiler 常用 mask 表示「只處理向量中的部分元素」，例如處理 padding 或不規則邊界。

原本 MLIR 在重新排列向量讀寫時，只要操作被 mask 包住，就直接放棄轉換。我補上這條路徑，確保向量重新排列後：

- mask 仍然對應正確的記憶體位置；
- read 操作的預設值也會跟著向量一起重新排列。

這是我第一個 MLIR Vector 貢獻，也代表工作範圍從純量算術進入 AI code generation 常用的向量層。

### 5. 修正 LLVM 無法正確回報 FP8 的數值損失

- [PR #216056](https://github.com/llvm/llvm-project/pull/216056)｜[upstream commit](https://github.com/llvm/llvm-project/commit/898b0188d9016c310629e53383c56365f6ee861a)
- 解決我提出的 [Issue #215445](https://github.com/llvm/llvm-project/issues/215445)
- 修改範圍：LLVM 核心浮點函式庫、MLIR parser

部分 FP8 格式無法表示負號或零，但 LLVM 原本仍會宣稱轉換「沒有損失」。這會造成兩種問題：

- 負值可能產生一個無法正常輸出的內部值，最後讓 compiler crash；
- 零可能被靜默換成另一個非零值。

我先找出並回報問題，再修改 LLVM 的 `APFloat` 共用函式庫，讓它正確通知呼叫端「這次轉換損失了資訊」。MLIR 因此能停止不安全的常數最佳化，也能在輸入不合法常數時回報錯誤，而不是 crash。

這是我的第一個主要修改 LLVM 核心函式庫、而不只修改 MLIR 的貢獻。

## 已通過 review、等待合併的 2 項貢獻

### 6. 讓 MXFP 量化操作可以提前算出常數結果

- [PR #215123](https://github.com/llvm/llvm-project/pull/215123)
- 狀態：**已 approve、測試全綠、可以合併**（2026-09-04 已 rebase 到最新 main，approve 保留）

如果 MXFP scaling 操作的輸入和 scale 都是常數，MLIR 原本仍會把運算保留到後面的硬體轉換階段。

我加入常數計算功能，讓 compiler 可以提前算出結果並移除不必要的運算。最大一組測試枚舉了 **16,777,216 種輸入組合**，並與另一條 MLIR 轉換路徑及獨立計算結果比較，沒有發現差異。

目前程式碼與 review 都已完成，只因我沒有 LLVM commit 權限，需要 maintainer 代為合併。

### 7. 統一不同 compiler backend 的 ceiling division 結果

- [PR #215696](https://github.com/llvm/llvm-project/pull/215696)
- 狀態：**已 approve、測試全綠、可以合併；等待第二位 maintainer 確認**（2026-09-04 已 rebase 到最新 main，approve 保留）

我在處理前面的極端整數問題時，進一步發現相同的 ceiling division 在不同轉換路徑中並不一致：

- MLIR 直接計算時可能得到正確的負值；
- 轉成 LLVM 或 SPIR-V 後，卻可能因 overflow 得到錯誤的正值。

這表示同一份模型或程式，可能因選擇不同 backend 而得到不同答案。我把 Index、Affine、LLVM、SPIR-V 與數值範圍分析的相關實作統一成相同的正確演算法。

## 正在 review 的 2 項貢獻

### 8. 同一個 MXFP 操作經過不同 lowering，可能算出不同答案

- [Issue #215295](https://github.com/llvm/llvm-project/issues/215295) → [PR #217892](https://github.com/llvm/llvm-project/pull/217892)
- 狀態：**已送出，review 中**（2026-08-21 送出；maintainer 已回覆一輪，2026-09-04 已處理）

我發現 MLIR 的一般轉換流程與 AMDGPU 流程，對非 2 次方的 scale 有不同解讀。簡單來說，同一個 MXFP 操作可能因為 compiler 選了不同的硬體轉換路徑，而使用不同 scale，最後得到不同數值。

這個問題已促成多位 LLVM maintainer 討論，並進一步查閱 AMD CDNA5 ISA，確認真實硬體也支援非 E8M0 的 scale。

我已送出修正：

- 讓一般轉換流程使用 scale 的實際數值；
- 更新操作文件；
- 補上原本缺少的 FP8 scale 測試與型別邊界檢查；
- 完整 MLIR 測試結果為 **3965 passed、0 failed**。

Review 中 maintainer 進一步指出 AMD 硬體指令只讀 scale 的 sign 與 exponent bits，我據此提出後續 patch 的範圍：只在 scale 格式與硬體語意一致時才使用硬體指令。這項工作完整涵蓋了：發現不同 backend 結果不一致、提出 Issue、查閱硬體規格、參與語意討論、完成實作與驗證。

### 9. 讓 2-bit 量化的向量截斷也走高效路徑

- [PR #221185](https://github.com/llvm/llvm-project/pull/221185)
- 狀態：**已送出，review 中**（2026-09-04）
- 修改範圍：MLIR Vector

低位元量化模型會把權重壓成 2-bit 或 4-bit。MLIR 原本只對 4-bit 的向量截斷做了高效重寫，2-bit 直接放棄，交給 LLVM 自己拼湊；而反方向的 2-bit 解壓早在 2025 年就有人補上。

我補上 2-bit 截斷這一半，把每四個 byte 用兩層 deinterleave 分組、遮罩、移位後合併成一個 byte。驗證方式是把全部 **256 種 byte 值**同時走重寫路徑與原始路徑，用 `mlir-runner` 印出結果逐位比對，並補上整合測試。

## 這些成果證明了什麼能力

### AI compiler 與數值正確性

我不只會使用 MLIR 建立模型編譯流程，也能修改 MLIR 本身，處理量化格式、向量 lowering、整數 overflow 與不同 backend 結果不一致等底層問題。

### 系統性驗證

除了普通單元測試，我也使用：

- 全輸入空間枚舉；
- 獨立數學計算作為比對基準；
- Alive2 形式驗證；
- 故意還原修正，確認新增測試真的能抓到原始錯誤。

### Open-source 協作

我已完成多輪 LLVM upstream review，包含拆分 PR、回覆技術質疑、依 reviewer 意見補強測試、處理 rebase 與跨模組語意討論。目前已有多位 maintainer 審核並合併我的修改。

## 目前進度判讀

長期路線是：

`MLIR 算術與量化 → Vector → Linalg／GPU`

目前狀態：

- LLVM／MLIR 開發環境與 upstream 流程：**完成**。
- 在 Arith／Vector 累積 3～5 個實質 merged patch：**完成，目前已有 5 個**。
- FP8／MXFP 量化與 Vector 經驗：**已有實際 upstream 成果**。
- 自動找 bug 與語意驗證工具：**尚未產品化**，但已在實際 patch 中使用 exhaustive testing 與 Alive2。
- Linalg／GPU 層：**尚未開始**。

## 對外介紹版本

### 30 秒自我介紹

我是 LLVM／MLIR upstream contributor，目前有 5 個修改已正式合併，另外 2 個已通過 review，2 個在 review 中。我的工作主要處理 AI compiler 的 FP8／MXFP 量化、向量 lowering 和數值正確性，例如修正 NaN 被轉成 Infinity、不同 backend 算出不同結果，以及極端整數 overflow。我也會用 Alive2、全輸入枚舉和 regression tests 驗證修正，而不只是讓一般測試通過。

### 履歷版本

- Contributed **5 merged patches** to LLVM/MLIR, fixing FP8/MXFP numerical correctness, integer overflow edge cases, and masked vector lowering used in AI compiler pipelines.
- Diagnosed and fixed cross-layer inconsistencies spanning MLIR constant optimization, range analysis, LLVM/SPIR-V lowering, and LLVM's core floating-point library.
- Validated compiler transformations with Alive2, independent mathematical oracles, and exhaustive sweeps of up to **16.7 million input combinations**.

## 下一步

1. 推動兩個已 approve 的 PR 合併，讓正式 upstream 貢獻由 5 個增加到 7 個。
2. 完成 #217892 的 review，並接著送出 AMDGPU 硬體路徑的對應修正。
3. 推進 #221185 的 review；下一題是 `VectorToGPU` 轉置 store（候選清單第 2 名），開始接觸 GPU codegen。
4. 把目前用過的枚舉與語意驗證方法整理成自動化工具，用來系統性尋找更多 compiler correctness bug。

## 一句話總結

> 我已經不只是使用 MLIR 的 AI compiler engineer，而是能直接修改 LLVM／MLIR、找出跨量化、向量與 backend lowering 的底層正確性問題，並把修正通過 upstream review 與完整驗證的 contributor。
