# `memref-emulate-wide-int` 只轉 `nontemporal`，漏 `alignment`／`invariant`

**檔案**：`mlir/lib/Dialect/MemRef/Transforms/EmulateWideInt.cpp`（`ConvertMemRefLoad`／`ConvertMemRefStore`）
**測試**：`mlir/test/Dialect/MemRef/emulate-wide-int.mlir`
**PR**：[#221320](https://github.com/llvm/llvm-project/pull/221320)，分支 `memref-emulate-wide-int-keep-attrs`，head `7b2fa9a73327`，+19/−2
**開工**：2026-09-05

## 一句話

這個 pass 把 `iN`（N 超過目標支援）的 memref 換成 `vector<2xiN/2>`。load／store 重建時傳了 `op.getNontemporal()`
（2023 年 Guray Ozen 加 nontemporal 時順手接的），但 `alignment`（2025-07）與 `invariant`（2025 之後）沒人接。
是「部分轉發」，和其他四個全丟的不同，反而更好答：同一個 create 呼叫裡已經在轉一個屬性了。

## 為什麼轉發是對的

type converter 把 `memref<...xi64>` 變成 `memref<...xvector<2xi32>>`：元素大小一樣（8 bytes）、
layout 一樣、base pointer 一樣，同一組 index 就是同一個位址。alignment 對位址成立、invariant 對記憶體區塊成立。

## 改了什麼

`op.getNontemporal()` 改成 `op.getNontemporalAttr(), op.getAlignmentAttr(), op.getInvariantAttr()`（load）、
`op.getNontemporalAttr(), op.getAlignmentAttr()`（store），走 TableGen 的 attr builder；和 #221312／#221314 一致。

## 驗證

repro 修前只剩 `nontemporal(true)`，修後三個齊全。`Dialect/MemRef`＋`Dialect/Arith`＋`Conversion/MemRefToSPIRV` 69 個 lit 全過。
新測試鏡射既有 `@alloc_load_store_i64_nontemporal`。

## Reviewer 可能問

- **「`alignment(16)` 放在 `memref<4xvector<2xi32>>` 上合法嗎？」** verifier 只要求正的 2 的冪，不跟元素大小綁。
- **「narrow-type emulation 也一樣嗎？」** `EmulateNarrowType.cpp` 五個點全丟，但那邊存取會 round down 到容器元素，
  alignment 要另外論證，這個 PR 不碰（見 `notes/attr-drop-sweep.md`）。
