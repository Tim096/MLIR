`convert-gpu-to-nvvm` handles five of the fifteen
`gpu.subgroup_mma_elementwise` ops and hits `llvm_unreachable` on the
other ten, so a `convert-vector-to-gpu` kernel with a `subf`, `negf` or
`truncf` epilogue on the WMMA path aborts in `-gpu-lower-to-nvvm-pipeline`:

```
UNREACHABLE executed at mlir/lib/Conversion/GPUToNVVM/WmmaOpsToNvvm.cpp:365!
```

`addf` on an f32 multiplicand fragment builds an `llvm.fadd` on the `i32`
registers that hold the tf32 bit patterns and fails verification instead.

This lowers `subf`, `negatef`, `addi`, `subi`, `muli`, `divs`, `divu` and
`negates` register by register like the existing ops, which the
"Manipulating fragment contents" rules of the PTX ISA allow, and rejects
the rest with a match failure: `extf` and `truncf`, because the PTX ISA
leaves conversions between f16 and f32 accumulator fragments undefined,
and any op on a fragment whose registers pack several elements (s8, u8,
tf32). The SPIR-V lowering handles all of these ops on cooperative
matrices, so `convert-vector-to-gpu` keeps emitting them.

Tests: lit tests for the new lowerings and for the rejected cases, and a
tensor core integration test that runs a matmul with a `subf` + `negf`
epilogue through `convert-vector-to-gpu` and the NVVM pipeline. It aborts
before this change and passes on an RTX 3070 (sm_86).
