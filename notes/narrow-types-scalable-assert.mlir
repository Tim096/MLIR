// transform.apply_patterns.vector.rewrite_narrow_types on scalable vectors.
// Used in notes/scalable-patch-candidates.md (S-1a, 2026-11-28 review).
//
//   mlir-opt narrow-types-scalable-assert.mlir -transform-interpreter \
//     -test-transform-dialect-erase-schedule
//
// With an assertions build at 376f04dd8bdb this aborts (rc=134) in
// BitCastBitsEnumerator's constructor, VectorEmulateNarrowType.cpp:1576:
// "requires -D non-scalable vector type". Either function alone triggers it.
// The same functions with fixed-length vectors are rewritten, and a scalable
// extsi with no bitcast in front of it is left unchanged.

func.func @ext_of_bitcast(%a: vector<[8]xi8>) -> vector<[16]xi8> {
  %0 = vector.bitcast %a : vector<[8]xi8> to vector<[16]xi4>
  %1 = arith.extsi %0 : vector<[16]xi4> to vector<[16]xi8>
  return %1 : vector<[16]xi8>
}

func.func @bitcast_of_trunc(%a: vector<[16]xi8>) -> vector<[8]xi8> {
  %0 = arith.trunci %a : vector<[16]xi8> to vector<[16]xi4>
  %1 = vector.bitcast %0 : vector<[16]xi4> to vector<[8]xi8>
  return %1 : vector<[8]xi8>
}

module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%module_op: !transform.any_op {transform.readonly}) {
    %f = transform.structured.match ops{["func.func"]} in %module_op
        : (!transform.any_op) -> !transform.any_op
    transform.apply_patterns to %f {
      transform.apply_patterns.vector.rewrite_narrow_types
    } : !transform.any_op
    transform.yield
  }
}
