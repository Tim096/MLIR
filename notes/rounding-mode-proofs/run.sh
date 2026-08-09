#!/bin/bash
# Q1 的證明腳本：三個掛著 rounding-mode TODO 的 canonicalization 安不安全。
# rm 宣告成自由變數 => 一次證完所有捨入模式，不是逐一列舉。
# 用 `=`（值相等，+0 != -0）而不是 fp.eq，否則會漏掉 subf 的那個 -0 反例。
set -e
for W in "Float16 5 11" "Float32 8 24" "Float64 11 53"; do
  set -- $W; T=$1; E=$2; S=$3

  for OP in mul div; do
    printf '(set-logic QF_FP)(declare-const x %s)(declare-const y %s)(declare-const rm RoundingMode)(assert (not (= (fp.%s rm (fp.neg x) (fp.neg y)) (fp.%s rm x y))))(check-sat)\n' \
      "$T" "$T" "$OP" "$OP" > /tmp/q1.smt2
    echo "$T ${OP}f(negf x, negf y) -> ${OP}f(x, y)          : $(z3 /tmp/q1.smt2)   (want unsat)"
  done

  # subf: 先要反例
  printf '(set-logic QF_FP)(declare-const x %s)(declare-const rm RoundingMode)(assert (not (= (fp.sub rm (_ -zero %s %s) x) (fp.neg x))))(check-sat)(get-model)\n' \
    "$T" "$E" "$S" > /tmp/q1.smt2
  echo "$T subf(-0.0, x) -> negf(x)                    : $(z3 /tmp/q1.smt2 | tr '\n' ' ')   (want sat)"

  # subf: 排除那唯一一組反例後應該就沒有別的了
  printf '(set-logic QF_FP)(declare-const x %s)(declare-const rm RoundingMode)(assert (not (= (fp.sub rm (_ -zero %s %s) x) (fp.neg x))))(assert (not (and (= rm roundTowardNegative) (= x (_ -zero %s %s)))))(check-sat)\n' \
    "$T" "$E" "$S" "$E" "$S" > /tmp/q1.smt2
  echo "$T   ^ 排除 (x=-0, RTN) 之後                    : $(z3 /tmp/q1.smt2)   (want unsat => 反例唯一)"
  echo
done
