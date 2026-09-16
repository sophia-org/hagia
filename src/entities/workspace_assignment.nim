import std/[algorithm, tables]
import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]
import ./tag_ops

proc assignedSlots*(settings: PolicySettings, key: uint64): seq[uint32] =
  for assignment in settings.workspaceAssignments:
    if assignment.outputKey == key:
      result.add(uint32(assignment.number))
  result.sort()

proc bindOutputPolicyKey*(model: var PolicyModel, output: OutputId, key: uint64) =
  ## Runs only on the uncommitted policy candidate. Legacy local ordinals are
  ## remapped together with window and scratchpad membership; view IDs, cameras,
  ## layouts, focus and column identity remain intact.
  if output notin model.outputs or key == 0:
    fail("assigned output requires a nonzero policy key")
  let previous = model.outputs[output].policyKey
  if previous != 0:
    if previous != key:
      fail("live output policy key cannot be reassigned")
    return
  let slots = model.settings.assignedSlots(key)
  if slots.len == 0:
    fail("output policy key has no assigned workspaces")
  var replacements = initTable[TagId, TagId]()
  for view in model.outputs[output].views:
    let tags = model.viewTagIds(view)
    if model.views[view].preferredOutput != output or tags.len != 1:
      fail("legacy output workspace migration is ambiguous")
    let old = model.tags[tags[0]]
    if old.kind != TagKind.profile or old.slot < 1 or old.slot > uint32(slots.len):
      fail("legacy output workspace migration needs matching local ordinals")
    let destination = slots[int(old.slot) - 1]
    let existing = model.tagIdForSlot(destination)
    if existing != nullTagId and model.tags[existing].kind != TagKind.profile:
      fail("legacy migration collides with a dynamic workspace")
    let target = model.profileTag(destination)
    replacements[old.id] = target
  for window in model.windowOrder:
    if model.windows[window].homeOutput != output:
      continue
    for tag in model.windowTagIds(window):
      if tag != model.scratchpadTag and tag notin replacements:
        fail("legacy window membership cannot be assigned unambiguously")
  for view in model.outputs[output].views:
    model.viewTags[view] = @[replacements[model.viewTagIds(view)[0]]]
  for window in model.windowOrder:
    if model.windows[window].homeOutput != output:
      continue
    var tags = model.windowTagIds(window)
    for tag in tags.mitems:
      if tag in replacements:
        tag = replacements[tag]
    model.windowTags[window] = tags
    if window in model.scratchpadRestore:
      var saved = model.scratchpadRestore[window]
      for tag in saved.tags.mitems:
        if tag notin replacements:
          fail("legacy scratchpad membership is ambiguous")
        tag = replacements[tag]
      model.scratchpadRestore[window] = saved
  model.outputs[output].policyKey = key

proc workspaceHost*(model: PolicyModel, number: int): (OutputId, ViewId) =
  ## The current host may be the fallback after unplug. Preferred ownership is
  ## retained by the output affinity and restored when its configured key returns.
  for output in model.outputOrder:
    for view in model.outputs[output].views:
      let tags = model.viewTagIds(view)
      if tags.len == 1 and model.tags[tags[0]].slot == uint32(number):
        if result[0] != nullOutputId:
          fail("workspace number has more than one live owner")
        result = (output, view)

proc validateWorkspaceAssignments*(settings: PolicySettings) =
  var numbers: set[1 .. 9]
  for assignment in settings.workspaceAssignments:
    if assignment.number < 1 or assignment.number > 9 or assignment.outputKey == 0:
      fail("workspace assignment is outside its bounds")
    if assignment.number in numbers:
      fail("workspace numbers must be globally unique")
    numbers.incl(assignment.number)
