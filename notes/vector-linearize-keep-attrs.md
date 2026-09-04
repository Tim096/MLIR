# `vector.load`／`store` 線性化時丟掉 `alignment` 與 `nontemporal`

**檔案**：`mlir/lib/Dialect/Vector/Transforms/VectorLinearize.cpp`（`LinearizeVectorLoad`／`LinearizeVectorStore`）
**測試**：`mlir/test/Dialect/Vector/linearize.mlir`（`-test-vector-linearize`）
**PR**：[#221319](https://github.com/llvm/llvm-project/pull/221319)，分支 `vector-linearize-keep-attrs`，head `2bb26b72e617`，+28/−4
**開工**：2026-09-05

## 一句話

`vector<1x1x...xN>` 的 load／store 被改成 `vector<N>`，重建只傳 `adaptor.getBase()`／`getIndices()`，
兩個屬性都掉。這兩個 pattern 是 #145115（nbpatel，2025-07-14）加的，和 `alignment` 屬性（#144344，2025-07）同期，
但當時沒接上。

## 為什麼轉發是對的

base、indices、存取的 byte 數全部不變，只是 vector type 少掉幾個 unit dim。`alignment` 是位址性質、
`nontemporal` 是 cache hint，都只看這次存取，所以照抄。

## 驗證

修前 `alignment = 16 nontemporal = true` 全掉；修後兩個都在。`Dialect/Vector`＋`Dialect/XeGPU`＋
`Conversion/VectorToXeGPU`＋`Conversion/VectorToLLVM` 共 145 個 lit 全過（XeGPU 是 linearize 的主要使用者）。

## Reviewer 可能問

- **「用 `getNontemporal()`（bool）還是 `getNontemporalAttr()`？」** custom builder 收 `bool nontemporal, MaybeAlign`，
  所以傳 `loadOp.getNontemporal()` 與 `loadOp.getMaybeAlign()`；和 #221308／#221317 一致。
- **「scalable 的情況？」** pattern 只允許最內層 scalable，其他維度是 1，位址邏輯不變。
