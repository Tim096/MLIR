# playground — 隨手試 IR 的地方

放在**本 repo** 而不是 `~/llvm-project`，理由是後者是上游原始碼，
在那裡亂丟檔案會讓 `git status` 一團亂，送 PR 時很容易誤 `git add` 進去。

## 怎麼用

開著任一個 `.mlir` 檔，按 **`Ctrl+Shift+B`** → 會先建置 `mlir-opt`（沒改東西約 1 秒）
再把這個檔丟進去跑 `--canonicalize`。

其他跑法在 **Terminal → Run Task**（Ctrl+Shift+P → `Tasks: Run Task`）裡：

| 任務 | 用在什麼時候 |
|---|---|
| 執行目前的 .mlir (canonicalize) | 看某段 IR 會被折成什麼 |
| 執行目前的 .mlir (不套 pass) | 只想確認語法／verifier 有沒有過 |
| 執行目前的 .mlir (印出每個 pass 後的 IR) | 折疊結果跟預期不符，要看是哪一步出的事 |
| 🧪 跑目前這個 lit test 檔 | 寫完 test 要驗 |
| 📤 送 PR 前：完整檢查 | 格式 + 全套測試 |

## 檔案

- `scratch.mlir` — 隨便改，**不進版控**（見 `.gitignore`）
- `templates/` — 有用的範本，這些**會**進版控

## 兩個常踩的坑

1. **改完 C++ 一定要重建再測。** 拿舊的 `mlir-opt` 測新程式碼會得到完全錯誤的結論，
   而且看起來很像真的。預設任務刻意設計成「先建置再執行」就是為了這件事。
2. **`arith.constant` 的型別要寫對。** `%c = arith.constant 7 : i8` 跟 `: i32`
   走的是不同的溢位邊界，測 MININT 相關行為時特別容易搞錯。
