; S-1 (notes/scalable-patch-candidates.md): can the AArch64 SVE backend handle
; sub-byte scalable vectors? Each function loads from %in and stores to %out so
; that no scalable sub-byte value crosses a function boundary.
;
; *_direct    : what MLIR emits today (arith.trunci / arith.extsi on i4 vectors)
; *_rewritten : what RewriteAlignedSubByteInt{Trunc,Ext} would emit if it
;               accepted scalable vectors (bitcast + (de)interleave + bit ops)
;
; The old "experimental" intrinsic names are used so that LLVM 18 accepts the
; file; newer LLVM auto-upgrades them.
target triple = "aarch64-unknown-linux-gnu"

declare { <vscale x 8 x i8>, <vscale x 8 x i8> } @llvm.experimental.vector.deinterleave2.nxv16i8(<vscale x 16 x i8>)
declare <vscale x 16 x i8> @llvm.experimental.vector.interleave2.nxv16i8(<vscale x 8 x i8>, <vscale x 8 x i8>)

define void @trunc_direct(ptr %in, ptr %out) #0 {
  %v = load <vscale x 16 x i8>, ptr %in, align 1
  %t = trunc <vscale x 16 x i8> %v to <vscale x 16 x i4>
  %b = bitcast <vscale x 16 x i4> %t to <vscale x 8 x i8>
  store <vscale x 8 x i8> %b, ptr %out, align 1
  ret void
}

define void @trunc_rewritten(ptr %in, ptr %out) #0 {
  %c15.0 = insertelement <vscale x 8 x i8> poison, i8 15, i64 0
  %c15 = shufflevector <vscale x 8 x i8> %c15.0, <vscale x 8 x i8> poison, <vscale x 8 x i32> zeroinitializer
  %c4.0 = insertelement <vscale x 8 x i8> poison, i8 4, i64 0
  %c4 = shufflevector <vscale x 8 x i8> %c4.0, <vscale x 8 x i8> poison, <vscale x 8 x i32> zeroinitializer
  %v = load <vscale x 16 x i8>, ptr %in, align 1
  %d = call { <vscale x 8 x i8>, <vscale x 8 x i8> } @llvm.experimental.vector.deinterleave2.nxv16i8(<vscale x 16 x i8> %v)
  %even = extractvalue { <vscale x 8 x i8>, <vscale x 8 x i8> } %d, 0
  %odd = extractvalue { <vscale x 8 x i8>, <vscale x 8 x i8> } %d, 1
  %lo = and <vscale x 8 x i8> %even, %c15
  %hi = shl <vscale x 8 x i8> %odd, %c4
  %m = or <vscale x 8 x i8> %lo, %hi
  %i4 = bitcast <vscale x 8 x i8> %m to <vscale x 16 x i4>
  %b = bitcast <vscale x 16 x i4> %i4 to <vscale x 8 x i8>
  store <vscale x 8 x i8> %b, ptr %out, align 1
  ret void
}

define void @sext_direct(ptr %in, ptr %out) #0 {
  %v = load <vscale x 8 x i8>, ptr %in, align 1
  %i4 = bitcast <vscale x 8 x i8> %v to <vscale x 16 x i4>
  %e = sext <vscale x 16 x i4> %i4 to <vscale x 16 x i8>
  store <vscale x 16 x i8> %e, ptr %out, align 1
  ret void
}

define void @sext_rewritten(ptr %in, ptr %out) #0 {
  %c4.0 = insertelement <vscale x 8 x i8> poison, i8 4, i64 0
  %c4 = shufflevector <vscale x 8 x i8> %c4.0, <vscale x 8 x i8> poison, <vscale x 8 x i32> zeroinitializer
  %v0 = load <vscale x 8 x i8>, ptr %in, align 1
  %i4 = bitcast <vscale x 8 x i8> %v0 to <vscale x 16 x i4>
  %v = bitcast <vscale x 16 x i4> %i4 to <vscale x 8 x i8>
  %s = shl <vscale x 8 x i8> %v, %c4
  %lo = ashr <vscale x 8 x i8> %s, %c4
  %hi = ashr <vscale x 8 x i8> %v, %c4
  %r = call <vscale x 16 x i8> @llvm.experimental.vector.interleave2.nxv16i8(<vscale x 8 x i8> %lo, <vscale x 8 x i8> %hi)
  store <vscale x 16 x i8> %r, ptr %out, align 1
  ret void
}

attributes #0 = { "target-features"="+sve" }
