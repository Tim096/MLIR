`f8E8M0FNU` declares `hasSignedRepr = false` and `hasZero = false`, but
`APFloat::convert` into it reports `opOK` with `losesInfo == false` for negative
values and for zero. A negative value keeps its sign and produces an `APFloat`
that cannot be printed; zero silently becomes 2^-127. On `11799583db91`, with
assertions enabled.

```cpp
constexpr fltSemantics APFloatBase::semFloat8E8M0FNU = {
    127, -127, 1, 8,
    fltNonfiniteBehavior::NanOnly,
    fltNanEncoding::AllOnes,
    false,   // hasZero
    false,   // hasSignedRepr
    false, false};
```

### Reproducer 1: a fold produces the negative value

```mlir
func.func @f() -> f8E8M0FNU {
  %c = arith.constant -2.000000e+00 : f32
  %t = arith.truncf %c : f32 to f8E8M0FNU
  return %t : f8E8M0FNU
}
```

```
$ mlir-opt repro.mlir --canonicalize
This floating point format does not support signed values
UNREACHABLE executed at llvm/lib/Support/APFloat.cpp:3178!
```

Without a pass the same input round-trips fine, so the negative constant is
created by the fold.

### Reproducer 2: no pass at all

```mlir
func.func @f() -> f8E8M0FNU {
  %c = arith.constant -2.000000e+00 : f8E8M0FNU
  return %c : f8E8M0FNU
}
```

```
$ mlir-opt repro2.mlir
This floating point format does not support signed values
UNREACHABLE executed at llvm/lib/Support/APFloat.cpp:3178!
```

The attribute parses and the crash happens on the way out, so this is not
specific to `arith`: any path that builds an `f8E8M0FNU` `FloatAttr` from a
negative value produces IR that cannot be printed.

### Where it goes wrong

`IEEEFloat::convert` switches semantics without consulting either flag:

```cpp
  // Now that we have the right storage, switch the semantics.
  semantics = &toSemantics;
```

`sign` is left as it was, and the zero category is carried over into a semantics
that has no encoding for it. Callers that guard on loss therefore see nothing to
reject. `mlir::arith`'s `convertFloatValue` is one of them:

```cpp
  bool losesInfo = false;
  auto status = sourceValue.convert(targetSemantics, roundingMode, &losesInfo);
  if (losesInfo || status != APFloat::opOK)
    return failure();
```

The `llvm_unreachable` that eventually fires is the one guarding string parsing,
reached because `AsmPrinter` prints the attribute as `-2.000000e+00` and then
re-parses it:

```cpp
  sign = *p == '-' ? 1 : 0;
  if (sign && !semantics->hasSignedRepr)
    llvm_unreachable("This floating point format does not support signed values");
```

### Silent wrong values where nothing has to be printed

`--arith-expand=include-f8e8m0` lowers the same conversion by extracting the
exponent field, which drops the sign. Constant folding and the expansion
disagree:

| `extf(truncf(x : f32 to f8E8M0FNU))` | folded | `include-f8e8m0` |
|---|---|---|
| `-1.0` | `-1.0` | NaN |
| `-4.0` | `-4.0` | `4.0` |
| `-3.0` | not folded (inexact) | `2.0` |
| `0.0` | `5.87747175E-39` (2^-127) | `0.0` |
| `-0.0` | `5.87747175E-39` (2^-127) | `0.0` |

The zero rows do not crash, and they carry a second disagreement on top: the
expansion reads the `f8E8M0FNU` encoding `0x00` back as `0.0`, while `APFloat`
reads it as 2^-127. Either way `convert` accepted a value the target has no
encoding for without reporting it.

### Question

Should `APFloat::convert` report the sign, and the zero, as lost when the target
has `hasSignedRepr == false` or `hasZero == false`?

Reporting loss fixes all of the above at once, since every caller shown here
already checks `losesInfo`, and it stops `arith` from folding a conversion whose
result it cannot represent. The alternative -- clearing the sign inside
`convert` -- would make the folder agree with the expansion, but at the cost of a
silent value change in a function whose contract is to report exactly this.

Happy to send the patch either way, with MLIR tests for both reproducers.

Context: found while investigating #215295, but independent of the semantics
question there.

cc @tgymnich @krzysz00 @umangyadav @kuhar
