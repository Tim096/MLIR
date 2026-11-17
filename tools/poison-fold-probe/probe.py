#!/usr/bin/env python3
"""Mutation probe: does a folder survive a ub.poison operand?

For every `-canonicalize` test under mlir/test, each test case (split on
`// -----`) is mutated by replacing one constant definition at a time with
`ub.poison` of the same type. The mutated case is run through
`mlir-opt --canonicalize`. A run that dies on a signal is recorded together
with the assertion text and the first `::fold` / pattern frame of the stack.

Usage: probe.py <llvm-project> <out.tsv> [jobs]
"""
import concurrent.futures as cf
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
JOBS = int(sys.argv[3]) if len(sys.argv) > 3 else 8
OPT = ROOT / "build/bin/mlir-opt"
MAX_MUTANTS_PER_CASE = 12

# `%x = arith.constant <value> : <type>` and friends. The type is whatever
# follows the last " : " on the line.
TYPED = re.compile(
    r"^(\s*%[\w.\-]+\s*=\s*)(?:arith\.constant|index\.constant|"
    r"shape\.const_shape|shape\.const_size|complex\.constant)\b(.*)$")
BOOL = re.compile(r"^(\s*%[\w.\-]+\s*=\s*)arith\.constant\s+(?:true|false)\s*$")


def poison_line(line):
    body = line.split("//")[0].rstrip()
    m = BOOL.match(body)
    if m:
        return m.group(1) + "ub.poison : i1"
    m = TYPED.match(body)
    if not m:
        return None
    rest = m.group(2)
    if "index.constant" in body:
        return m.group(1) + "ub.poison : index"
    if "shape.const_size" in body:
        return m.group(1) + "ub.poison : !shape.size"
    if " : " not in rest:
        return None
    ty = rest.rsplit(" : ", 1)[1].strip()
    if not ty or "->" in ty:
        return None
    return m.group(1) + "ub.poison : " + ty


def mutants(path):
    text = path.read_text(errors="replace")
    if not re.search(r"RUN:.*canonicalize", text):
        return
    for ci, case in enumerate(re.split(r"^// -----.*$", text, flags=re.M)):
        lines = case.split("\n")
        n = 0
        for li, line in enumerate(lines):
            new = poison_line(line)
            if new is None:
                continue
            n += 1
            if n > MAX_MUTANTS_PER_CASE:
                break
            yield (path, ci, li, line.strip(),
                   "\n".join(lines[:li] + [new] + lines[li + 1:]))


FRAME = re.compile(r"#\d+ 0x[0-9a-f]+ (.*?) \(")


def run(job):
    path, ci, li, orig, src = job
    try:
        p = subprocess.run(
            [str(OPT), "--canonicalize", "--allow-unregistered-dialect"],
            input=src.encode(), capture_output=True, timeout=30)
    except subprocess.TimeoutExpired:
        return (path, ci, li, orig, "TIMEOUT", "", "")
    if p.returncode >= 0:
        return None
    err = p.stderr.decode(errors="replace")
    msg = ""
    m = re.search(r"Assertion `(.*?)' failed", err)
    if m:
        msg = m.group(1)[:120]
    where = ""
    for f in FRAME.findall(err):
        if "::fold" in f or "matchAndRewrite" in f or "canonicalize" in f:
            where = re.sub(r"\(.*", "", f)[:120]
            break
    return (path, ci, li, orig, f"SIG{-p.returncode}", msg, where)


def main():
    files = sorted((ROOT / "mlir/test").rglob("*.mlir"))
    jobs = [j for f in files for j in mutants(f)]
    print(f"{len(jobs)} mutants", file=sys.stderr)
    rows = []
    with cf.ThreadPoolExecutor(JOBS) as ex:
        for r in ex.map(run, jobs):
            if r:
                rows.append(r)
    with OUT.open("w") as fh:
        fh.write(f"# mutants={len(jobs)} crashes={len(rows)}\n")
        for path, ci, li, orig, sig, msg, where in rows:
            rel = path.relative_to(ROOT)
            fh.write(f"{rel}\t{ci}\t{li}\t{sig}\t{where}\t{msg}\t{orig}\n")
    print(f"{len(rows)} crashes", file=sys.stderr)


if __name__ == "__main__":
    main()
