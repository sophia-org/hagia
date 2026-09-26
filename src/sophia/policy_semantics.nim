import std/[options, sets]
import ../types/[session, wm_presentation, wm_v1]

## Typed WM protocol semantics shared by every transport Hagia speaks: pure
## predicates and code conversions over passive records, with no bytes, frames
## or files. Each caller raises its own error, so a legacy decoder keeps its
## messages and order. The legacy decoders call a predicate only where it is
## exactly their existing condition; the Focus and Interaction targets they
## refuse at index zero stay their private rule.

proc validSurface*(index, generation: uint32): bool =
  ## A present surface: the all-ones index names none, and generation zero is
  ## never issued.
  index != high(uint32) and generation != 0

proc validOptionalSurface*(index, generation: uint32): bool =
  (index == 0 and generation == 0) or validSurface(index, generation)

proc validActionNameByte*(value: byte): bool =
  value >= byte('a') and value <= byte('z') or value >= byte('A') and value <= byte('Z') or
    value >= byte('0') and value <= byte('9') or
    value in [byte('-'), byte('_'), byte(' '), byte('.')]

proc validInteractionPayload*(
    phase: InteractionPhase,
    kind: InteractionKind,
    axis: InteractionAxis,
    x, y, width, height: int32,
): bool =
  ## Move, resize and drag carry positive geometry and no axis. Scroll names
  ## its axis, reuses x and y as the delta, and leaves width and height zero;
  ## only a cancelled scroll may have no delta.
  case kind
  of InteractionKind.move, InteractionKind.resize, InteractionKind.drag:
    axis == InteractionAxis.none and width > 0 and height > 0
  of InteractionKind.scroll:
    axis != InteractionAxis.none and width == 0 and height == 0 and
      (phase == InteractionPhase.cancel or x != 0 or y != 0)
  of InteractionKind.none:
    false

proc validPresentationIdentity*(identity: PresentationIdentity): bool =
  identity.publicationGeneration != 0 and identity.output != 0 and
    identity.outputGeneration != 0 and identity.presentationEpoch != 0 and
    (identity.targetId == 0) == (identity.targetGeneration == 0)

proc validReceiptIdentity*(receipt: PresentationReceipt): bool =
  ## Identity shape only; the caller compares the connection epoch.
  receipt.publicationGeneration != 0 and receipt.output != 0 and
    receipt.outputGeneration != 0 and receipt.presentationEpoch != 0

proc validAffectedOutputs*(outputs: openArray[uint64]): bool =
  if outputs.len < 1 or outputs.len > maxOutputs:
    return false
  var seen = initHashSet[uint64]()
  for output in outputs:
    if output == 0 or seen.containsOrIncl(output):
      return false
  true

proc projectionOutcomeFromCode*(code: uint16): Option[ProjectionOutcomeKind] =
  case code
  of 1:
    some(ProjectionOutcomeKind.committed)
  of 2:
    some(ProjectionOutcomeKind.rejectedStale)
  of 3:
    some(ProjectionOutcomeKind.rejectedInvalid)
  of 4:
    some(ProjectionOutcomeKind.timedOut)
  of 5:
    some(ProjectionOutcomeKind.disconnected)
  else:
    none(ProjectionOutcomeKind)

proc presentationOutcomeFromCode*(code: uint16): Option[PresentationOutcomeKind] =
  case code
  of 1:
    some(PresentationOutcomeKind.presented)
  of 2:
    some(PresentationOutcomeKind.revoked)
  of 3:
    some(PresentationOutcomeKind.withdrawn)
  else:
    none(PresentationOutcomeKind)

proc profileOutcomeFromCode*(code: uint16): Option[ProfileOutcomeKind] =
  case code
  of 1:
    some(ProfileOutcomeKind.accepted)
  of 2:
    some(ProfileOutcomeKind.rejectedIdentity)
  of 3:
    some(ProfileOutcomeKind.rejectedState)
  else:
    none(ProfileOutcomeKind)
