import ../state/[id_gen, model, queries, values]
import
  ../entities/
    [column_ops, focus_ops, group_ops, output_ops, tag_ops, view_ops, window_ops]
import
  ../systems/[focus, layout, movement, placement, scratchpad, window_state, workspaces]

## Facade over the data-oriented layers, so a caller names one module instead of
## eleven. Triad's `docs/dod-architecture.md` describes the same front for its
## state layer. New code may import a layer directly; this exists so the split
## did not churn every consumer.

export id_gen, model, queries, values
export column_ops, focus_ops, group_ops, output_ops, tag_ops, view_ops, window_ops
export focus, layout, movement, placement, scratchpad, window_state, workspaces
