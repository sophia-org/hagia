import std/sets

import ../types/[session, wm_v1]
import ./[policy_semantics, policy_transport]

## Shared complete-snapshot checks. Legacy identity exceptions are explicit
## at its wrapper; the file path uses strict identities without changing it.

proc validateSnapshotFields(snapshot: PolicySnapshot, strictIdentities: bool) =
  if snapshot.generation == 0 or snapshot.activeOutput == 0 or snapshot.outputs.len == 0 or
      snapshot.outputs.len > maxOutputs or snapshot.surfaces.len > maxSurfaces:
    fail("policy snapshot count is invalid")
  var outputs = initHashSet[uint64]()
  for output in snapshot.outputs:
    if output.output == 0 or output.generation == 0 or output.width <= 0 or
        output.height <= 0 or output.workWidth <= 0 or output.workHeight <= 0 or
        output.workX < output.x or output.workY < output.y or
        int64(output.workX) + int64(output.workWidth) >
        int64(output.x) + int64(output.width) or
        int64(output.workY) + int64(output.workHeight) >
        int64(output.y) + int64(output.height) or output.output in outputs:
      fail("policy snapshot output is invalid")
    outputs.incl(output.output)
  if snapshot.activeOutput notin outputs:
    fail("policy snapshot active output is invalid")
  var surfaces = initHashSet[(uint32, uint32)]()
  for surface in snapshot.surfaces:
    let identity = (surface.surfaceIndex, surface.surfaceGeneration)
    if surface.surfaceGeneration == 0 or (
      strictIdentities and
      not validSurface(surface.surfaceIndex, surface.surfaceGeneration)
    ) or surface.stateGeneration == 0 or surface.width <= 0 or surface.height <= 0 or
        identity in surfaces or
        (surface.currentOutput != 0 and surface.currentOutput notin outputs):
      fail("policy snapshot surface is invalid")
    if (surface.minWidth == 0) != (surface.minHeight == 0) or
        (surface.maxWidth == 0) != (surface.maxHeight == 0) or surface.minWidth < 0 or
        surface.minHeight < 0 or surface.maxWidth < 0 or surface.maxHeight < 0 or (
      surface.minWidth > 0 and surface.maxWidth > 0 and
      (surface.minWidth > surface.maxWidth or surface.minHeight > surface.maxHeight)
    ):
      fail("policy surface constraints are invalid")
    if surface.kind < 1 or surface.kind > 5 or
        (surface.requestStateBits and not 7'u16) != 0 or
        (surface.currentStateBits and not 7'u16) != 0 or
        (surface.exactWidth == 0) != (surface.exactHeight == 0) or surface.exactWidth < 0 or
        surface.exactHeight < 0:
      fail("policy surface reduced state is invalid")
    if (surface.currentStateBits and 1) != 0 and (surface.currentStateBits and 2) != 0 or
        (surface.currentStateBits and 4) != 0 and (surface.currentStateBits and 3) != 0:
      fail("policy surface presentation state conflicts")
    surfaces.incl(identity)
  for surface in snapshot.surfaces:
    if strictIdentities and
        not validOptionalSurface(surface.transientIndex, surface.transientGeneration):
      fail("policy transient owner identity is invalid")
    if surface.transientGeneration != 0 and
        (surface.transientIndex, surface.transientGeneration) notin surfaces:
      fail("policy transient owner is invalid")
  for output in snapshot.outputs:
    let invalidFocus =
      if strictIdentities:
        not validOptionalSurface(output.focusIndex, output.focusGeneration)
      else:
        (output.focusIndex == 0) != (output.focusGeneration == 0)
    if invalidFocus:
      fail("policy output focus identity is partial")
    if output.focusGeneration != 0:
      var validFocus = false
      for surface in snapshot.surfaces:
        if surface.surfaceIndex == output.focusIndex and
            surface.surfaceGeneration == output.focusGeneration and
            surface.currentOutput == output.output and
            (surface.capabilityBits and surfaceFocusable) != 0 and
            (surface.currentStateBits and 4) == 0:
          validFocus = true
          break
      if not validFocus:
        fail("policy output focus is invalid")
  var classifiedSurfaces = initHashSet[(uint32, uint32)]()
  for classification in snapshot.classifications:
    let identity = (classification.surfaceIndex, classification.surfaceGeneration)
    if classification.classification == 0 or identity notin surfaces or
        identity in classifiedSurfaces:
      fail("policy surface classification is invalid")
    classifiedSurfaces.incl(identity)
  var actions = initHashSet[uint64]()
  var operationSlots = initHashSet[uint16]()
  for operation in snapshot.sessionOperations:
    if operation.operation == 0 or operation.slot == 0 or
        operation.slot in operationSlots:
      fail("policy session operation is invalid")
    operationSlots.incl(operation.slot)
  var actionNames = initHashSet[string]()
  for action in snapshot.actions:
    if action.action == 0 or action.action in actions or action.name in actionNames or
        action.sessionOperationSlot != 0 and
        action.sessionOperationSlot notin operationSlots:
      fail("policy action is invalid")
    actions.incl(action.action)
    actionNames.incl(action.name)

proc validateSnapshot*(snapshot: PolicySnapshot) =
  # Preserve the characterized legacy direct-validator acceptance.
  snapshot.validateSnapshotFields(false)

proc validateFileSnapshot*(snapshot: PolicySnapshot) =
  snapshot.validateSnapshotFields(true)
  for surface in snapshot.surfaces:
    if (surface.capabilityBits and not snapshotSurfaceCapabilityMask) != 0:
      fail("policy surface capabilities are invalid")
  for operation in snapshot.sessionOperations:
    if (operation.targetBits and not snapshotSessionOperationTargetMask) != 0:
      fail("policy session operation target bits are invalid")

proc applyOutputPolicyKey*(
    outputs: var seq[SnapshotOutput], output, generation, key: uint64
) =
  var found = -1
  for index, item in outputs:
    if key == 0 or item.policyKey == key:
      fail("output policy key is null or repeated")
    if item.output == output and item.generation == generation:
      found = index
  if found < 0 or outputs[found].policyKey != 0:
    fail("output policy key names an unknown or repeated output")
  outputs[found].policyKey = key
