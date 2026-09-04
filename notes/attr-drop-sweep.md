# 「重建 op 時丟屬性」全樹掃描（2026-09-05）

兩個 agent 平行掃 `mlir/lib`：一個掃 `memref.load/store` 重建，一個掃 `vector.{load,store,maskedload,maskedstore,gather,scatter,expandload,compressstore}` 重建。
判準：來源 op 帶 `alignment`／`nontemporal`／`invariant`，新 op 是同類記憶體 op，且**位址不變**（轉發才成立）。

## 已送出

| PR | 位置 | 屬性 |
|---|---|---|
| #221308 | `AMDGPU/MaskedloadToLoad.cpp` | alignment |
| #221312 | `GPU/DecomposeMemRefs.cpp` | nontemporal／alignment／invariant |
| #221314 | `MemRef/ElideReinterpretCast.cpp:622` | 同上 |
| #221317 | `Vector/IR/VectorOps.cpp` 六個 folder | alignment |
| #221319 | `Vector/VectorLinearize.cpp:687,732` | alignment／nontemporal |
| #221320 | `MemRef/EmulateWideInt.cpp:69,92` | alignment／invariant（nontemporal 已有） |

## 還沒送、轉發無爭議（位址不變）

| 位置 | pattern | 來源 → 新 op | 備註 |
|---|---|---|---|
| `Vector/VectorUnroll.cpp:694` | `UnrollGatherPattern` | gather → gather | base／offsets 不變，只切 index／mask／passthru；`LowerVectorGather.cpp:72` 同樣的 unroll 有轉 |
| `Vector/LowerVectorMask.cpp:270` | `MaskedGatherOpPattern` | `vector.mask { gather }` → gather | 只換 mask |
| `Vector/BufferizableOpInterfaceImpl.cpp:169,212` | gather／scatter bufferize | tensor base → memref base | 同 tensor 的 buffer，offsets／indices 不變 |
| `Vector/VectorTransforms.cpp:1354` | `StoreOpFromBroadcast` | `vector.store` → `vector.store`（1 元素）；隔壁 `memref.store` 分支同款 | base／indices 不變 |

這四個可以併成一個 `[mlir][vector]` PR（gather／scatter 三處）＋ 一個 sink 的小 PR，等 #221317／#221319 的 review 意見再送，避免同一批 reviewer 一次收太多。

## 還沒送、alignment 要重算（位址會移）

| 位置 | 為什麼不能照抄 |
|---|---|
| `Vector/VectorTransforms.cpp:1298` `ExtractOpFromLoad` | index 加上 extract 的位置，`vector<4xf32>` align 16 取第 1 個只剩 4；要 `min(align, offset*elemBytes)`。`nontemporal` 可以照抄 |
| `Vector/VectorUnroll.cpp:740,783` `UnrollLoad/StorePattern` | 每個 tile 不同 offset，只有 offset 0 的 tile 保得住原 alignment |
| `Vector/VectorEmulateNarrowType.cpp` 九處 | i4 → i8 容器，index 換成 linearized；整除的 fast path（:379／:638／:710）byte 位址相同可轉，RMW 路徑會 round down 要重算。此檔已有 `assumeAligned` 模式（#178565）與 byte-alignment 修正（#189235），alignment 敏感 |
| `MemRef/EmulateNarrowType.cpp` 五處 | 同上；:543 是 RMW 的讀回，**絕不能**標 `invariant` |

## 反向要看的

`Vector/LowerVectorGather.cpp:297` `Gather1DToConditionalLoads`：把 gather 的 alignment 抄到每一個 scalar load 上，
但每個 load 的位址是 data-dependent 的 gather index，這是「多抄」而不是「漏抄」。#155683（amd-eochoalo，2025-09）加的。
要先確認 gather 的 alignment 語意是「每個元素」還是「base」，才知道對不對。

## 確認沒問題的

- `FoldMemRefAliasOps`／`FlattenMemRefs`／`ExtractAddressComputations`：走 `updateMemrefAndIndices` 原地改，屬性不會掉。
- `ArmSVE/LegalizeVectorStorage.cpp`：`op.clone()` 後改 operand，屬性保留。
- `VectorToLLVM`、`VectorEmulateMaskedLoadStore`、`VectorToXeGPU` unflatten、`LowerVectorGather.cpp:72,190`：都有轉。
- `LowerVectorTransfer`、`VectorToGPU`、`AffineToStandard`（vector）：來源是 transfer op／affine op，沒有 alignment 可轉。
