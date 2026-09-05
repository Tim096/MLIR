# fastmath 全樹掃描（2026-09-05）

一個 agent 掃 arith／math／complex／vector 的 FP 改寫，分兩類：A「新 op 沒接來源的 fastmath」（安全但少最佳化，跟 alignment 漏傳同款）、B「新 op 多了來源沒有的 flag」（語意問題）。

## 已送

| PR | 位置 | 類型 |
|---|---|---|
| #221384 | `ComplexOps.cpp` add／sub／exp fold | 比 B 更糟：不看 flag 就做只有 flag 才合法的 fold |

## 值得送、順序

1. `Math/Transforms/AlgebraicSimplification.cpp:221-239` `PowIStrengthReduction<FPowIOp>`：`buildMul` 的 complex 分支轉 `getFastmathAttr()`，float 分支沒轉（跟 `MulIOp` 綁在同一個 else）；`DivOpTy` 同。同檔 `PowFStrengthReduction` 與 `ExpQuotientStrengthReduction` 都轉得很仔細，作者顯然想轉。一行。
2. `Arith/Transforms/ExpandOps.cpp:894` `MulFOp::create(b, absF32, cInv256, nullptr)`：同檔八處都傳 `op.getFastmathAttr()`，這處明寫 `nullptr`。`:439`／`:545`／`:557-558`／`:891`／`:310` 同檔漏轉。
3. `Conversion/MathToLibm/MathToLibm.cpp:113-123` `PromoteOpToF32`：把 f16 math op 升到 f32 重建**同一個 op**，flag 沒帶；`PolynomialApproximation.cpp:349` 同款 helper 用 `op->getAttrs()`。
4. `Arith/Transforms/ExpandOps.cpp:192-241` maximumf／minimumf／maxnumf／minnumf 展開：cmpf 沒接 flag，而且來源有 `nnan` 時整段 NaN 修補（`isNaN` cmpf ＋ select）是死的，同檔 `F8E8M0ExtFOpConverter:470-482` 有跳過的先例。這個比前三個有料。
5. `ComplexOps.cpp:218` `FoldComponentNeg`、`ComplexToStandard.cpp:600,858`：`complex.neg`／`conj` 轉 `arith.negf` 沒帶 flag。negf 精確，價值低。

## 不要碰 / 不是 bug

- `PolynomialApproximation.cpp` 全檔零 fastmath：多項式近似不是同一個運算，`nnan`／`ninf`／`afn` 不能機械轉；要談的是只轉 `contract`／`reassoc`／`arcp`，這是設計討論。
- `Math/Transforms/ExpandOps.cpp` 十二個 converter：`rsqrt`／`fma`／`tan`／`exp2` 可直轉（`convertFmaFOp` 拆成 mul+add 還丟了 `contract`，等於倒退），但 `tanh`／`powf` 造出新的中間值，要學 `ExpQuotientStrengthReduction` 清掉 `nnan|ninf`。要送就只送前四個。
- `EmulateUnsupportedFloats`／`ExtendToSupportedTypes` 給 extf/truncf 加 `contract`：故意的，那是讓 `ExtFOp::fold` 把 round-trip 折掉的鑰匙。
- `TruncFSIToFPToSIToFP`：sitofp 沒有 fastmath 可接。
- `LowerVectorMultiReduction`：`vector.multi_reduction` 本身沒有 fastmath 屬性，要先改 td；`vector.outerproduct`／`vector.fma` 同。這是「加屬性」的 feature，不是 bug。
- `MathToFuncs`：outlined function 按型別快取，flag 沒地方放。
- `ArithToLLVM`／`MathToLLVM`／`ArithToSPIRV`／`ComplexToStandard` 主體：都對。
