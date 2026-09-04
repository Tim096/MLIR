# `gpu-decompose-memrefs` 丟掉 `memref.load`／`store` 的屬性

**檔案**：`mlir/lib/Dialect/GPU/Transforms/DecomposeMemRefs.cpp`（`FlattenLoad` 第 145 行、`FlattenStore` 第 168 行）
**測試**：`mlir/test/Dialect/GPU/decompose-memrefs.mlir`
**開工**：2026-09-05
**分支**：`gpu-decompose-memrefs-keep-attrs`，base `f6a369fa4a57`

---

## 一句話

這個 pass 把 `gpu.launch` 裡的 `memref.load %m[%i, %j, %k]` 改成「算線性 offset → `reinterpret_cast` 成 0-d memref → `memref.load %p[]`」。
重建時只傳新 memref，`memref.load` 的 `nontemporal`／`alignment`／`invariant` 和 `memref.store` 的 `nontemporal`／`alignment` 全掉。

---

## 為什麼屬性可以直接轉傳

- `reinterpret_cast` 的 offset 就是原本 indices 的線性化，存取的是同一個元素、同一個型別 → `alignment` 是位址的性質，成立。
- `nontemporal`（別留在 cache）與 `invariant`（kernel 期間記憶體不變）是存取本身的性質，與定址方式無關。
- 丟掉的後果：`invariant` 掉了就少一次 `!invariant.load` metadata，`nontemporal` 掉了就少 `!nontemporal`，都是效能提示；`alignment` 掉了退回 element 對齊。

## 為什麼用 attr 版 builder
- 手寫的 ODS builder 只收 `(bool nontemporal, MaybeAlign alignment)`，**沒有 `invariant`**。
- TableGen 生的 attr 版 `build(..., BoolAttr nontemporal, IntegerAttr alignment, BoolAttr invariant)` 是唯一一個三個都收的；body 是 `if (attr) props.x = attr`，null 沒事，也保留「沒寫」與「寫 false」的差別。
- overload 不會歧義：`Attribute::operator bool` 是 explicit，`TypeRange(ValueRange)` 也是 explicit，五參數的呼叫只有這一個候選。
- 若 reviewer 偏好 bool 版（`EmulateWideInt.cpp:71` 的寫法），`.h.inc` 也有 `(Value, ValueRange, bool, IntegerAttr, bool)`，一行可換。

## 語法注意
#217274（2026-08-20）之後 `memref.load`／`store` 是 strict property assembly：`{nontemporal = true}` 放 attr-dict 會 parse error，要寫 `memref.load %m[%i] alignment(16) nontemporal(true) invariant(true)`，印出來也是這個順序。

---

## 驗證

| 項目 | 結果 |
|---|---|
| 重現（舊 binary） | load／store 的屬性改寫後全掉 |
| 重現（新 binary） | 兩處 `alignment(16)` 都在，連同 `nontemporal(true)`／`invariant(true)` |
| lit | `Dialect/GPU` 41 個全過；新 CHECK 在舊 binary 上會在 store 那條失敗 |
| clang-format | 乾淨 |

---

## Reviewer 可能問

- **「in-tree 誰用？」** 沒有 pipeline 用，只有它的 lit。`Passes.td` 說這是給「memref 降成裸指標」的 SPIR-V 類目標用的，作者 Ivan Butygin（Hardcode84，numba-mlir）。誠實講。
- **「discardable attr 也掉了？」** 是，但那是 `replaceOpWithNewOp` 的一般行為，不在這題範圍。
- **「`ElideReinterpretCast.cpp:622` 同樣的問題？」** 是同款，已另開為 #221314（2026-09-05）。
- 可能的 reviewer：Hardcode84、kuhar、krzysz00。
