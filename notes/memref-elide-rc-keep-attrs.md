# `memref-elide-reinterpret-cast` 重建 `memref.load` 時丟掉三個屬性

**檔案**：`mlir/lib/Dialect/MemRef/Transforms/ElideReinterpretCast.cpp`（`RewriteLoadFromReinterpretCast`，原 :622）
**測試**：`mlir/test/Dialect/MemRef/elide-reinterpret-cast-load.mlir`
**PR**：[#221314](https://github.com/llvm/llvm-project/pull/221314)，分支 `memref-elide-rc-keep-attrs`，head `c63ecc0da80d`，+18/−1
**開工**：2026-09-05

---

## 一句話

`memref.reinterpret_cast` 只插入或拿掉 unit dim 時，這個 pattern 把 `memref.load %rc[...]` 改寫成直接讀
`%src`，index 對應到非 unit 的維度。重建用的是 `replaceOpWithNewOp<memref::LoadOp>(op, rcInput, rcInputIdxs)`，
只有 memref 和 index，`nontemporal`／`alignment`／`invariant` 三個屬性全掉。和 #221312（`gpu-decompose-memrefs`）同款。

## 重現

| 輸入 | 修前 | 修後 |
|---|---|---|
| `memref.load %rc[%c0, %c0, %i] alignment(16) nontemporal(true) invariant(true)` on `memref<1x1x8xf32>` | `memref.load %src[%c0, %i] : memref<1x8xf32>` | `memref.load %src[%c0, %i] alignment(16) nontemporal(true) invariant(true)` |

## 為什麼轉發是對的

要能答的是：**改寫前後讀的是同一個位址嗎？**
- pattern 的前提 `getNonUnitDimMapping(rc)`：offset 是 0、非 unit 的維度順序與大小一致、stride 靜態。
  它只允許「插 unit dim」或「拿掉 unit dim」，unit dim 的 index 必為 0（`areIndicesInBounds` assert）。
- 所以 `%rc[i0, ..., ik]` 與 `%src[remapped]` 是同一個元素、同一個 byte address。
- `alignment` 是「這個位址對齊到 N」；`nontemporal` 是「不要留在 cache」；`invariant` 是「這塊記憶體在函式內不變」。
  三個都是對「這次存取」的描述，位址沒變，描述就仍成立。

## 什麼沒動
- `CopyToLoadAndStore`（:426）從 `memref.copy` 造 load／store：`memref.copy` 本來就沒有這些屬性，沒東西可轉。
- 負向測試（offset 非 0、動態 shape／stride、非 unit dim 順序不同）完全不受影響，pattern 根本不會進到重建那行。

## 驗證
- repro 修前三個屬性全掉、修後齊全。
- `Dialect/MemRef` lit 33 個全過；clang-format 乾淨。
- 新測試 `@expand_keeps_load_attrs` 放在正向測試區的最後，CHECK 整行含三個屬性。

## Reviewer 可能問
- **「為什麼只有 load？」** 這個檔案只有 load 的改寫 pattern；store 走的是 `CopyToLoadAndStore`，來源是 copy，沒有屬性。
- **「alignment 會不會因為 index 對應而失效？」** 不會，位址相同；alignment 是位址的性質，不是 memref type 的性質。
- **「用 builder 還是 setAttr？」** 用帶三個屬性的 TableGen builder，和 #221312 一致，一個 create 呼叫就完成，不用先建再 set。
- **「為什麼 ping ioghiban／banach-space？」** 檔案七次 commit 有五次是 ioghiban，三個 PR 都是 banach-space approve。
