// Overflow status under rmTowardZero for IEEEdouble and PPCDoubleDouble.
#include "llvm/ADT/APFloat.h"
#include "llvm/ADT/APInt.h"
#include <cstdio>
using namespace llvm;

static void show(const char *what, APFloat::opStatus s, const APFloat &v) {
  std::printf("%-40s ovf=%d inexact=%d largest=%d inf=%d\n", what,
              !!(s & APFloat::opOverflow), !!(s & APFloat::opInexact),
              v.isLargest(), v.isInfinity());
}

int main() {
  for (const fltSemantics *Sem :
       {&APFloat::IEEEdouble(), &APFloat::PPCDoubleDouble()}) {
    const char *n = Sem == &APFloat::IEEEdouble() ? "double" : "ppc";
    char buf[64];
    APFloat a(*Sem);
    APInt big = APInt::getOneBitSet(1200, 1100);
    auto s = a.convertFromAPInt(big, false, APFloat::rmTowardZero);
    std::snprintf(buf, sizeof buf, "%s convertFromAPInt(2^1100)", n);
    show(buf, s, a);
    APFloat m = APFloat::getLargest(*Sem);
    APFloat x = m;
    s = x.add(m, APFloat::rmTowardZero);
    std::snprintf(buf, sizeof buf, "%s max+max", n);
    show(buf, s, x);
    x = m;
    s = x.multiply(m, APFloat::rmTowardZero);
    std::snprintf(buf, sizeof buf, "%s max*max", n);
    show(buf, s, x);
  }
}
