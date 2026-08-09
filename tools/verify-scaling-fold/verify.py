#!/usr/bin/env python3
"""Exhaustive check of the arith.scaling_extf / arith.scaling_truncf folders.

For every point of the input space it checks three things:

  1. Does the folder agree with `-arith-expand -canonicalize`?  That pipeline
     is upstream's own expansion of these ops, folded by the pre-existing
     extf/truncf/mulf/divf folders, so it encodes upstream's conventions.

  2. Does the folded value match the OCP MXFP semantics, computed in Python
     without LLVM in the loop at all?

  3. Was the *decision* to fold or not correct?  A fold is expected exactly
     when every step of the documented expansion is lossless -- that is
     upstream's convention for cast folders (see @truncFPConstantRounding in
     canonicalize.mlir).  This catches missed folds, not just wrong ones.

(1) and (2) are deliberately complementary: (1) would happily agree with a bug
that lives in the expansion itself, and (2) knows the mathematical answer but
not upstream's conventions about when to give up.

The input space is small enough that "exhaustive" is literal:
  scaling_extf  : f4E2M1FN (16) x f8E8M0FNU (256), to f16 and to f32
  scaling_truncf: f16 (65536) x f8E8M0FNU (256) -> f4E2M1FN

Usage: verify.py --mlir-opt PATH [--quick]
"""

import argparse
import math
import os
import struct
import subprocess
import sys
import tempfile
import time

# ---------------------------------------------------------------------------
# Float format decoding: bit pattern -> the exact real number it stands for.
# None means NaN. These follow the OCP spec, not LLVM's tables, on purpose.
# ---------------------------------------------------------------------------


def decode_f4e2m1fn(bits):
    """OCP FP4 E2M1: 1 sign, 2 exponent, 1 mantissa, finite-only (no Inf/NaN)."""
    sign = -1.0 if (bits >> 3) & 1 else 1.0
    exp, man = (bits >> 1) & 0b11, bits & 1
    value = man * 0.5 if exp == 0 else (1.0 + 0.5 * man) * (2.0 ** (exp - 1))
    return sign * value


def decode_f16(bits):
    """IEEE binary16."""
    value = struct.unpack("<e", struct.pack("<H", bits))[0]
    return None if math.isnan(value) else value


def decode_f8e8m0fnu(bits):
    """OCP E8M0 scale: 8 exponent bits only, no sign, no mantissa. 0xFF = NaN."""
    return None if bits == 0xFF else 2.0 ** (bits - 127)


F4E2M1FN_VALUES = [decode_f4e2m1fn(b) for b in range(16)]
F4E2M1FN_MAX = max(abs(v) for v in F4E2M1FN_VALUES)

# f16 can hold 2^e exactly for e in [-24, 15]: 2^15 is the largest power of two
# below its overflow threshold, 2^-24 is its smallest subnormal.
F16_EXACT_POW2 = range(-24, 16)


def round_to_f4e2m1fn(value):
    """Round to nearest f4E2M1FN, ties to even; None if not representable."""
    if value is None or math.isnan(value) or math.isinf(value):
        return None
    if abs(value) > F4E2M1FN_MAX:
        return None  # overflow: finite-only type, nothing to round to
    best_bits, best_dist = None, None
    for bits, cand in enumerate(F4E2M1FN_VALUES):
        dist = abs(cand - value)
        if best_dist is None or dist < best_dist:
            best_bits, best_dist = bits, dist
        elif dist == best_dist and (bits & 1) == 0 and (best_bits & 1) == 1:
            best_bits = bits  # tie -> even significand
    return F4E2M1FN_VALUES[best_bits]


# ---------------------------------------------------------------------------
# Driving mlir-opt
# ---------------------------------------------------------------------------


def run_and_parse(mlir_opt, source, passes):
    """Returns {func name: folded constant text or None}.

    A function counts as folded when its whole body is one arith.constant plus
    the return. Parsed line by line: these outputs run to tens of megabytes and
    a regex over the whole thing is the slowest part of the sweep.
    """
    fd, path = tempfile.mkstemp(suffix=".mlir")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(source)
        proc = subprocess.run(
            [mlir_opt, path] + passes, capture_output=True, text=True, check=False
        )
    finally:
        os.unlink(path)
    if proc.returncode != 0:
        sys.exit(f"mlir-opt failed ({' '.join(passes)}):\n{proc.stderr[:3000]}")

    results = {}
    name, body = None, []
    for line in proc.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("func.func @"):
            name = stripped[len("func.func @") :].split("(")[0]
            body = []
        elif name is not None and stripped == "}":
            folded = None
            if (
                len(body) == 2
                and "arith.constant" in body[0]
                and body[1].startswith("return")
            ):
                folded = body[0].split("arith.constant ", 1)[1].rsplit(" : ", 1)[0]
            results[name] = folded
            name = None
        elif name is not None and stripped:
            body.append(stripped)
    return results


def parse_float(text):
    """MLIR prints either a decimal literal or a raw `0x` bit pattern."""
    if text.startswith("0x"):
        return ("bits", int(text, 16))
    return float(text)


# ---------------------------------------------------------------------------
# Sweeps
# ---------------------------------------------------------------------------


class Tally:
    def __init__(self):
        self.cases = 0
        self.folded = 0
        self.nan_scale_diff = 0
        self.bad_oracle = []
        self.bad_python = []
        self.bad_decision = []

    def note(self, kind, name, detail):
        getattr(self, kind).append((name, detail))


def sweep_extf(mlir_opt, result_ty, tally):
    """f4E2M1FN x f8E8M0FNU -> result_ty, all 16 x 256 combinations."""
    # f16 holds 2^e exactly for e in [-24, 15]; f32 for e in [-149, 127],
    # i.e. every value f8E8M0FNU can encode.
    exact_pow2 = F16_EXACT_POW2 if result_ty == "f16" else range(-149, 128)
    to_np = {"f16": "float16", "f32": "float32"}[result_ty]
    import numpy as np

    np_ty = getattr(np, to_np)

    src = []
    for i in range(16):
        for s in range(256):
            src.append(
                f"func.func @e_{i}_{s}() -> {result_ty} {{\n"
                f"  %in = arith.constant 0x{i:X} : f4E2M1FN\n"
                f"  %sc = arith.constant 0x{s:02X} : f8E8M0FNU\n"
                f"  %r = arith.scaling_extf %in, %sc : f4E2M1FN, f8E8M0FNU to {result_ty}\n"
                f"  return %r : {result_ty}\n}}\n"
            )
    source = "\n".join(src)
    mine = run_and_parse(mlir_opt, source, ["-canonicalize"])
    expand = run_and_parse(mlir_opt, source, ["-arith-expand", "-canonicalize"])

    for i in range(16):
        for s in range(256):
            name = f"e_{i}_{s}"
            got, exp = mine[name], expand[name]
            tally.cases += 1
            if got is not None:
                tally.folded += 1
            in_val, scale_val = decode_f4e2m1fn(i), decode_f8e8m0fnu(s)

            if got != exp:
                if scale_val is None:
                    tally.nan_scale_diff += 1
                else:
                    tally.note("bad_oracle", name, f"folder {got}, expansion {exp}")

            # Should it have folded? Both widenings must be lossless. Widening
            # f4E2M1FN is always exact; widening the scale needs 2^e in range.
            should_fold = scale_val is None or (s - 127) in exact_pow2
            if (got is not None) != should_fold:
                tally.note(
                    "bad_decision",
                    name,
                    f"folded={got is not None}, expected={should_fold}",
                )
                continue
            if got is None:
                continue

            value = parse_float(got)
            if scale_val is None:
                # NaN scale: the op documents propagating a NaN.
                is_nan = (
                    value[1] in (0x7FC00000, 0x7E00)
                    if isinstance(value, tuple)
                    else math.isnan(value)
                )
                if not is_nan:
                    tally.note("bad_python", name, f"NaN scale gave {got}")
                continue
            if isinstance(value, tuple):
                bits = value[1]
                raw = struct.pack("<I" if result_ty == "f32" else "<H", bits)
                value = struct.unpack("<f" if result_ty == "f32" else "<e", raw)[0]
            with np.errstate(over="ignore"):
                want = np_ty(in_val * scale_val)  # exact in f64, rounded once here
            if not (np_ty(value) == want or (np.isnan(value) and np.isnan(want))):
                tally.note("bad_python", name, f"got {value}, want {want}")


def sweep_truncf(mlir_opt, tally, scales):
    """f16 x f8E8M0FNU -> f4E2M1FN, chunked one file per scale value."""
    import numpy as np

    for s in scales:
        scale_val = decode_f8e8m0fnu(s)
        src = []
        for i in range(65536):
            src.append(
                f"func.func @t_{i}() -> f4E2M1FN {{\n"
                f"  %in = arith.constant 0x{i:04X} : f16\n"
                f"  %sc = arith.constant 0x{s:02X} : f8E8M0FNU\n"
                f"  %r = arith.scaling_truncf %in, %sc : f16, f8E8M0FNU to f4E2M1FN\n"
                f"  return %r : f4E2M1FN\n}}\n"
            )
        source = "\n".join(src)
        mine = run_and_parse(mlir_opt, source, ["-canonicalize"])
        expand = run_and_parse(mlir_opt, source, ["-arith-expand", "-canonicalize"])

        for i in range(65536):
            name = f"t_{i}"
            got, exp = mine[name], expand[name]
            tally.cases += 1
            if got is not None:
                tally.folded += 1
            if got != exp:
                if scale_val is None:
                    tally.nan_scale_diff += 1
                else:
                    tally.note(
                        "bad_oracle", f"{name}/s{s:02X}", f"folder {got}, expansion {exp}"
                    )

            in_val = decode_f16(i)
            # f4E2M1FN is finite-only, so a NaN or Inf result can never fold.
            if scale_val is None or in_val is None or math.isinf(in_val):
                if got is not None:
                    tally.note("bad_decision", f"{name}/s{s:02X}", f"folded {got}")
                continue

            if (s - 127) not in F16_EXACT_POW2:
                # Widening the scale into f16 is lossy, so nothing folds.
                if got is not None:
                    tally.note("bad_decision", f"{name}/s{s:02X}", f"folded {got}")
                continue

            # Dividing by a power of two is exact in f64, so this rounds once,
            # into f16 -- exactly what arith.divf on f16 operands does.
            with np.errstate(over="ignore", under="ignore"):
                quotient = float(np.float16(in_val / scale_val))
            rounded = round_to_f4e2m1fn(quotient)
            should_fold = rounded is not None and rounded == quotient
            if (got is not None) != should_fold:
                tally.note(
                    "bad_decision",
                    f"{name}/s{s:02X}",
                    f"folded={got is not None}, expected={should_fold} "
                    f"(in={in_val}, scale=2^{s - 127}, q={quotient})",
                )
                continue
            if got is not None and float(got) != quotient:
                tally.note(
                    "bad_python", f"{name}/s{s:02X}", f"got {got}, want {quotient}"
                )
        print(f"  scale 0x{s:02X} (2^{s - 127}) done: {tally.cases} cases so far", flush=True)


def report(title, tally):
    print(f"\n=== {title} ===")
    print(f"  cases                        : {tally.cases}")
    print(f"  folded by -canonicalize      : {tally.folded}")
    print(f"  left alone                   : {tally.cases - tally.folded}")
    print(f"  wrong value vs expand oracle : {len(tally.bad_oracle)}")
    print(f"  wrong value vs python oracle : {len(tally.bad_python)}")
    print(f"  wrong fold/no-fold decision  : {len(tally.bad_decision)}")
    print(f"  NaN-scale diffs vs expansion : {tally.nan_scale_diff}  (expected, see #214919)")
    for kind in ("bad_oracle", "bad_python", "bad_decision"):
        items = getattr(tally, kind)
        for name, detail in items[:6]:
            print(f"    [{kind}] {name}: {detail}")
        if len(items) > 6:
            print(f"    [{kind}] ... and {len(items) - 6} more")
    return len(tally.bad_oracle) + len(tally.bad_python) + len(tally.bad_decision)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlir-opt", required=True)
    ap.add_argument(
        "--quick",
        action="store_true",
        help="sweep 16 representative scales instead of all 256 for scaling_truncf",
    )
    args = ap.parse_args()

    failures = 0
    for result_ty in ("f16", "f32"):
        tally = Tally()
        start = time.time()
        sweep_extf(args.mlir_opt, result_ty, tally)
        failures += report(
            f"scaling_extf: f4E2M1FN x f8E8M0FNU -> {result_ty}  "
            f"[{time.time() - start:.0f}s]",
            tally,
        )

    scales = (
        [0, 1, 100, 110, 120, 126, 127, 128, 129, 135, 142, 143, 150, 200, 254, 255]
        if args.quick
        else range(256)
    )
    tally = Tally()
    start = time.time()
    print(f"\nscaling_truncf sweep: {len(scales)} scale values x 65536 inputs")
    sweep_truncf(args.mlir_opt, tally, scales)
    failures += report(
        f"scaling_truncf: f16 x f8E8M0FNU -> f4E2M1FN  [{time.time() - start:.0f}s]",
        tally,
    )

    print("\nFAIL" if failures else "\nOK")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
