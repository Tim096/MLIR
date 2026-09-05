# LLVM / MLIR 貢獻報告

> 統計日期：2026-09-05  
> 貢獻者：Hung-Kuan Tseng（GitHub：[`Tim096`](https://github.com/Tim096)）

## 結論先看

我目前向 LLVM 官方專案提出過 **25 個程式碼修改**：

- **6 個已正式合併**，成為 LLVM／MLIR 的一部分。
- **3 個已通過 maintainer review**，測試也全部通過，正在等待合併。
- **16 個正在 review**：一個處理不同硬體轉換路徑對 MXFP scale 的解讀分歧，一個補上 2-bit 量化的向量截斷重寫，一個修正向量化時把會越界的讀寫標成安全的判斷，一個修正 GPU tensor core 的 matmul 後面接減法或取負時編譯器直接崩潰的問題，一個修正向量化器把 tensor 切片寫到錯誤位置的問題，一個修正混合精度矩陣乘法折疊產生不合法 IR 的問題，一個修正帶 mask 的向量讀寫經過迴圈展開後產生不合法 IR 的問題，七個修正記憶體存取改寫時遺失對齊與快取提示的問題（其中一個在位址移動後重新計算對齊），一個修正複數運算的化簡在沒有 fast-math 授權時就改變結果的問題。
- 另外提出過 **2 個技術問題報告**；其中 1 個已由我自己修好並合併。

這些工作主要處理 AI compiler 在量化、向量運算和數值轉換時可能遇到的錯誤，包括：

- FP8／MXFP 量化數值被錯誤轉換；
- 極端整數值算出錯誤結果；
- 帶 mask 的向量操作無法經過最佳化流程；
- 同一段程式經過不同硬體轉換流程，可能得到不同答案。

## 成果總覽

| 狀態 | 數量 | 代表成果 |
|---|---:|---|
| 已合併進 LLVM | **6** | FP8、MXFP 常數最佳化、整數邊界、Vector mask、LLVM 浮點核心 |
| 已通過 review | **3** | 跨後端整數正確性、GPU MMA 轉置 store、MemRef 轉型省略時保留存取屬性 |
| Review 中 | **16** | MXFP scale 語意統一、2-bit 向量截斷、向量化 in_bounds 越界判斷、tensor core elementwise epilogue 崩潰、insert_slice 向量化寫錯位置、混合精度 contract 折疊、帶 mask 的向量讀寫展開、AMDGPU／GPU／MemRef／Vector 記憶體存取屬性保留（七項，含位址移動後重算對齊）、複數運算化簡的 fast-math 檢查 |
| 技術 Issue | **2** | 浮點 crash、MXFP 不同 lowering 結果不一致 |

## 已正式合併的 6 項貢獻

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

## 已通過 review、等待合併的 3 項貢獻

### 6. 讓 MXFP 量化操作可以提前算出常數結果

- [PR #215123](https://github.com/llvm/llvm-project/pull/215123)
- 狀態：**已合併**（2026-09-04，merge commit `57807585a6ae`）

如果 MXFP scaling 操作的輸入和 scale 都是常數，MLIR 原本仍會把運算保留到後面的硬體轉換階段。

我加入常數計算功能，讓 compiler 可以提前算出結果並移除不必要的運算。最大一組測試枚舉了 **16,777,216 種輸入組合**，並與另一條 MLIR 轉換路徑及獨立計算結果比較，沒有發現差異。

審核通過後等了 18 天，rebase 到最新 main 並回報 CI 綠燈後當天合併。

### 7. 統一不同 compiler backend 的 ceiling division 結果

- [PR #215696](https://github.com/llvm/llvm-project/pull/215696)
- 狀態：**已 approve、測試全綠、可以合併；等待第二位 maintainer 確認**（2026-09-04 已 rebase 到最新 main，approve 保留）

我在處理前面的極端整數問題時，進一步發現相同的 ceiling division 在不同轉換路徑中並不一致：

- MLIR 直接計算時可能得到正確的負值；
- 轉成 LLVM 或 SPIR-V 後，卻可能因 overflow 得到錯誤的正值。

這表示同一份模型或程式，可能因選擇不同 backend 而得到不同答案。我把 Index、Affine、LLVM、SPIR-V 與數值範圍分析的相關實作統一成相同的正確演算法。

## 正在 review 的 16 項貢獻

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

### 10. 讓轉置的向量寫入也能用 GPU tensor core 的 MMA store

- [PR #221248](https://github.com/llvm/llvm-project/pull/221248)
- 狀態：**已 approve、測試全綠、等待合併**（送出當天由轉置 load 的原作者 approve）
- 修改範圍：MLIR VectorToGPU（GPU codegen）

MLIR 把向量運算轉成 GPU tensor core 指令時，轉置的向量讀取從 2026 年 2 月起就能直接對應到硬體的轉置 load，但轉置的向量寫入還是被整個放棄。擋住它的是一行 2021 年留下的 TODO，說要等 GPU dialect 加上 transpose 屬性；那個屬性 2022 年就加了，NVVM 與 SPIR-V 兩個後端也都會讀。

我讓寫入側用和讀取側相同的判斷，並把屬性設上去。驗證除了 MLIR 完整測試 **3965 passed、0 failed**，還把轉出來的結果繼續往 NVVM 降，確認最後的 `wmma.store` 拿到 column-major layout；並新增一個 tensor core 整合測試，在本機 RTX 3070 上實際執行，確認寫回的矩陣就是輸入的轉置。這是我第一個 GPU codegen 的 patch，也是第一個在真實 GPU 上驗證過的。

### 11. 修正向量化時把會越界的讀寫標成安全

- [PR #221268](https://github.com/llvm/llvm-project/pull/221268)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Vector utils（`affine-super-vectorize` 使用）

MLIR 的 affine 向量化在產生向量讀寫時，只要 memref 的維度能被向量寬度整除，就把讀寫標成「一定不越界」，完全不看索引。索引有偏移（例如 `A[i + 1]`）或迴圈起點沒對齊時，最後一個向量會讀寫到 memref 之外，而這個「不越界」的標記會讓後端直接發出沒有遮罩的 load／store。

我從數學上補齊了缺少的條件（索引必須是向量寬度的倍數），並用一個遞迴走訪常數、迴圈變數與 affine 運算的判斷實作它，讓 tiling 後的迴圈仍能被認出是對齊的，既有的最佳化結果不退化。這題原本是候選清單上的「清 TODO」，動手時發現是可重現的錯誤，並找到上游測試裡一個本來就期望錯誤結果的 CHECK。

### 12. 修正 GPU tensor core 的 matmul 接上 elementwise 運算時編譯器直接崩潰

- [PR #221288](https://github.com/llvm/llvm-project/pull/221288)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR GPUToNVVM（GPU codegen、mixed precision）

MLIR 的 GPU dialect 定義了 15 種可以直接套在 tensor core 矩陣片段上的 elementwise 運算，向量層會把 matmul 後面的減法、取負、型別轉換等都轉成它們。但降到 NVIDIA 後端的程式碼只實作了 5 種，其餘 10 種走到一行「不可能到達」的斷言，整個編譯器 abort；SPIR-V 後端則 12 種都有。

我對照 PTX ISA 的規格分成兩類處理：8 種算術運算按規格允許的方式逐暫存器實作；f16 與 f32 之間的轉換在規格裡明寫結果未定義，因此改成明確拒收並給出可讀的錯誤。同時補上一個檢查，擋掉把 4 個 int8 塞在一個暫存器裡的 packed 片段，這類片段之前會產生型別錯誤的 LLVM IR。驗證包含新的 lit 測試、負向測試，以及一個在本機 RTX 3070 上實際執行的 tensor core 整合測試：它在修正前於同一行 abort，修正後印出正確的矩陣。

### 13. 修正向量化器把 tensor 切片寫到錯誤位置的問題

- [PR #221293](https://github.com/llvm/llvm-project/pull/221293)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Linalg vectorizer（tensor layout、vectorization）

MLIR 的向量化器把 `tensor.insert_slice`（把一個小 tensor 放進大 tensor 的某個位置）轉成一次向量讀取加一次向量寫入。這個轉換只在「每個元素間距為 1、而且小 tensor 對到大 tensor 最內層的維度」時才和原本的語意相同，但程式碼完全沒檢查這兩個條件：帶間距的 insert 會被寫成連續的幾列，把 8×4 的 tensor 放進 8×1×4 的中間維度時只有第一列被保留。編譯器不報錯，程式輸出直接是錯的。

同一個檔案裡較舊的 pad 專用 pattern 本來就有這兩個檢查，新的一般化版本漏掉了。我把檢查補回前置條件，並用 `getDroppedDims` 的配對方向證明「丟掉的維度全在最前面」正好等於「對到最內層維度」，所以既有能正確向量化的案例全部保留。驗證包含三個新的 lit 測試（兩個負向、一個正向）與完整的 MLIR 測試套件。

### 14. 修正混合精度矩陣乘法折疊產生不合法 IR 的問題

- [PR #221298](https://github.com/llvm/llvm-project/pull/221298)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Vector dialect transforms（vectorization、mixed precision）

MLIR 有一個最佳化會把矩陣乘法兩個輸入上的型別擴展（例如 f16 擴成 f32）折進 `vector.contract`，讓 GPU tensor core 直接用混合精度指令運算。這個最佳化只檢查兩邊「都有擴展」，沒檢查兩邊是從同一種型別擴展出來的：一邊從 i8、另一邊從 i16 擴展時，折疊後的 `vector.contract` 兩個輸入型別不同，違反 op 本身的定義，整個 pass 直接失敗。f16 與 bf16 混用也一樣。

我補上一個來源型別的比較，不一致就不折疊、保留原本的擴展。比較的粒度對齊 `vector.contract` verifier 的實際要求（只要求 element type 相同，形狀與 scalable 可以不同），所以既有能折疊的案例全部保留。驗證包含兩個新的負向 lit 測試與完整的 MLIR 測試套件。

### 15. 修正帶 mask 的向量讀寫經過迴圈展開後產生不合法 IR 的問題

- [PR #221307](https://github.com/llvm/llvm-project/pull/221307)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR VectorToSCF conversion（vectorization、masking）

MLIR 把多維向量讀寫降成迴圈的轉換，沒有檢查這個讀寫是不是被 `vector.mask` 包住。`vector.mask` 的區塊只允許放一個操作，轉換卻把展開後的緩衝區、迴圈和低維讀寫全部塞進去，verifier 直接拒絕，整個 pass 失敗；而且展開出來的讀寫完全沒帶 mask。五條轉換路徑（漸進式、完全展開、一維、scalable 轉置、tensor）都重現。

正確的順序是先把 `vector.mask` 降成讀寫本身的 mask operand，再做迴圈展開，MLIR 內建的整合測試都是這樣排的。我讓五個 pattern 在遇到被 mask 包住的讀寫時明確拒絕，交給前一個步驟處理，和 MLIR 一週前處理另一個類似前置條件的方式一致。驗證包含四個新的負向 lit 測試（三種 pass 設定都比對）與完整的 MLIR 測試套件。

### 16. 修正 AMDGPU 遮罩讀取改寫時遺失對齊資訊的問題

- [PR #221308](https://github.com/llvm/llvm-project/pull/221308)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR AMDGPU dialect transforms（GPU memory access）

AMDGPU 有一個轉換會把帶 mask 的向量讀寫改成一般讀寫加條件判斷，讓硬體走較快的路徑。這個轉換比讀寫操作的 `alignment` 屬性早一個月寫成，重建操作時沒有把對齊資訊帶過去，最後產生的 LLVM 讀取只能退回元素大小的對齊（f16 向量從 16 bytes 退到 2 bytes），失去原本能用的較寬存取。這是效能損失，不影響結果正確性。

改寫前後存取的位址與寬度完全相同，所以對齊資訊可以直接轉傳。我透過 builder 把它帶過去，寫法與 MLIR 其他轉換一致。驗證包含三個新的 lit 測試（每個重建點各一個）與 LLVM 層輸出的對照。

### 17. 修正 GPU 記憶體存取分解時遺失快取與對齊提示的問題

- [PR #221312](https://github.com/llvm/llvm-project/pull/221312)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR GPU dialect transforms（memory access lowering）

GPU dialect 有一個轉換把 kernel 裡的多維記憶體存取改成「算出線性位址、再做零維存取」，給只支援裸指標的目標（例如 SPIR-V）使用。重建存取時只傳了新的記憶體參考，`nontemporal`（不要留在快取）、`alignment`（對齊）與較新的 `invariant`（kernel 期間不會改變）三個提示全部遺失，後端因此少掉對應的最佳化資訊。

存取的元素與型別在改寫前後相同，三個提示都仍然成立。手寫的 builder 沒有 `invariant` 參數，我改用能帶齊三個屬性的 builder。驗證包含兩個新的 lit 測試與完整的 MLIR 測試套件。

### 18. 修正消除 reinterpret_cast 時遺失記憶體存取提示的問題

- [PR #221314](https://github.com/llvm/llvm-project/pull/221314)
- 狀態：**已 approve（joker-eph，送出後半小時），等待合併**（2026-09-04）
- 修改範圍：MLIR MemRef dialect transforms

MemRef dialect 有一個轉換會把「先用 `reinterpret_cast` 增減單位維度、再讀取」改寫成直接讀原本的記憶體，省掉一層轉型。重建讀取時只傳了原記憶體與對應後的索引，`nontemporal`、`alignment` 與 `invariant` 三個提示全部遺失。這和第 17 項是同一種問題，我在做第 17 項時順手記下這個位置，這一輪補上。

改寫的前提保證前後讀的是同一個元素，三個提示仍然成立，所以用能帶齊屬性的 builder 轉傳。驗證包含一個新的 lit 測試與 MemRef dialect 的全部測試。

### 19. 修正向量記憶體操作在 canonicalization 時遺失對齊資訊的問題

- [PR #221317](https://github.com/llvm/llvm-project/pull/221317)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Vector dialect canonicalization

做完第 17、18 項之後，我把整個 MLIR 程式庫掃了一遍，找所有「重建記憶體操作卻沒把屬性帶過去」的地方，並依「改寫前後位址是否相同」分類（同位址才能直接轉傳）。這一項是其中影響最大的：Vector dialect 的六個 canonicalization 規則（mask 全為真時把帶 mask 的讀寫折成一般讀寫；索引連續時把 gather／scatter 折成帶 mask 的讀寫）都比 `alignment` 屬性早寫成，折疊時對齊資訊全部遺失。canonicalization 幾乎每條編譯流程都會跑，所以下游只要標了對齊，經過這一步就會退回元素對齊。

六個規則折疊前後存取的位址相同，我透過各 op 共用的 alignment 介面把屬性轉傳過去，每個規則各加一個測試，並跑完整的 MLIR 測試套件。

### 20. 修正向量讀寫線性化時遺失屬性的問題

- [PR #221319](https://github.com/llvm/llvm-project/pull/221319)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Vector dialect transforms（linearization）

線性化把 `vector<1x1x...xN>` 的讀寫改成 `vector<N>`，只改向量型別，記憶體位址與存取寬度不變，但重建時遺失了 `alignment` 與 `nontemporal`。這個轉換的主要使用者是 Intel 的 XeGPU 流程。修法是把兩個屬性轉傳，並跑 Vector、XeGPU 與 Vector 到 LLVM 的相關測試。

### 21. 補齊寬整數模擬轉換遺漏的屬性

- [PR #221320](https://github.com/llvm/llvm-project/pull/221320)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR MemRef dialect transforms（wide integer emulation）

寬整數模擬把目標不支援的 `i64` 記憶體改成 `vector<2xi32>`，位元組配置完全相同。這個轉換在 2023 年就已經轉傳 `nontemporal`，但後來新增的 `alignment` 與 `invariant` 沒有人接上。修法是在同一個呼叫裡把三個屬性一起轉傳，並補一個測試。

### 22. 修正 gather 在展開與 mask 降階時遺失對齊資訊的問題

- [PR #221382](https://github.com/llvm/llvm-project/pull/221382)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Vector dialect transforms（unrolling、mask lowering）

`vector.gather` 被切成小塊或從 `vector.mask` 裡拆出來時，讀的仍是同一組位址，但重建時遺失了 `alignment`。修法是兩處各透過 builder 轉傳。過程中也確認 bufferization 那一處不需要修：tensor 上本來就不允許帶這個屬性。

### 23. 修正把 broadcast 下沉進 store 時遺失屬性的問題

- [PR #221383](https://github.com/llvm/llvm-project/pull/221383)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Vector dialect transforms（sink patterns）

一個元素的向量 store 會被改寫成純量 store，位址不變，但 `nontemporal` 與 `alignment` 沒有跟著過去。兩個分支各補一行。

### 24. 修正複數運算化簡在沒有 fast-math 授權時就改變結果的問題

- [PR #221384](https://github.com/llvm/llvm-project/pull/221384)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Complex dialect folders

Complex dialect 會把 `(a − b) + b`、`(a + b) − b` 與 `exp(log(a))` 直接化簡成 `a`，不檢查任何 fast-math flag。這三個等式在浮點數下不成立：中間結果會捨入（`(1 − 10³⁰) + 10³⁰` 算出 0），帶號零會被吃掉，`exp(log(a))` 只是近似。我依照 LLVM 對同樣化簡的規則，要求前兩類帶 `reassoc` 與 `nsz`、第三類雙方帶 `afn` 才做，並為每個化簡補上沒有 flag 時不能動的測試。這是這個 dialect 上個月才修過的同一批化簡裡剩下的三個。

### 25. 讓向量讀寫在位址移動後仍保留正確的對齊資訊

- [PR #221385](https://github.com/llvm/llvm-project/pull/221385)
- 狀態：**已送出，review 中**（2026-09-05）
- 修改範圍：MLIR Vector dialect utils 與 transforms（sink、unrolling）

前面幾項都是位址不變、屬性照抄。這一項不同：把大向量的讀寫切成小塊，或只取其中一個元素時，新的存取落在原位址往後一段距離，原本的對齊不能照抄。我加入一個共用的計算：把小塊的偏移量經由記憶體的靜態 stride 換算成 byte 距離，取原對齊與這段距離都滿足的最大 2 的冪；距離或 stride 不是靜態時就放棄。這是 MLIR 裡第一個做這種推導的地方，測試把每個小塊算出來的對齊值逐一列出，並跑完整 MLIR 測試套件。

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
- Linalg／GPU 層：**第一個 GPU codegen patch 已通過 review**（#221248）。

## 對外介紹版本

### 30 秒自我介紹

我是 LLVM／MLIR upstream contributor，目前有 6 個修改已正式合併，另外 2 個已通過 review，4 個在 review 中。我的工作主要處理 AI compiler 的 FP8／MXFP 量化、向量 lowering、GPU codegen 和數值正確性，例如修正 NaN 被轉成 Infinity、不同 backend 算出不同結果，以及極端整數 overflow。我也會用 Alive2、全輸入枚舉和 regression tests 驗證修正，而不只是讓一般測試通過。

### 履歷版本

- Contributed **6 merged patches** to LLVM/MLIR, fixing FP8/MXFP numerical correctness and constant folding, integer overflow edge cases, and masked vector lowering used in AI compiler pipelines.
- Diagnosed and fixed cross-layer inconsistencies spanning MLIR constant optimization, range analysis, LLVM/SPIR-V lowering, and LLVM's core floating-point library.
- Validated compiler transformations with Alive2, independent mathematical oracles, and exhaustive sweeps of up to **16.7 million input combinations**.

## 下一步

1. 推動三個已 approve 的 PR（#215696、#221248、#221314）合併，讓正式 upstream 貢獻由 6 個增加到 9 個。
2. 完成 #217892 的 review，並送出 AMDGPU 硬體路徑的對應修正：只在 scale 已是 `f8E8M0FNU` 時走硬體指令，其餘交給通用展開（設計研究已完成，見 `TODO.md`）。
3. 推進其餘 16 個 review 中的 PR。fast-math 掃描（`notes/fastmath-sweep.md`）還有四個排好順序的候選，`notes/attr-drop-sweep.md` 剩兩組 narrow-type emulation 要重算對齊。
4. 把目前用過的枚舉與語意驗證方法整理成自動化工具，用來系統性尋找更多 compiler correctness bug。

## 一句話總結

> 我已經不只是使用 MLIR 的 AI compiler engineer，而是能直接修改 LLVM／MLIR、找出跨量化、向量與 backend lowering 的底層正確性問題，並把修正通過 upstream review 與完整驗證的 contributor。
