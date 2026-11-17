#!/usr/bin/env python3
"""Three-way check of the integer ops in `arith` and `index`.

For every op and every pair of inputs, three answers are compared:

  ref   the documented semantics, written here in plain Python
  fold  what the folder produces (`mlir-opt -canonicalize` on constants)
  exec  what the lowering computes (expand + LLVM lowering, run by mlir-runner)

`arith` is checked exhaustively on i4 (256 pairs per op) and on boundary values
of i8, `index` on boundary values of the 64-bit type. Inputs for which the op documents undefined
behaviour or poison are skipped for `exec` and reported separately for `fold`.

Usage: probe.py <llvm-project> <out-dir>
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
BIN = ROOT / "build/bin"
LIBS = ROOT / "build/lib/libmlir_c_runner_utils.so"


def wrap(v, w):
    v &= (1 << w) - 1
    return v - (1 << w) if v >> (w - 1) else v


def uns(v, w):
    return v & ((1 << w) - 1)


def tdiv(a, b):  # truncating division
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def ceil_div(a, b):
    return -((-a) // b)


# name -> (reference, undefined(a, b, w)); a and b are signed values.
def ops(w):
    lo = -(1 << (w - 1))

    def z(a, b, w):
        return b == 0

    def zo(a, b, w):
        return b == 0 or (a == lo and b == -1)

    def sh(a, b, w):
        return uns(b, w) >= w

    def never(a, b, w):
        return False

    return {
        "add": (lambda a, b: a + b, never),
        "sub": (lambda a, b: a - b, never),
        "mul": (lambda a, b: a * b, never),
        "divs": (tdiv, zo),
        "divu": (lambda a, b: uns(a, w) // uns(b, w), z),
        "rems": (lambda a, b: a - b * tdiv(a, b), zo),
        "remu": (lambda a, b: uns(a, w) % uns(b, w), z),
        "ceildivs": (ceil_div, zo),
        "ceildivu": (lambda a, b: -((-uns(a, w)) // uns(b, w)), z),
        "floordivs": (lambda a, b: a // b, zo),
        "shl": (lambda a, b: a << uns(b, w), sh),
        "shrs": (lambda a, b: a >> uns(b, w), sh),
        "shru": (lambda a, b: uns(a, w) >> uns(b, w), sh),
        "maxs": (max, never),
        "mins": (min, never),
        "maxu": (lambda a, b: max(uns(a, w), uns(b, w)), never),
        "minu": (lambda a, b: min(uns(a, w), uns(b, w)), never),
    }


ARITH = {
    "add": "addi", "sub": "subi", "mul": "muli", "divs": "divsi",
    "divu": "divui", "rems": "remsi", "remu": "remui",
    "ceildivs": "ceildivsi", "ceildivu": "ceildivui",
    "floordivs": "floordivsi", "shl": "shli", "shrs": "shrsi", "shru": "shrui",
    "maxs": "maxsi", "mins": "minsi", "maxu": "maxui", "minu": "minui",
}
INDEX = {k: k for k in ARITH}

DECLS = """
func.func private @printI64(i64)
func.func private @printNewline()
"""
LOWER = ("--arith-expand,--convert-scf-to-cf,--convert-index-to-llvm,"
         "--convert-arith-to-llvm,--convert-func-to-llvm,--convert-cf-to-llvm,"
         "--reconcile-unrealized-casts").split(",")


def sh_run(cmd, stdin):
    p = subprocess.run(cmd, input=stdin.encode(), capture_output=True)
    return p.returncode, p.stdout.decode(), p.stderr.decode(errors="replace")


def emit(dialect, opname, ty, pairs, constants):
    """One call to @f per pair. With `constants` the op is inlined on
    constants (for the folder), otherwise it sits behind a call."""
    mn = f"{dialect}.{opname}"
    cst = "index.constant" if ty == "index" else "arith.constant"

    def const(name, v):
        if ty == "index":
            return f"  %{name} = index.constant {v}\n"
        return f"  %{name} = arith.constant {v} : {ty}\n"

    def to_i64(src, dst):
        if ty == "index":
            return f"  %{dst} = index.casts %{src} : index to i64\n"
        return f"  %{dst} = arith.extsi %{src} : {ty} to i64\n"

    out = [DECLS]
    if not constants:
        out.append(f"func.func private @f(%a: {ty}, %b: {ty}) -> {ty} "
                   "attributes {no_inline} {\n"
                   f"  %r = {mn} %a, %b" + ("" if ty == "index" else f" : {ty}")
                   + f"\n  return %r : {ty}\n}}\n")
    out.append("func.func @main() {\n")
    for i, (a, b) in enumerate(pairs):
        out.append(const(f"a{i}", a) + const(f"b{i}", b))
        if constants:
            out.append(f"  %r{i} = {mn} %a{i}, %b{i}"
                       + ("" if ty == "index" else f" : {ty}") + "\n")
        else:
            out.append(f"  %r{i} = call @f(%a{i}, %b{i}) : ({ty}, {ty}) -> {ty}\n")
        out.append(to_i64(f"r{i}", f"x{i}"))
        out.append(f"  call @printI64(%x{i}) : (i64) -> ()\n"
                   "  call @printNewline() : () -> ()\n")
    out.append("  return\n}\n")
    return "".join(out)


def run_exec(src):
    rc, low, err = sh_run([str(BIN / "mlir-opt")] + LOWER, src)
    if rc:
        return None, "lowering failed: " + err.strip().split("\n")[0][:200]
    rc, out, err = sh_run(
        [str(BIN / "mlir-runner"), "-e", "main", "-entry-point-result=void",
         f"-shared-libs={LIBS}"], low)
    if rc:
        return None, f"runner rc={rc}: " + err.strip().split("\n")[0][:200]
    return [int(x) for x in out.split()], ""


def run_fold(src, n):
    """Folded results, in call order. None where the op was not folded."""
    rc, out, err = sh_run([str(BIN / "mlir-opt"), "--canonicalize"], src)
    if rc:
        return None, "canonicalize failed: " + err.strip().split("\n")[0][:200]
    consts = {}
    for m in re.finditer(r"%(\S+) = arith\.constant (-?\d+) : i64", out):
        consts[m.group(1)] = int(m.group(2))
    res = []
    for m in re.finditer(r"call @printI64\(%([^)\s]+)\)", out):
        res.append(consts.get(m.group(1)))
    if len(res) != n:
        return None, f"expected {n} prints, saw {len(res)}"
    return res, ""


def check(dialect, table, ty, w, values, report):
    sem = ops(w)
    for key, opname in table.items():
        ref, undef = sem[key]
        pairs = [(a, b) for a in values for b in values]
        defined = [p for p in pairs if not undef(p[0], p[1], w)]
        fold, ferr = run_fold(emit(dialect, opname, ty, pairs, True), len(pairs))
        execd, eerr = run_exec(emit(dialect, opname, ty, defined, False))
        traps = []
        if execd is None and eerr.startswith("runner"):
            # The batch died: run the pairs one by one to find which trap.
            execd = []
            for pr in defined:
                one, err1 = run_exec(emit(dialect, opname, ty, [pr], False))
                if one is None:
                    traps.append(pr)
                    execd.append(wrap(ref(pr[0], pr[1]), w))
                else:
                    execd.append(one[0])
            eerr = f"traps={len(traps)}"
        row = {"fold_wrong": [], "fold_undef": [], "exec_wrong": [],
               "exec_trap": traps,
               "fold_err": ferr, "exec_err": eerr, "unfolded": 0}
        if fold is not None:
            for (a, b), got in zip(pairs, fold):
                if undef(a, b, w):
                    if got is not None:
                        row["fold_undef"].append((a, b, got))
                    continue
                if got is None:
                    row["unfolded"] += 1
                elif got != wrap(ref(a, b), w):
                    row["fold_wrong"].append((a, b, got, wrap(ref(a, b), w)))
        if execd is not None:
            for (a, b), got in zip(defined, execd):
                if got != wrap(ref(a, b), w):
                    row["exec_wrong"].append((a, b, got, wrap(ref(a, b), w)))
        report.append((f"{dialect}.{opname}", ty, len(pairs), len(defined), row))
        print(f"{dialect}.{opname} {ty}: fold_wrong={len(row['fold_wrong'])} "
              f"fold_on_undef={len(row['fold_undef'])} "
              f"exec_wrong={len(row['exec_wrong'])} unfolded={row['unfolded']} "
              f"{ferr} {eerr}", flush=True)


def main():
    report = []
    check("arith", ARITH, "i4", 4, list(range(-8, 8)), report)
    e8 = [-128, -127, -126, -65, -64, -9, -8, -7, -3, -2, -1, 0, 1, 2, 3, 7, 8,
          9, 63, 64, 126, 127]
    check("arith", ARITH, "i8", 8, e8, report)
    lo, hi = -(1 << 63), (1 << 63) - 1
    edge = sorted({lo, lo + 1, lo + 2, -(1 << 62), -(1 << 32), -(1 << 31) - 1,
                   -(1 << 31), -65, -64, -63, -3, -2, -1, 0, 1, 2, 3, 63, 64, 65,
                   (1 << 31) - 1, 1 << 31, 1 << 32, 1 << 62, hi - 1, hi})
    check("index", INDEX, "index", 64, edge, report)
    with (OUT / "report.txt").open("w") as fh:
        for name, ty, n, d, row in report:
            fh.write(f"## {name} {ty} pairs={n} defined={d} "
                     f"unfolded={row['unfolded']} {row['fold_err']} "
                     f"{row['exec_err']}\n")
            for kind in ("fold_wrong", "exec_wrong", "exec_trap", "fold_undef"):
                items = row[kind]
                fh.write(f"  {kind}: {len(items)}\n")
                for it in items[:12]:
                    fh.write(f"    {it}\n")


if __name__ == "__main__":
    main()
