# Issue 草稿：PPC double-double 在 rmTowardZero 下 overflow 的兩個既有 bug

**未開**。與 #220020 無關（兩者在不含 #220020 的 main `723587b250b0` 上都重現），在 #220020 review 時順帶發現。
探針原檔：`scratchpad/apf/probe3.cpp`（連 `build/lib/libLLVMSupport.so`，要 `-fno-rtti`）。

---

**Title**: `[APFloat] PPCDoubleDouble overflow under rmTowardZero: convertFromString asserts, add/multiply return +Inf`

**Body**:

With `PPCDoubleDouble` and `rmTowardZero`, two overflow paths misbehave (both reproduced on main, independent of #220020):

1. `convertFromString("1e400", rmTowardZero)` hits an assertion:

   ```
   APFloat.cpp:3489: llvm::APInt llvm::detail::IEEEFloat::convertPPCDoubleDoubleLegacyAPFloatToAPInt() const: Assertion `fs == opOK || fs == opInexact' failed.
   ```

   The string is converted in the legacy 106-bit semantics, which rounds toward zero to its largest value. `convertPPCDoubleDoubleLegacyAPFloatToAPInt` then converts that to `IEEEdouble` with `rmNearestTiesToEven`, which rounds up past `DBL_MAX` and overflows.

2. `getLargest() + getLargest()` and `getLargest() * getLargest()` under `rmTowardZero` return `+Inf` with only `opInexact` set. Rounding toward zero should never produce an infinity from finite operands; `IEEEdouble` gives the largest finite value here.

Reproducer:

```cpp
#include "llvm/ADT/APFloat.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/Support/Error.h"
#include <cstdio>
using namespace llvm;

static void show(const char *Op, APFloat::opStatus St, const APFloat &V) {
  SmallString<48> S;
  V.toString(S);
  printf("%-16s %s overflow=%d inexact=%d\n", Op, S.c_str(),
         !!(St & APFloat::opOverflow), !!(St & APFloat::opInexact));
}

int main() {
  setvbuf(stdout, nullptr, _IONBF, 0); // keep the output before the assert
  const fltSemantics &Sem = APFloat::PPCDoubleDouble();
  auto RM = APFloat::rmTowardZero;

  APFloat A = APFloat::getLargest(Sem);
  show("max + max", A.add(APFloat::getLargest(Sem), RM), A);

  APFloat M = APFloat::getLargest(Sem);
  show("max * max", M.multiply(APFloat::getLargest(Sem), RM), M);

  APFloat F(Sem);
  auto St = F.convertFromString("1e400", RM); // asserts
  if (!St)
    consumeError(St.takeError());
  else
    show("fromString 1e400", *St, F);
}
```

Current output (assertions enabled):

```
max + max        +Inf overflow=0 inexact=1
max * max        +Inf overflow=0 inexact=1
<assertion above>
```

Expected: the largest finite `PPCDoubleDouble` value in all three cases, and no assertion. (Whether `opOverflow` is also set depends on #220020, which makes `IEEEFloat` signal it on this path.)

For comparison, `convertFromAPInt(2^1100, false, rmTowardZero)` on `PPCDoubleDouble` does return the largest finite value (`1.79769313486231580793728971405301E+308`), through `DoubleAPFloat::handleOverflow`.
