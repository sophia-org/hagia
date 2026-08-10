module entities

sig LogicalId {}
abstract sig TagKind {}
one sig ProfileTag, DynamicTag, ScratchpadTag extends TagKind {}
sig Tag {
  tagId: one LogicalId,
  kind: one TagKind
}
sig Output {
  outputId: one LogicalId,
  active: one View
}
sig View {
  viewId: one LogicalId,
  owner: one Output,
  selected: some Tag
}
sig Column {
  columnId: one LogicalId,
  owner: one Output
}
sig Window {
  windowId: one LogicalId,
  owner: one Output,
  column: one Column,
  member: some Tag,
  parent: lone Window,
  restore: set Tag
}

fact IdentityUniqueness {
  no disj a, b: Tag | a.tagId = b.tagId
  no disj a, b: Output | a.outputId = b.outputId
  no disj a, b: View | a.viewId = b.viewId
  no disj a, b: Column | a.columnId = b.columnId
  no disj a, b: Window | a.windowId = b.windowId
}

fact OwnershipConsistency {
  all window: Window | window.column.owner = window.owner
  all output: Output | output.active.owner = output
}

fact DynamicWorkspaceLiveness {
  all tag: Tag |
    tag.kind = DynamicTag implies
      (some window: Window | tag in window.member or tag in window.restore) or
      (some output: Output | tag in output.active.selected)
}

fact ScratchpadIsolation {
  all view: View | no tag: view.selected | tag.kind = ScratchpadTag
  all window: Window |
    (some tag: window.member | tag.kind = ScratchpadTag) implies
      ((all tag: window.member | tag.kind = ScratchpadTag) and
      (some tag: window.restore | tag.kind != ScratchpadTag))
  no window: Window | window in window.^parent
}

assert EntityOwnership {
  all window: Window | one window.owner and one window.column
  all view: View | one view.owner
}

assert MembershipNonempty {
  all window: Window | some window.member
  all view: View | some view.selected
}

assert NoDanglingReferences {
  all window: Window |
    window.owner in Output and window.column in Column and window.member in Tag
  all view: View | view.owner in Output and view.selected in Tag
}

assert UniqueIds {
  all disj a, b: Window | a.windowId != b.windowId
  all disj a, b: View | a.viewId != b.viewId
  all disj a, b: Column | a.columnId != b.columnId
  all disj a, b: Output | a.outputId != b.outputId
  all disj a, b: Tag | a.tagId != b.tagId
}

assert NoStaleDynamicWorkspace {
  no tag: Tag |
    tag.kind = DynamicTag and
    (no window: Window | tag in window.member) and
    (no window: Window | tag in window.restore) and
    (no output: Output | tag in output.active.selected)
}

assert ScratchpadsCannotBecomeViews {
  no view: View, tag: view.selected | tag.kind = ScratchpadTag
}

assert ScratchpadsRetainRestoreMembership {
  all window: Window |
    (some tag: window.member | tag.kind = ScratchpadTag) implies
      (some tag: window.restore | tag.kind != ScratchpadTag)
}

assert ParentGraphIsAcyclic {
  no window: Window | window in window.^parent
}

check EntityOwnership for 8
check MembershipNonempty for 8
check NoDanglingReferences for 8
check UniqueIds for 8
check NoStaleDynamicWorkspace for 8
check ScratchpadsCannotBecomeViews for 8
check ScratchpadsRetainRestoreMembership for 8
check ParentGraphIsAcyclic for 8
