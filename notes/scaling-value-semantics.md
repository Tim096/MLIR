# `arith.scaling_extf` / `scaling_truncf`：scale 是值，不是指數

> 分支 `arith-scaling-value-semantics`，基準 `fb7a3412079f`（2026-08-20）。
> **本地完成、尚未送出**——等 `tgymnich` 在 #215295 表態。
> commit `dade85d185b4`；`check-mlir` 3905 passed / 0 failed、`git clang-format HEAD~1` 乾淨。
> 這份筆記的用途是**讓你不看它也能答辯**，不是存檔。

---

## 1. 一句話

`arith.scaling_truncf(in, scale)` 是 `in / scale`，不是 `in / 2^exponent(scale)`。
今天的 generic expansion 把 scale 先截成 `f8E8M0FNU`，**在非 E8M0 的 scale 上算出錯的值**。

## 2. 為什麼是 `in / scale`（這題是怎麼定的）

兩位 maintainer 給過相反的答案：

| 誰 | 什麼時候 | 說什麼 | 依據 |
|---|---|---|---|
| `tgymnich` | 2026-08-13（#215123） | 取 scale 的 exponent | OCP MXFP 規格定義 MX 的 scale 是 E8M0 |
| `krzysz00` | 2026-08-17（#215295） | **`in / scale`** | AMD Instinct **CDNA5 ISA** §7.12.6（E5M3 scale 是 OCP 的擴充，真實硬體上存在）、§7.6.3（E5M3 scale 的轉換）、§15.14（`scalef32` 指令的精確定義） |

**為什麼後者贏**：規格定義的是 MX 格式的 scale = E8M0，所以那個論證只涵蓋兩人本來就同意的那半
（E8M0 scale 兩種讀法算出來一樣）。**它涵蓋不到分歧的那半**——`f16` / `f8E5M3FNU` 的 scale
在 OCP 規格裡根本不存在，而真實硬體吃這種 scale。

> ⚠️ 送出前必須確認 `tgymnich` 已經表態。兩個相反的裁決同時掛在紀錄上，
> 送 patch 等於替他選邊，這是 `Goal.md` 明訂不做的事。

## 3. 改了什麼

兩個 converter（`ExpandOps.cpp`）都不再把 scale 截成 `f8E8M0FNU`，
改成把 scale **cast 到運算實際發生的型別**：

| op | scale cast 到 | 然後 |
|---|---|---|
| `scaling_extf` | result type | `mulf(extf(in), scale)` |
| `scaling_truncf` | input type | `truncf(divf(in, scale))` |

抽出 helper `castFloatValue(b, value, targetTy, fastmath)`：
同型別 → 原值不動；變寬 → `extf`；變窄 → `truncf`；**同寬但不同型 → `failure()`**。

`ArithOps.td` 兩段 description 也改了——**它們原本就寫著舊讀法**
（`%0 = arith.truncf %1 : f32 to f8E8M0FNU`），不改的話文件會跟程式碼打架。

## 4. 為什麼 E8M0 的路徑不會變（實測，不是推論）

送出前用 `mlir-opt --arith-expand=include-f8e8m0` 實跑過：

```
E8M0 scale → bitcast → shli 23 → NaN select → bitcast → extf(in) → mulf
```

沒有任何截斷。原因是今天的程式碼對 8 bit 的 scale **本來就跳過那個 truncf**
（條件是 `bitwidth >= 16`），而 `isa<Float8E8M0FNUType>` 的檢查會放行，
接著就是 `extf` 然後 `mulf`——**那本來就是 `in * scale`**。

所以這個 patch 對 E8M0 scale 是 no-op。**能改的只有兩種 case**，正是今天錯的兩種。

## 5. 對照：f16 scale 今天怎麼算錯

```
f16 scale → extf f32 → bitcast i32 → shrui 23 → trunci i8 → bitcast f8E8M0FNU
```

尾數在 `shrui 23` / `trunci` 這一步被丟掉。`3.0 : f16` 的 scale 在被用到之前就變成 2 的冪。
**這是值算錯，不是 rounding mode 選錯**——換 rounding mode 換不回尾數。

## 6. 那個順手修掉的邊界（今天的程式碼會建出違法 IR）

`arith.extf` 與 `arith.truncf` 的 verifier 都要求**嚴格**變寬／變窄
（`verifyExtOp<FloatType>`）。所以 scale 與目標型別**同寬但不同型**時，兩個都不合法。

今天的程式碼在這種組合下（例如 8 bit 的 `f8E5M2FNUZ` scale 配 8 bit 的 result）
會直接 `arith::ExtFOp::create`，建出過不了 verifier 的 op。
新版明確 `notifyMatchFailure`，並補了兩個負向測試
（`invalid_scaling_extf_equal_width_scale`、`invalid_scaling_truncf_equal_width_scale`）。

## 7. 測試怎麼動的

`expand-ops.mlir` 裡 scale 不是 E8M0 的有 8 個，全部會變：

| 動法 | 測試 |
|---|---|
| 6 個改形狀（原本斷言 `arith.truncf ... to f8E8M0FNU` 那一步） | `scaling_truncf_propagate_rounding_mode_fast_math`、`scaling_truncf_f16_to_f4E2M1FN_using_f16_scales`、`scaling_truncf_vector_f16_to_f4E2M1FN_using_f16_scales`、`scaling_extf_to_f32_using_f16_scales`、`scaling_extf_vector_to_f32_using_f16_scales`、`scaling_extf_vector_to_f32_using_f16_scales_fastmath` |
| 2 個從負向翻成正向（`f8E5M2FNUZ` scale 原本無法 legalize） | `invalid_scaling_truncf_to_f4E2M1FN` → `scaling_truncf_f16_to_f4E2M1FN_using_f8E5M2FNUZ_scales`、`invalid_scaling_extf_to_f32` → `scaling_extf_to_f32_using_f8E5M2FNUZ_scales` |

新增 4 個：`f8E5M3FNU` scale 的正向測試兩個（krzysz00 點名的型別，MLIR 有這個型別）、
同寬 bail 的負向測試兩個。

**那 6 個改掉的測試是樹上對舊讀法唯一的白紙黑字**，這也是為什麼要等 tgymnich 表態。

## 8. reviewer 大概會問什麼

**Q：為什麼乘法／除法在 result type（或 input type）做，不在比較寬的那個型別做？**
A：那是今天就有的結構，也是 op description 寫的契約（"Cast scale to result type" 然後 mulf）。
這個 patch 只換「scale 怎麼變成那個型別」，不動運算發生在哪。要改精度模型是另一題。

**Q：E8M0 scale 的行為變了嗎？**
A：沒有。實跑驗證過（第 4 節）。今天對 8 bit scale 就跳過截斷，走的已經是 `in * scale`。

**Q：這算 breaking change 嗎？**
A：對非 E8M0 scale 是。但今天那條路算的值是錯的（第 5 節），而且 8 bit 非 E8M0 的 scale
今天**根本不 legalize**——沒有使用者可以依賴一個不存在的展開。

**Q：`ArithToAMDGPU` 怎麼辦？**
A：不在這個 patch 裡。`ArithToAMDGPU.cpp:592` 把任何 scale 型別 ext／trunc 到 f32
交給 `amdgpu::PackedScaledTruncOp`；若硬體只讀 exponent bit，那條路在這個讀法下也丟尾數。
**這一點已經在 #215295 用問句丟給 krzysz00**（他的 §15.14 才是答案來源），沒有自己推論。

## 9. 四關（`Goal.md` §8.7）

| 關 | 判定 | 依據 |
|---|---|---|
| ① 真實 AI pipeline 走得到 | ✅ | MXFP 反量化的 generic 展開；`mlir/test/Integration/Dialect/XeGPU/WG/simple_mxfp_gemm_dequantizeB_F4.mlir` 是跑得起來的 MXFP GEMM |
| ② JD 關鍵字 | ✅ | quantization、mixed precision |
| ③ 不看筆記能答辯 | 見第 8 節 | — |
| ④ 可驗證證據 | ✅ | 見第 10 節的數值對照表（`mlir-opt` 實跑，可重現） |
| ⑤ 撞車 | 待查 | **送出前必查**，指令見 `Goal.md` §8.7 第 5 步 |

---

## 10. 第 4 關的證據：舊展開實際除以什麼

不是手算，是把舊展開那串 IR（`bitcast` → `shrui 23` → `trunci i8` → `bitcast` → `extf`）
直接餵給 `mlir-opt -canonicalize` 折出來的：

| scale | 舊展開實際用的除數 | 正確值 | 差多少 |
|---|---|---|---|
| `3.0` | **2.0** | 3.0 | 1.5× |
| `1.6` | **1.0** | 1.6 | 1.6× |
| `7.0` | **4.0** | 7.0 | 1.75× |

誤差上界趨近 2×（scale 落在 2 的冪正下方時最糟）。**這是值算錯，不是精度損失。**

重現指令（把 `3.0` 換成任何值）：

```mlir
func.func @old_divisor() -> f32 {
  %c = arith.constant 3.0 : f32
  %b = arith.bitcast %c : f32 to i32
  %c23 = arith.constant 23 : i32
  %s = arith.shrui %b, %c23 : i32
  %t = arith.trunci %s : i32 to i8
  %e = arith.bitcast %t : i8 to f8E8M0FNU
  %r = arith.extf %e : f8E8M0FNU to f32
  return %r : f32
}
```

**另外查清一件事**：`f16` scale 走完整 pipeline 時，舊路徑的答案取決於 `include-f8e8m0` 開不開。

| 跑法 | `truncf(1.6 : f16 to f8E8M0FNU)` 然後 `extf` 的結果 |
|---|---|
| 只 `-canonicalize` | **不折**——轉換不精確，`losesInfo` 為真，folder 拒絕 |
| `-arith-expand=include-f8e8m0 -canonicalize` | **1.0**（bit shift 丟掉尾數） |

> ⚠️ TODO.md 在 2026-08-10 記的「`1.6 : f16` → ExpandOps 給 2.0」**已經過期**。
> 今天實測是「不折」，另一條是 1.0。要引數字就重跑，不要抄舊紀錄。

## 11. 新展開實跑輸出（三個代表案例）

```mlir
// f16 scale：不再有截斷
func.func @f16_scale(%arg0: f4E2M1FN, %arg1: f16) -> f32 {
  %0 = arith.extf %arg1 : f16 to f32
  %1 = arith.extf %arg0 : f4E2M1FN to f32
  %2 = arith.mulf %1, %0 : f32
}

// f8E5M3FNU scale：今天根本不 legalize，現在展開
func.func @e5m3_scale(%arg0: f16, %arg1: f8E5M3FNU) -> f4E2M1FN {
  %0 = arith.extf %arg1 : f8E5M3FNU to f16
  %1 = arith.divf %arg0, %0 : f16
  %2 = arith.truncf %1 : f16 to f4E2M1FN
}

// E8M0 scale：與今天逐字相同
func.func @e8m0_unchanged(%arg0: f4E2M1FN, %arg1: f8E8M0FNU) -> f32 {
  %0 = arith.extf %arg1 : f8E8M0FNU to f32
  %1 = arith.extf %arg0 : f4E2M1FN to f32
  %2 = arith.mulf %1, %0 : f32
}
```

同寬 bail 也實測過：`scaling_extf %in : f4E2M1FN, f8E5M2FNUZ to f8E4M3FN`
回報 `failed to legalize`，不再建出違法的 op。
