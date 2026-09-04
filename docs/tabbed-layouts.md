# Native tabbed layouts

Select `frame-tree`, `notion`, or `i3` in `policy.layout` or `layout-cycle`.
`split-tree` is an alias for `i3`. The corresponding actions are
`layout-frame-tree`, `layout-notion`, and `layout-i3`.

Frame-tree and Notion use private binary trees with ordered tabs in leaf cells.
Splitting a cell with multiple tabs moves its active tab into the new sibling;
splitting a singleton preserves an empty sibling. Only the selected tab is
projected. `frame-unsplit` removes an empty focused cell. Notion computes the
same recursive geometry natively; it does not require Janet.

Use `frame-split-horizontal`, `frame-split-vertical`, `frame-split-toggle`,
`frame-tab-next`, `frame-tab-prev`, `frame-focus-parent`, `frame-focus-child`,
and `frame-resize-left/right/up/down`. Empty cells remain keyboard-addressable.

I3 uses a persistent n-ary split tree. `split-tree-split-horizontal/vertical/toggle`
wrap the focused leaf; `split-tree-layout-split-horizontal/vertical`,
`split-tree-layout-tabbed`, `split-tree-layout-stacking`,
`split-tree-layout-toggle-split`, and `split-tree-layout-cycle-all` change the
container mode. Tabbed and stacking modes both use horizontal strips, matching
Triad. `split-tree-focus-parent/child` and
`split-tree-focus-next-sibling/prev-sibling` navigate the topology.

The ordinary spatial focus actions choose tree behavior in these layouts.
`focus-left/right/up/down` and `move-window-left/right/up/down` are also explicit
tree actions. Grouping and ungrouping operate on the active layout's tree.
Checkpoint version 5 retains tree state and validates topology before restore;
version 4 is accepted with initially empty tree state.

Hagia emits only opaque surface membership and geometry in Sophia's negotiated
revision-3 tab-group extension. Sophia validates and commits the projection,
remaps descriptors for Narthex, and renders the bar using GPU composition.
Hagia receives no titles, application identities, icons, or rendering authority.
Unavailable shell descriptors leave neutral noninteractive bars and keyboard
layout control. Fullscreen suppresses the output's bars.

Application-ID frame bindings, tab dragging/reordering, and parameterized Janet
commands are excluded. This port derives from Triad's recorded baseline in
`docs/provenance.md`; it does not import Triad's compositor ownership.
