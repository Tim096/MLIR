# Review 後續回覆草稿：#237342、#233860、#245951

狀態：三則都於 2026-11-26 已貼，全部是 COMMENT：#237342（pullrequestreview-6074006080）、#233860（pullrequestreview-6074006329）、#245951（pullrequestreview-6074003065）。
APPROVE 送不出去：API 回 422 `Can not approve a pull request without explicit repository access`。沒有 commit access 之前只能用 COMMENT（內文寫 LGTM）。

本機分支 `review/batch-1126`（`review/batch-1125` 上還原 #233860／#245951 舊版，再套三個 PR 的新版 diff，一次 build）。
lit：`mlir/test/Dialect/{Arith,EmitC}`、`Analysis/DataFlow`、`Conversion/{ArithToLLVM,ArithToEmitC}`、兩個新的 integration 測試，共 67 個全過。
驗的 head：#237342 `e67542df70`、#233860 `e898003481`、#245951 `bf2b3bf6dc`。基底仍是本機 11-16 的 main，不是各 PR 自己的基底。

---

## #237342（edisongz）——作者把 Tim096 加進 requested reviewers

作者回覆：加了 `@muli_divisor_overflow` 測試；`addi`／`subi` 另開 follow-up PR。

查證：
- `mlir/lib` 的 diff 與 11-25 驗過的那版逐行相同，只多了測試。
- 新測試在本機通過，輸出 `udiv = 9223372036854775808, sdiv = 9223372036854775808`。

要貼的內容（原訂 APPROVE，實際以 COMMENT 貼出）：

The new test passes here and the implementation is unchanged from what I checked. LGTM.

---

## #233860（dashygo097）

作者回覆：拿掉 `NOTE: TO BE WRITTEN`、還原空行；#233536 先進的話改用它的 helper，保留 zero／signed 兩個檢查。

查證：
- `mlir/lib` 的 diff 與舊版相比只差三行：兩個空行不再被刪、區塊註解換了。fold 的程式碼沒變，所以 159 組的窮舉結果仍適用，沒有重跑。
- 新註解有錯字：`interger`。

要貼的內容（原訂 APPROVE，實際以 COMMENT 貼出）：

Thanks. The fold itself is unchanged from what I checked and the tests pass. One typo in the new comment: `interger`. LGTM.

---

## #245951（yuanyiboyyb）——作者問了一個問題

作者的問題：現在用 `math.copysign` 讀正負號，動態形狀要 splat 出常數 tensor（可能變暫存 buffer）。要不要另外加 `math.signbit` 來省掉，還是這個 PR 維持 copysign？

新版改了什麼：PR 由 +236 變 +493。unranked tensor 走新路徑：`shape.shape_of`＋`shape.num_elements` 算元素數，`tensor.splat` 出一維常數，再 `tensor.reshape` 回 unranked。pass 多依賴 Math、Shape、Tensor 三個 dialect。

查證：
- 98 個結果（{+0, −0, 1, −1, NaN, +inf, −inf} 兩兩 × max／min）用 `mlir-runner` 實跑，仍與 `llvm.maximum`／`llvm.minimum` 逐 bit 相同（NaN 只比是不是 NaN）。
- 昨天的重現檔（`tensor<*xf32>`）現在可以展開；`tensor<?x4xf64>`、`vector<[4]xf32>`、f16／bf16／f80／f128 也都展開。
- unranked 展開後的 shape op：只跑 `--convert-shape-to-std` 會留下 `shape.num_elements`；前面加 `--shape-to-shape-lowering` 才全部降掉。
- **沒驗到**：unranked 的執行結果。`convert-elementwise-to-linalg`＋`one-shot-bufferize` 在 unranked 的 `arith.select` 就失敗（`only i1 condition values are supported`），這跟 PR 無關，但表示 unranked 路徑只看得到 IR，跑不起來。PR 的 integration 測試也只有 static 與 dynamic，沒有 unranked。
- 試過「不用 splat」的替代寫法（`uitofp(cmpf true)` 當 1.0）：純量算得對，但 `arith.uitofp` 在 unranked tensor 上會讓 verifier assert（見 TODO），所以不能拿來建議。

要貼的內容（event = COMMENT）：

I ran the new version. The tests pass, the 98 scalar results still match `llvm.maximum`/`llvm.minimum`, and the unranked case from my last comment expands now.

On your question: I would keep `math.copysign` for this PR. `math.signbit` would be a new op with its own lowerings, and that is better discussed separately.

One thing about the unranked path: it emits `shape.shape_of` and `shape.num_elements`, and `--convert-shape-to-std` on its own leaves the `shape.num_elements` behind (it goes away with `--shape-to-shape-lowering` before it). So with unranked tensors `arith-expand` now needs the Shape lowerings after it. Whether that dependency is fine for this pass is for the maintainers to say, not me.
