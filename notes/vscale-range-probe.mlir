// What does the integer range analysis know about vscale * 8?
// Used in notes/visibility-track-candidates.md (topic 1, 2026-11-28 review).
//
//   mlir-opt vscale-range-probe.mlir -int-range-optimizations
//
// test.with_bounds stands in for a vscale that has the given range;
// test.reflect_bounds prints the range the analysis inferred.

// (a) today: vector.vscale has no range
func.func @today() -> (i1, index) {
  %vs = vector.vscale
  %c0 = arith.constant 0 : index
  %ne = arith.cmpi ne, %vs, %c0 : index
  %r = test.reflect_bounds %vs : index
  return %ne, %r : i1, index
}
// (b) vscale in [1, UMAX] (what "returns [1, max]" gives), step = vscale * 8
func.func @lower_only() -> (index, index, index) {
  %vs = test.with_bounds < umin = 1 : index, umax = -1 : index, smin = -9223372036854775808 : index, smax = 9223372036854775807 : index > : index
  %c8 = arith.constant 8 : index
  %m = arith.muli %vs, %c8 : index
  %mnuw = arith.muli %vs, %c8 overflow<nuw> : index
  %mnsw = arith.muli %vs, %c8 overflow<nsw> : index
  %r0 = test.reflect_bounds %m : index
  %r1 = test.reflect_bounds %mnuw : index
  %r2 = test.reflect_bounds %mnsw : index
  return %r0, %r1, %r2 : index, index, index
}
// (c) vscale in [1, SMAX] (positive as signed too)
func.func @lower_signed() -> (index, index, index) {
  %vs = test.with_bounds < umin = 1 : index, umax = 9223372036854775807 : index, smin = 1 : index, smax = 9223372036854775807 : index > : index
  %c8 = arith.constant 8 : index
  %m = arith.muli %vs, %c8 : index
  %mnuw = arith.muli %vs, %c8 overflow<nuw> : index
  %mnsw = arith.muli %vs, %c8 overflow<nsw> : index
  %r0 = test.reflect_bounds %m : index
  %r1 = test.reflect_bounds %mnuw : index
  %r2 = test.reflect_bounds %mnsw : index
  return %r0, %r1, %r2 : index, index, index
}
// (d) vscale in [1, 16] (SVE: 128..2048 bit), no flags
func.func @bounded() -> (index, i1) {
  %vs = test.with_bounds < umin = 1 : index, umax = 16 : index, smin = 1 : index, smax = 16 : index > : index
  %c8 = arith.constant 8 : index
  %c0 = arith.constant 0 : index
  %m = arith.muli %vs, %c8 : index
  %ne = arith.cmpi ne, %m, %c0 : index
  %r0 = test.reflect_bounds %m : index
  return %r0, %ne : index, i1
}
