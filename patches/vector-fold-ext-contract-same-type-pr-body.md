`FoldArithExtIntoContractionOp` checks that both contraction operands are produced by the same kind of extension, but not that the extensions start from the same element type. With `extsi` from i8 on one side and from i16 on the other it rewrites the contraction to take the two sources directly, and the result fails to verify:

```
'vector.contract' op failed to verify that lhs and rhs have same element type
```

The same happens with `extf` from f16 and bf16. Compare the source element types and leave such contractions alone.

Tests: one `extf` and one `extsi` case in `fold-arith-extf-into-vector-contract.mlir` that keep the extensions.
