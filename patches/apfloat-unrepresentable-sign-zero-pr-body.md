Fixes #215445, in the direction @tgymnich confirmed there.

`APFloat::convert` reports through `losesInfo` what rounding lost, but not what
the target format has no encoding for at all. Two properties of a format are not
rounding:

| property | formats today | what happens |
|---|---|---|
| `hasSignedRepr == false` | `f8E8M0FNU`, `f8E5M3FNU` | the sign bit is carried into a format with no room for it |
| `hasZero == false` | `f8E8M0FNU` | zero is replaced by the smallest normalized value, 2^-127 |

Both were reported as `opOK` with `losesInfo == false`. Callers gate on
`losesInfo` -- that is how `arith.truncf`'s folder decides whether a constant
fold is legal -- so they kept a value the format cannot hold.

### What went wrong in MLIR

```mlir
%c = arith.constant -2.000000e+00 : f32
%t = arith.truncf %c : f32 to f8E8M0FNU    // --canonicalize
```

folded, and printing the folded constant reached `convertFromString`, whose
leading-minus path is an `llvm_unreachable`:

```
This floating point format does not support signed values
UNREACHABLE executed at llvm/lib/Support/APFloat.cpp:3190!
```

The zero case did not crash, it disagreed: the folder produced 2^-127, while
`--arith-expand=include-f8e8m0` reads the same `0x00` encoding back as `0.0`.

### The two commits

1. **`APFloat`**: report both as `opInexact` with `losesInfo` set. The values
   that come out are unchanged, only the status is. The NaN path is restructured
   to fall through to the common tail instead of returning early, so the checks
   see every conversion. `arith.truncf` then leaves both constants alone.

2. **MLIR parser**: `arith.constant -2.000000e+00 : f8E8M0FNU` needs no pass at
   all -- parsing and printing the file was enough to assert, because the
   attribute is built with `FloatAttr::get` and never consults `losesInfo`. Both
   literal paths now emit a diagnostic:

   ```
   error: negative floating point literal for a type with no signed representation
   ```

### One test changed on purpose

`APFloatTest.ConvertDoubleToE8M0FNU` pinned the old status for the zero case:

```cpp
  // For E8M0, zero encoding is represented as the smallest normalized value.
  EXPECT_FALSE(losesInfo);
  EXPECT_EQ(status, APFloat::opOK);
```

The substituted value is kept -- only the two lines above change, since 2^-127
is not the value that went in. Please say if that substitution is meant to be
reported as exact; everything else here follows from it.

### Not covered

Writing `0.0 : f8E8M0FNU` as a literal still yields 2^-127 silently. That is a
value question rather than a crash, and rejecting the literal is a bigger
decision than this patch should take; the folder no longer produces it.

### Verification

| check | result |
|---|---|
| `ADTTests` | 2188 passed, 0 failed |
| `check-mlir` | 3848 passed, 0 failed (611 unsupported, 1 expectedly failed) |
| `git clang-format` | clean |

Both reproducers from the issue were rerun: the fold is gone (`-2.0` and `0.0`
into `f8E8M0FNU`, and `-2.0` into `f8E5M3FNU` all stay as `arith.truncf`), and
the literal now produces a diagnostic instead of an abort.
