; src = the algorithm used by the new CeilDivSIOp::fold
; tgt = the expansion arith-expand already uses for arith.ceildivsi
; Both generated from MLIR via --convert-to-llvm | mlir-translate --mlir-to-llvmir

define i8 @src(i8 %0, i8 %1) {
  %3 = sdiv i8 %0, %1
  %4 = srem i8 %0, %1
  %5 = icmp ne i8 %4, 0
  %6 = icmp slt i8 %0, 0
  %7 = icmp slt i8 %1, 0
  %8 = icmp eq i1 %6, %7
  %9 = and i1 %5, %8
  %10 = add i8 %3, 1
  %11 = select i1 %9, i8 %10, i8 %3
  ret i8 %11
}

define i8 @tgt(i8 %0, i8 %1) {
  %3 = sdiv i8 %0, %1
  %4 = mul i8 %3, %1
  %5 = icmp ne i8 %0, %4
  %6 = icmp slt i8 %0, 0
  %7 = icmp slt i8 %1, 0
  %8 = icmp eq i1 %6, %7
  %9 = and i1 %5, %8
  %10 = add i8 %3, 1
  %11 = select i1 %9, i8 %10, i8 %3
  ret i8 %11
}
