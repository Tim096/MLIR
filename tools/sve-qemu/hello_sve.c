// Smoke test: does the emulator expose SVE, and at which vector length?
#include <arm_sve.h>
#include <stdio.h>
#include <sys/auxv.h>

int main(void) {
  int hasSve = (int)((getauxval(AT_HWCAP) >> 22) & 1); // HWCAP_SVE
  int bits = (int)svcntb() * 8;
  printf("HWCAP_SVE=%d VL=%d bits vscale=%d\n", hasSve, bits, bits / 128);
  return hasSve ? 0 : 1;
}
