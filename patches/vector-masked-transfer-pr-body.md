`LowerVectorTransfer.cpp` builds its patterns on `MaskableOpRewritePattern`,
whose purpose is to let a pattern rewrite an op sitting inside a `vector.mask`
region, but every one of them declines to:

```cpp
// TODO: Support transfer_read inside MaskOp case.
if (maskOp)
  return rewriter.notifyMatchFailure(op, "Masked case not supported");
```

This turns that path on for `TransferReadPermutationLowering` and
`TransferWritePermutationLowering`.

The mask itself needs no adjustment, which is the part worth checking. Per
`inferTransferOpMaskType`, a transfer op's mask is not indexed like the
transferred vector: its shape is the vector shape mapped back through the
inverse of the permutation map, so it is indexed in memory order. Both
rewrites only reorder the vector -- one transposes the result of a read, the
other transposes the value handed to a write -- and neither changes which
memory dimensions are touched. The existing tests show this directly: the
write case keeps its `vector<8x4xi1>` mask and the read case its
`vector<2x4xi1>`. A passthru does follow the vector, since its type is the
result type, so on the read side it is permuted along with the result.

Three existing tests therefore change from "not lowered" to lowered. The four
other `..._masked` tests in that file belong to
`TransferWriteNonPermutationLowering` and `TransferOpReduceRank` and are
unchanged. Those two are left for a follow-up: one adds unit dimensions and
the other drops leading broadcast dimensions, so in both cases the mask does
need a transformation. The remaining two patterns cannot support masking at
all, as they target `vector.load` and `vector.store`, which have no mask
operand.

Note that #200703 also touches these functions, dropping their 0-d guards.
The changes are independent, but they sit on adjacent lines, so whichever
lands second will need a trivial rebase.
