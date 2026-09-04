# `gpu.subgroup_mma_elementwise` 降到 NVVM：補 8 個運算、拒收 2 個、擋 packed fragment

**檔案**：`mlir/lib/Conversion/GPUToNVVM/WmmaOpsToNvvm.cpp`（`createScalarOp`、`WmmaElementwiseOpToNVVMLowering`）
**測試**：`mlir/test/Conversion/GPUToNVVM/wmma-ops-to-nvvm.mlir`、新檔 `gpu-to-nvvm-invalid-wmma-elementwise.mlir`、整合測試 `Integration/GPU/CUDA/TensorCore/wmma-matmul-f16-elementwise.mlir`
**開工**：2026-09-05

---

## 一句話

`gpu.subgroup_mma_elementwise` 的 enum 有 15 種運算，NVVM 只實作 5 種（`addf`／`mulf`／`divf`／`maxf`／`minf`），
其他 10 種走 `default: llvm_unreachable("unknown op")`，整個 `mlir-opt` abort。SPIR-V 那側 12 種都有，缺的會 `notifyMatchFailure`。
`convert-vector-to-gpu` 會把 `arith.subf`／`negf`／`truncf`… 全部轉成這些 op，所以 matmul 後面接一個 bias 減法的 kernel，
在 `-gpu-lower-to-nvvm-pipeline` 就直接崩。

---

## 為什麼 15 種不是全部補上——PTX ISA 兩條規則

**規則一：「Manipulating fragment contents」**（PTX ISA §9.7.15.4.1 末尾）
> 可以直接讀寫 fragment 的各個暫存器，條件是：所有元素用同樣的參數一致地運算，且元素順序不變。

所以 `subf`／`negatef`／`addi`／`subi`／`muli`／`divs`／`divu`／`negates` 逐暫存器做是合法的，
跟既有的 `addf`／`mulf` 是同一種做法。

**規則二：同一段的最後一句**
> 「.f16 與 .f32 累加器 fragment 之間的型別轉換，兩個方向都不支援。即使 fragment 內元素順序不變，結果也是未定義。」

所以 `extf`／`truncf` 在 WMMA 路徑上**不可能正確實作**——不是我們懶得做，是硬體規格說沒有這件事。
也對得上 fragment 形狀：f16 累加器是 4 個 `vector<2xf16>`，f32 累加器是 8 個 `f32`，暫存器數都不一樣。
正確做法是 `notifyMatchFailure`，讓 `-convert-gpu-to-nvvm` 用「failed to legalize」的錯誤停下來，而不是 abort。

### 為什麼不去改 `convert-vector-to-gpu` 不要產生 `extf`／`truncf`
它是 target-agnostic 的；SPIR-V 的 cooperative matrix 有 `OpFConvert`，這兩個 op 在那條路是合法而且有測試的
（#182499 加 `truncf` 時就只做了 VectorToGPU ＋ SPIR-V）。該拒收的地方是 NVVM lowering。

---

## 第三個問題：packed fragment

`addf` 在 `mma_matrix<16x8xf32, "AOp">`（tf32）上今天不是崩，是產生 `llvm.fadd` on `i32` 然後 verifier 報錯。
原因：`inferMMAType` 給 tf32 multiplicand 的暫存器型別是 `i32`（存 tf32 bit pattern），s8／u8 multiplicand 也是 `i32`（一個暫存器塞 4 個元素）。
逐暫存器做算術在這些 fragment 上算的是錯的東西（整數加法會跨元素進位）。

擋法一行：`getElementTypeOrSelf(registerType) != matrixType.getElementType()` 就拒收。
- f16：暫存器 `vector<2xf16>` → 元素 f16 ✓
- f32 COp：`f32` ✓；f32 AOp：`i32` ≠ f32 ✗
- i32 COp：`i32` ✓；si8 AOp：`i32` ≠ si8 ✗
- f64：`f64` ✓

---

## 改了什麼

1. `isSupportedElementwiseOp`：`EXTF`／`TRUNCF` 回 false；`matchAndRewrite` 一開頭就檢查，**在建任何 op 之前**就 `notifyMatchFailure`
   （測試的第二條 RUN line 是 `allow-pattern-rollback=0`，先建 op 再失敗會炸）。
2. `createScalarOp`：`default: llvm_unreachable` 改成完整列舉 15 個 case；新增 8 個是 LLVM dialect 一對一的 op
   （`fsub`／`fneg`／`add`／`sub`／`mul`／`sdiv`／`udiv`），`negates` 用 `0 - x`（LLVM 沒有整數 neg）。
   `EXTF`／`TRUNCF` 兩個 case `break` 後 `llvm_unreachable`——現在真的到不了，前面已經擋掉。
3. packed fragment 檢查（上一節）。

---

## 測試

| 測試 | 內容 | 期望 |
|---|---|---|
| `gpu_wmma_elementwise_subf_negatef` | f16 COp，4 個 `vector<2xf16>` | 4 個 `llvm.fsub` ＋ 4 個 `llvm.fneg` |
| `gpu_wmma_elementwise_int` | i32 COp，8 個 `i32`，六種整數運算串起來 | 各 8 個 `add`／`sub`／`mul`／`sdiv`／`udiv`，`negates` 是 `constant 0` ＋ `sub` |
| invalid：`extf`、`truncf` | | `failed to legalize operation 'gpu.subgroup_mma_elementwise'` |
| invalid：`addi` on si8 AOp、`addf` on f32 AOp | packed | 同上 |
| 整合測試 | A[i][j]=j，C[i][j]=i，kernel 算 `-(C - (A·A + C))` | 每列都是 `[0, 120, 240, …, 1800]` |

整合測試走的是 `convert-vector-to-gpu` → `-gpu-lower-to-nvvm-pipeline`，改動前在同一行 `UNREACHABLE` abort（實測 rc=134），
這就是「真實 pipeline 走得到」的證據。用 `gpu.alloc`／`gpu.memcpy` 不用 `host_register` 的原因同 #221248（WSL2 不支援 `cuMemHostRegister`）。

為什麼算式是 `negf(subf(C, D))`：D = A·A + C = 120j + i；C − D = −120j；再取負 = 120j。
`subf` 方向反了會印出 −120j，`negatef` 沒做會印出 −120j，兩個都錯才會抵銷——但那需要 subf 和 negf 同時錯，機率可忽略，而且 lit 測試各自獨立驗證。

---

## Reviewer 可能問

- **「為什麼不用 `NVVM` 的什麼 intrinsic？」** 沒有；WMMA elementwise 本來就是「fragment 拆開逐暫存器做」，既有的五種就是這樣寫的。
- **「`extf`／`truncf` 真的不能做？CUDA 不是有 f16→f32 accumulator 轉換的範例？」** 那是 mma.sync（`nvgpu`）路徑，fragment layout 有文件；WMMA 的 layout 是 opaque，PTX ISA 明文說轉換未定義。
- **「拒收 `truncf` 會不會讓 `cast_f32_to_f16_write` 那條 VectorToGPU 測試的 IR 進不了 NVVM？」** 會，但改動前它是 abort，改動後是明確的 legalize error；VectorToGPU 不知道 target，SPIR-V 路徑照常。
- **「packed 檢查會不會誤擋？」** 只擋 tf32／s8／u8 的 multiplicand；所有累加器（f16／f32／i32／f64）和 f16／f64 multiplicand 都過。
- **「`negates` 為什麼不用 `llvm.neg`？」** LLVM IR 沒有整數 neg 指令，`sub 0, x` 就是 canonical 形式；`arith` 也沒有 `negi`。
