/* Copyright 2024 The Shardy Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
==============================================================================*/

#include <cstdint>

#include "llvm/ADT/STLExtras.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"
#include "shardy/dialect/sdy/ir/dialect.h"

namespace mlir {
namespace sdy {

namespace {

#include "shardy/dialect/sdy/ir/canonicalization.cc.inc"

// Pattern to remove unused block arguments and their corresponding operands
// from  a `ManualComputationOp`.
class ManualComputationUnusedInputsPattern
    : public OpRewritePattern<ManualComputationOp> {
 public:
  using OpRewritePattern<ManualComputationOp>::OpRewritePattern;

 private:
  LogicalResult matchAndRewrite(ManualComputationOp manualComputationOp,
                                PatternRewriter& rewriter) const override {
    BitVector unusedArgs(manualComputationOp.getNumOperands());
    for (BlockArgument arg : manualComputationOp.getRegion().getArguments()) {
      if (arg.use_empty()) {
        unusedArgs.set(arg.getArgNumber());
      }
    }
    if (unusedArgs.none()) {
      return failure();
    }

    manualComputationOp->eraseOperands(unusedArgs);
    manualComputationOp.getRegion().front().eraseArguments(unusedArgs);

    SmallVector<TensorShardingAttr> inShardings;
    inShardings.reserve(manualComputationOp.getNumOperands());
    for (int64_t index : unusedArgs.flip().set_bits()) {
      inShardings.push_back(manualComputationOp.getInSharding(index));
    }
    manualComputationOp.setInShardingsAttr(TensorShardingPerValueAttr::get(
        manualComputationOp.getContext(), inShardings));

    return success();
  }
};

// Pattern to remove duplicate (same input and group id) ShardingGroupOps within
// the same block.
class DedupShardingGroupPattern : public OpRewritePattern<ShardingGroupOp> {
 public:
  using OpRewritePattern<ShardingGroupOp>::OpRewritePattern;
  void initialize() { setDebugName("DedupShardingGroupPattern"); }

 private:
  LogicalResult matchAndRewrite(ShardingGroupOp shardingGroupOp,
                                PatternRewriter& rewriter) const override {
    // Loop over all ShardingGroupOps with the same input. IF there are any
    // ShardingGroupOps with the same group id, THEN delete the current op.
    bool anyDeduped = false;
    for (Operation* otherOp :
         llvm::make_early_inc_range(shardingGroupOp.getInput().getUsers())) {
      if (otherOp == shardingGroupOp) {
        continue;
      }
      if (auto otherShardingGroupOp = dyn_cast<ShardingGroupOp>(otherOp);
          otherShardingGroupOp != nullptr &&
          otherShardingGroupOp.getGroupId() == shardingGroupOp.getGroupId()) {
        rewriter.eraseOp(otherOp);
        anyDeduped = true;
      }
    }
    return success(anyDeduped);
  }
};

}  // namespace

void ManualComputationOp::getCanonicalizationPatterns(
    RewritePatternSet& results, MLIRContext* context) {
  results.add<ManualComputationUnusedInputsPattern>(context);
}

void ReshardOp::getCanonicalizationPatterns(RewritePatternSet& results,
                                            MLIRContext* context) {
  results.add<ReshardOfReshardPattern>(context);
}

void ShardingGroupOp::getCanonicalizationPatterns(RewritePatternSet& results,
                                                  MLIRContext* context) {
  results.add<DedupShardingGroupPattern>(context);
}

}  // namespace sdy
}  // namespace mlir
