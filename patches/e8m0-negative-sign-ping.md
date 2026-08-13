Ping on the question above, and one more data point for it: the sign half is not
specific to `f8E8M0FNU`. `semFloat8E5M3FNU` also has `hasSignedRepr == false`, and
converting a negative constant into it goes the same way -- `convert` reports no
loss, and printing the result hits the same `llvm_unreachable`:

```mlir
%c = arith.constant -2.000000e+00 : f8E5M3FNU
```

So this is a property of the `hasSignedRepr == false` formats rather than one
format's quirk, and the fix belongs in `convert` rather than at any single call
site. `hasZero == false` is `f8E8M0FNU` alone today.

Unless someone objects to reporting the loss, I will send that patch with both
reproducers as tests: `convert` returns `opInexact` and sets `losesInfo` when the
target cannot represent the sign or the zero of the source value, which leaves
every caller shown above -- all of which already check `losesInfo` -- rejecting
the conversion instead of accepting an unrepresentable result.

@tgymnich @krzysz00 @umangyadav @kuhar
