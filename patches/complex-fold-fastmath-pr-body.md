`complex.add(complex.sub(a, b), b)`, `complex.add(b, complex.sub(a, b))`
and `complex.sub(complex.add(a, b), b)` fold to `a` unconditionally, and
so does `complex.exp(complex.log(a))`:

```mlir
func.func @add_sub(%a: complex<f32>, %b: complex<f32>) -> complex<f32> {
  %sub = complex.sub %a, %b : complex<f32>
  %add = complex.add %sub, %b : complex<f32>
  return %add : complex<f32>
}
// -canonicalize today
func.func @add_sub(%a: complex<f32>, %b: complex<f32>) -> complex<f32> {
  return %a : complex<f32>
}
```

Neither identity holds in floating point. The intermediate result is
rounded, so with `a = (1.0, 0.0)` and `b = (1.0e30, 0.0)` the original
returns `(0.0, 0.0)`, and `(-0.0 - b) + b` is `+0.0`. `exp(log(a))` is an
approximation of `a` (and `log` of a zero is `-inf` before `exp` takes it
back). LLVM only simplifies `(X - Y) + Y` and `(X + Y) - Y` with
`reassoc` and `nsz` on the outer operation
(`InstructionSimplify.cpp`, `simplifyFAddInst`/`simplifyFSubInst`), and
only rewrites `log(exp(x))` when both calls are fast
(`SimplifyLibCalls.cpp`, `optimizeLog`).

This gates the add/sub folds on `reassoc` and `nsz` of the folded op and
the exp/log fold on `afn` of both ops, mirroring those rules, and adds a
test for each fold without the flags. The existing tests gain the flags.
Same direction as #212751 and #212781, which fixed the neighbouring
`add(a, 0)` and `log(exp(a))` folds.
