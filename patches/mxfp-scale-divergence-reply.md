Thanks both. That answers the hardware question, and @tgymnich is right that my
example did not show what I claimed it showed. Everything below is on
`11799583db91`.

### Correcting my example

The `1.6 -> 2.0` step in the issue is not a fold. The rounding happens when the
attribute is created:

```mlir
%c = arith.constant 1.600000e+00 : f8E8M0FNU   // already 2.0 at this point
%e = arith.extf %c : f8E8M0FNU to f32          // exact, folds to 2.0
```

The `truncf` folder does refuse the inexact case, as you expected.
`convertFloatValue` in `ArithOps.cpp` fails on `losesInfo`:

```cpp
bool losesInfo = false;
auto status = sourceValue.convert(targetSemantics, roundingMode, &losesInfo);
if (losesInfo || status != APFloat::opOK)
  return failure();
```

so `arith.truncf %cst : f16 to f8E8M0FNU` with `%cst = 1.6` survives
`--canonicalize` unfolded, while `2.0` folds. And `--arith-expand
--convert-arith-to-llvm` leaves the op in place, confirming there is no
conversion for it.

### The divergence is narrower than I filed, and it is inside arith

With the exponent-only reading confirmed, the two lowerings agree. What does not
agree is arith's own two implementations of the same op at its *default*
rounding mode:

| `1.6 : f16` to `f8E8M0FNU` | result |
|---|---|
| `--arith-expand=include-f8e8m0` (`F8E8M0TruncFOpConverter`) | `1.0` — shift right by 23 and keep the exponent, i.e. round toward zero |
| `APFloat::convert` (folder, attribute) | `2.0` — round to nearest even |

`kDefaultRoundingMode` in `ArithOps.cpp` is `NearestTiesToEven`, and the
expansion bails out whenever a rounding mode is spelled out:

```cpp
if (op.getRoundingmodeAttr())
  return rewriter.notifyMatchFailure(op, "only applicable to default rounding mode.");
```

So the expansion treats the absent attribute as exponent extraction while the
folder treats the same absent attribute as round-to-nearest-even. One side
effect is that `arith.truncf %x to_nearest_even : f32 to f8E8M0FNU` fails to
legalize under `--arith-expand=include-f8e8m0`, so the only rounding mode that
can be written explicitly is the one the pass refuses.

The only statement of intent I can find in tree is the comment above the
pattern, which agrees with @tgymnich:

```
TruncF to F8E8M0 is expected to extract exponent bits out of F32 type
```

### The same place mishandles the sign

`f8E8M0FNU` is unsigned, but `APFloat::convert` into it keeps the sign and
reports no loss, so the folder produces a negative `f8E8M0FNU` constant. That
constant cannot be printed -- `mlir-opt --canonicalize` aborts on this input:

```mlir
func.func @f() -> f8E8M0FNU {
  %c = arith.constant -2.000000e+00 : f32
  %t = arith.truncf %c : f32 to f8E8M0FNU
  return %t : f8E8M0FNU
}
```

```
This floating point format does not support signed values
UNREACHABLE executed at llvm/lib/Support/APFloat.cpp:3178!
```

When the result stays in f32 it does not crash, it just disagrees with the
expansion:

| `extf(truncf(x : f32 to f8E8M0FNU))` | folder | `include-f8e8m0` |
|---|---|---|
| `-1.0` | `-1.0` | NaN |
| `-4.0` | `-4.0` | `4.0` |
| `-3.0` | not folded (inexact) | `2.0` |
| `-0.0` | `5.87747175E-39` (2^-127) | `0.0` |

Filed as #215445, since it is a crash on valid IR and does not depend on which
reading wins here. `APFloat::convert` into `f8E8M0FNU` reports no loss for
negative values or for zero, so the folder accepts conversions whose result the
type cannot represent.

### Revised question

Is `arith.truncf` to `f8E8M0FNU` defined as round-to-nearest-even like every
other `truncf`, in which case the expansion should round; or as exponent
extraction, in which case the op documentation should say so and the folder
should stop routing it through `APFloat::convert`?

@tgymnich your comment points at the second, and I am happy to write the
documentation change plus the folder fix.

@krzysz00 does the second reading change your view on rejecting non-E8M0 scales
in `ArithToAMDGPU`? If truncation to E8M0 is defined as taking the exponent,
then handing an f16/f32 scale straight to the instruction already matches the
documented behaviour and there is nothing to reject. The part I cannot place is
your E5M3 point -- under an exponent-only definition an E5M3 scale loses its
mantissa on both paths, so I may be misreading what you meant by having it work
correctly.
