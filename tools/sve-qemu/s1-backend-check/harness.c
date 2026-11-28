// Calls the functions in subbyte.ll and compares against a scalar reference.
// Build with -DHAVE_<NAME> for each function that the backend could compile.
#include <arm_sve.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void trunc_direct(uint8_t *, uint8_t *);
void trunc_rewritten(uint8_t *, uint8_t *);
void sext_direct(uint8_t *, uint8_t *);
void sext_rewritten(uint8_t *, uint8_t *);

static int check(const char *name, const uint8_t *got, const uint8_t *want,
                 int n) {
  int bad = memcmp(got, want, n) != 0;
  printf(" %s=%s", name, bad ? "MISMATCH" : "ok");
  return bad;
}

int main(void) {
  int nb = (int)svcntb(); // bytes in one SVE register
  uint8_t in[256], out[256], want[256];
  int bad = 0;
  printf("VL=%d", nb * 8);
  for (int i = 0; i < nb; ++i)
    in[i] = (uint8_t)(i * 37 + 0xA5);

  // trunc: nb x i8 -> nb x i4, stored as nb/2 bytes (little-endian nibbles).
  for (int k = 0; k < nb / 2; ++k)
    want[k] = (uint8_t)((in[2 * k] & 0xF) | ((in[2 * k + 1] & 0xF) << 4));
#ifdef HAVE_trunc_direct
  memset(out, 0xEE, sizeof out);
  trunc_direct(in, out);
  bad |= check("trunc_direct", out, want, nb / 2);
#endif
#ifdef HAVE_trunc_rewritten
  memset(out, 0xEE, sizeof out);
  trunc_rewritten(in, out);
  bad |= check("trunc_rewritten", out, want, nb / 2);
#endif

  // sext: nb/2 bytes holding nb x i4 -> nb x i8.
  for (int k = 0; k < nb / 2; ++k) {
    want[2 * k] = (uint8_t)((int8_t)(in[k] << 4) >> 4);
    want[2 * k + 1] = (uint8_t)((int8_t)in[k] >> 4);
  }
#ifdef HAVE_sext_direct
  memset(out, 0xEE, sizeof out);
  sext_direct(in, out);
  bad |= check("sext_direct", out, want, nb);
#endif
#ifdef HAVE_sext_rewritten
  memset(out, 0xEE, sizeof out);
  sext_rewritten(in, out);
  bad |= check("sext_rewritten", out, want, nb);
#endif
  printf("\n");
  return bad;
}
