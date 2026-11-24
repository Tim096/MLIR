# 留言：#243614／#243705 與 #215696 重疊（2026-11-24 已送）

- #243614：issuecomment-7131931536
- #243705：issuecomment-7131931933

查證：
- #243705（woruyu，11-18）改 `IndexToLLVM.cpp` 的 `ConvertIndexCeilDivS` 與 `IndexOps.cpp` 的 folder；#215696 也改這兩處。
- #215696：2026-08-11 開，kuhar 08-14 approve，13 個檔 +234/−196。
- `(INT_MAX, -1)`：main `376f04dd8bdb` 上 `mlir-runner` SIGFPE（rc=136）；#215696 的公式手寫成 LLVM dialect 跑出 `-9223372036854775807`。

---

## 貼到 issue #243614

#215696 fixes this (approved, not landed yet). The same lowering also traps on `ceildivs(INT_MAX, -1)`: the branch that is not selected computes `INT_MIN sdiv -1`. That goes away with the same change.

## 貼到 PR #243705

Heads-up: #215696 changes the same two places (the `ceildivs` LLVM lowering and the folder) for the same `INT_MIN` case. It also covers the SPIR-V lowering, the affine expansion and range inference, and has been approved since August. The two will conflict, cc @kuhar on how to sequence them.
