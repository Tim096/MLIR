# #221383：`StoreOpFromBroadcast` 丟掉 `nontemporal`／`alignment`

分支 `vector-sink-store-keep-attrs`，base `f6a369fa4a57`，head `7f333326e7b0`，2 個檔案 +24/−2。

`VectorTransforms.cpp:1354` 附近：一個元素的 `vector.store`（值來自 broadcast）改寫成 broadcast 來源的 `vector.store` 或 `memref.store`，base／indices 原封不動。兩個分支各補 `op.getNontemporal(), op.getMaybeAlign()`。

`memref.store` 的 builder 是 `(value, memref, indices, bool nontemporal, MaybeAlign)`，和 `vector.store` 的 `(value, base, indices, bool, MaybeAlign)` 對稱，所以兩行長得一樣。

測試在 `vector-sink.mlir` 的 `[Pattern: StoreOpFromBroadcast]` 區，一個 scalar 分支（印出 `alignment(16) nontemporal(true)`）、一個 vector 分支（`alignment = 16 nontemporal = true`）。

答辯重點：vector 存一個元素跟 scalar 存同一個位址，對齊當然還成立；`nontemporal` 描述的是這次存取的快取行為，也跟著走。同款：#221319。
