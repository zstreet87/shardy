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

include "mlir/Pass/PassBase.td"

def AddDataFlowEdgesPass : Pass<"sdy-add-data-flow-edges", "func::FuncOp"> {
  let summary = "Inserts `DataFlowEdgeOp` for every data-flow edge.";
  let description = [{
    Inserts `DataFlowEdgeOp` for every value that is the owner of a data-flow
    edge, i.e., all values returned by `getDataFlowEdgeOwners` on every op in
    the module.

    The inserted `DataFlowEdgeOp` will take the existing sharding of the owner
    target if it exists.

    TODO(b/330339693): update this doc when `getDataFlowEdgeOwners` is removed.
  }];
  let dependentDialects = ["mlir::sdy::SdyDialect"];
}

def ApplyShardingConstraintsPass : Pass<"sdy-apply-sharding-constraints", "func::FuncOp"> {
  let summary = "Applies constraints that dictate the sharding of their input.";
  let description = [{
    Copies the sharding of a `ShardingConstraintOp` to its input if it satisfies
    all of the following:

    * The input doesn't have an existing sharding.
    * The input isn't produced by a `DataFlowEdgeOp`, which holds the sharding
      of all targets of the edge.
    * The sharding of the `ShardingConstraintOp` is fully closed.
    * The input doesn't have any other users of type `ShardingConstraintOp` or
      `ManualComputationOp`.

    Which indicates that the `ShardingConstraintOp` dictates the sharding of
    its input.

    Note that the sharding of a `ShardingConstraintOp` will propagate to its
    input or users during propagation regardless of this pass, but since the
    closed property of a dimension doesn't propagate, it's important to copy the
    sharding to fully respect the constraint in the above cases.

    The `in_shardings` of a `ManualComputationOp` are in essense sharding
    constraints on the corresponding operands, so this pass will also apply
    their sharding if the above conditions are satisfied (expect for the
    dangling case).
  }];
  let dependentDialects = ["mlir::sdy::SdyDialect"];
}

def ConstantSplitterPass : Pass<"sdy-constant-splitter", "func::FuncOp"> {
  let summary = "Splits constant sub-computations so each has a single use.";
  let description = [{
    Splits constant sub-computations such that they have a single user.

    This ensures that a sharding isn't propagated between different uses of a
    constant sub-computation, as this is considered a false dependency (the uses
    of a constant shouldn't be sharded in the same way just because they use the
    same constant). In effect, each use can have a different sharding that can
    propagate in isolation to its own copy of the constant sub-computation.

    A constant sub-computation is either:
    * a constant or iota op (no operands)
    * a broadcast, slice, or pure element-wise op, whose operands are all
      defined by constant sub-computations (recursively), along with the entire
      sub-computations that define its operands.

    Note that within a constant sub-computation, a value can have multiple uses
    within that sub-computation.

    NOTE: This pass is the MLIR equivalent of xla::HloConstantSplitter,
    needed for the purpose of Shardy Propagation.
  }];
  let dependentDialects = ["mlir::sdy::SdyDialect"];
}

def ShardingGroupUnificationPass : Pass<"sdy-sharding-group-unification", "ModuleOp"> {
  let summary = "Combines sharding groups to reduce them to a minimum set of canonical group ids.";
  let description = [{
    Combines sharding groups using the transitive property of group membership.

    Any time that a tensor T is in a sharding group G1 *and* sharding group G2,
    then we can infer that all members in G1 and G2 should be sharded in the
    same way. Thus we can combine G1 and G2 into a single group.

    The set of canonical group ids after merging will be 0,1,...N-1 for the
    minimum set of groups.
  }];
  let dependentDialects = ["mlir::sdy::SdyDialect"];
}

def ImportMaximalShardingPass : Pass<"sdy-import-maximal-sharding", "ModuleOp"> {
  let summary = "Convert sdy.sharding=n to maximal sharding.";
  let description = [{
    Convert `sdy.sharding=n` to maximal sharding as follows:

    ```mlir
    @sdy.mesh @maximal_mesh_n = <device_ids=[n]>
    sdy.sharding = #sdy.sharding<@maximal_mesh_n, [...]>
    ```
  }];
  let dependentDialects = ["mlir::sdy::SdyDialect"];
}
