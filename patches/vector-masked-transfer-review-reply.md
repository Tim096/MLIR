# Reply draft — #215318, answering banach-space's review

Two inline replies plus one top-level comment. Post after pushing the commit
that fixes the comment and adds the passthru test.

---

## Inline, on `LowerVectorTransfer.cpp:143` ("Something missing in this sentence?")

It read as if the clause were cut off. Rewritten:

```
// Re-apply an enclosing vector.mask. Its mask is indexed in memory order,
// so only the passthru has to be transposed.
```

## Inline, on `LowerVectorTransfer.cpp:149` ("add a test with passthru")

Added `@xfer_read_minor_identity_transposed_masked_with_passthru`. It uses a
three-dimensional permutation on purpose: the existing masked read tests
transpose by `[0, 2, 1]`, which is its own inverse, so they cannot tell
`invertPermutationVector` apart from a plain transpose. This one permutes by
`[2, 0, 1]` and fails if the inverse is dropped.

## Top-level ("Will there be follow-ups?")

Yes. `TransferWriteNonPermutationLowering` and `TransferOpReduceRank` are the
two that can be masked, and in both the mask does need a transformation rather
than passing straight through -- one adds unit dimensions, the other drops
leading broadcast dimensions -- so each needs its own argument. I would rather
send them separately than grow this patch.
