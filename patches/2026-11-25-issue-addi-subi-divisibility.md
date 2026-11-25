# Issue 草稿：`addi`／`subi` 的整除性推導遇溢位會錯（不送）

**本人 2026-11-25 決定：不自己開 issue，改成在 #237342 的 review 裡建議作者一起修。** 這份留著當查證紀錄。

查證（本機 `376f04dd8bdb`，分支 `review/batch-1125`，2026-11-25）：
- `mlir-opt --test-int-divisibility-analysis` 對下面兩個函式都回報 `udiv = 3`（addi 是 `udiv = 3, sdiv = 1`，subi 是 `udiv = 3, sdiv = 3`）。
- `mlir-runner` 實跑（`p = false`）印出 2 與 1。
- 重現檔用 `select` 不用 `muli`，所以不受 #237342 有沒有進影響；跑的 binary 沒有套 #237342。
- i8 窮舉（`scratchpad/divcheck.py`）：gcd 規則在無 flag／只有 nuw／只有 nsw 都有反例，`nuw, nsw` 沒有。
- 搜過 issue（divisibility＋addi／subi），沒看到有人報。#233210 只講 `muli`，#237342 只修 `muli`。
- 這個分析在樹裡目前只有測試 pass 在用。

範本取樣：#233210（同一個分析、同一個作者群的寫法：Summary／Reproducer／Actual／Expected）。

---

標題：`[mlir][arith] addi/subi divisibility inference ignores wraparound`

`arith.addi` and `arith.subi` infer the gcd of the operand divisors. That holds for the mathematical result, but not after the result wraps. This is the same problem as #233210, which is about `muli`.

```mlir
func.func @addi_remui(%p: i1) -> i8 {
  %c3 = arith.constant 3 : i8
  %c255 = arith.constant 255 : i8
  %a = arith.select %p, %c3, %c255 : i8
  %y = arith.addi %a, %c3 : i8
  "test.int_divisibility"(%y) : (i8) -> ()
  %r = arith.remui %y, %c3 : i8
  return %r : i8
}

func.func @subi_remui(%p: i1) -> i8 {
  %c0 = arith.constant 0 : i8
  %c3 = arith.constant 3 : i8
  %a = arith.select %p, %c3, %c0 : i8
  %y = arith.subi %a, %c3 : i8
  "test.int_divisibility"(%y) : (i8) -> ()
  %r = arith.remui %y, %c3 : i8
  return %r : i8
}
```

`mlir-opt --allow-unregistered-dialect --test-int-divisibility-analysis` reports `udiv = 3` for both `%y`.

Calling `@addi_remui(false)` returns 2: `255 + 3` wraps to 2. Calling `@subi_remui(false)` returns 1: `0 - 3` wraps to 253.

As for `muli`, only the power-of-two part of the gcd survives a wrap. The full unsigned divisor holds with `nuw` and the full signed divisor with `nsw`.
