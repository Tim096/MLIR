The gfx950 scaled conversion instructions (`v_cvt_scalef32_*`) take
their scale as an f32 and use only its exponent (bits 31:23). That
implements `arith.scaling_extf` and `arith.scaling_truncf` only when the
scale is `f8E8M0FNU`, whose value is its exponent. The lowering accepted
any float scale and extended or truncated it to f32:

```mlir
%0 = arith.scaling_extf %in, %scale : vector<4xf4E2M1FN>, vector<4xf32> to vector<4xf32>
// -convert-arith-to-amdgpu=chipset=gfx950 today: the f32 scale goes straight
// into amdgpu.scaled_ext_packed, which reads its exponent only
```

For a scale that is not `f8E8M0FNU` the exponent-only read is one
particular rounding of the scale (toward zero), and what such a scale
means is still open in #215295. The folder (#215123) already only
handles `f8E8M0FNU` scales for that reason. This makes the conversion
take the same line: it matches only `f8E8M0FNU` scales and leaves the
others to `arith-expand`, as @krzysz00 suggested on the issue.

Also from that discussion: when the scale is an f32 truncated to
`f8E8M0FNU` with `toward_zero`, the truncation is exactly what the
instruction does itself, so the f32 is fed to it directly and the
truncf/extf round trip goes away.

Tests: the four `long_*_broadcast` tests used an f32 scale and are the
only coverage of the multi-slice loop, so they keep their shape and take
an `f8E8M0FNU` scale. New tests cover f32, f16 and bf16 scales being left
alone, the `toward_zero` fold, and a default-rounding truncation not
being folded.

No in-tree pipeline runs this pass. A pipeline that feeds it scales that
are not `f8E8M0FNU` needs `arith-expand` after it, as the XeVM pipeline
already does.

This is the AMDGPU side of #217892: once the expansion uses the scale's
value, the exponent-only instruction path is the one that has to be
restricted to the scale type it is exact for.
