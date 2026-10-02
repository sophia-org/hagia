## Value conversion at the FFI boundary. The SDK owns every byte layout.
import ../types/desktop_sdk
import ../types/wm_v1
import ./desktop_sdk
import ./policy_transport
proc sdkCheck*(status: cint) =
  if status != 0:
    fail("C WM SDK refused a value: " & $status)

proc encodeRow*(value: WfSnapshotOutput): seq[byte] =
  result = newSeq[byte](56)
  var row = value
  sdkCheck(wfSnapshotOutputEncode(addr result[0], csize_t(result.len), addr row))

proc decodeRow*(section: WfSection, index: int, row: var WfSnapshotOutput) =
  const width = 56
  if index < 0 or uint64(index) >= uint64(section.count) or section.rows == nil or
      uint64(section.bytes) != uint64(section.count) * width:
    fail("invalid SDK snapshot row view")
  sdkCheck(wfSnapshotOutputDecode(addr section.rows[index * width], width, addr row))

proc policyValue*(row: WfSnapshotOutput): SnapshotOutput =
  SnapshotOutput(
    output: row.output,
    generation: row.generation,
    focusIndex: row.focusIndex,
    focusGeneration: row.focusGeneration,
    x: row.x,
    y: row.y,
    width: row.width,
    height: row.height,
    workX: row.workX,
    workY: row.workY,
    workWidth: row.workWidth,
    workHeight: row.workHeight,
  )

proc encodeRow*(value: WfSnapshotSurface): seq[byte] =
  result = newSeq[byte](80)
  var row = value
  sdkCheck(wfSnapshotSurfaceEncode(addr result[0], csize_t(result.len), addr row))

proc decodeRow*(section: WfSection, index: int, row: var WfSnapshotSurface) =
  const width = 80
  if index < 0 or uint64(index) >= uint64(section.count) or section.rows == nil or
      uint64(section.bytes) != uint64(section.count) * width:
    fail("invalid SDK snapshot row view")
  sdkCheck(wfSnapshotSurfaceDecode(addr section.rows[index * width], width, addr row))

proc policyValue*(row: WfSnapshotSurface): SnapshotSurface =
  SnapshotSurface(
    surfaceIndex: row.surfaceIndex,
    surfaceGeneration: row.surfaceGeneration,
    stateGeneration: row.stateGeneration,
    currentOutput: row.currentOutput,
    capabilityBits: row.capabilityBits,
    kind: row.kind,
    requestStateBits: row.requestStateBits,
    currentStateBits: row.currentStateBits,
    transientIndex: row.transientIndex,
    transientGeneration: row.transientGeneration,
    x: row.x,
    y: row.y,
    width: row.width,
    height: row.height,
    minWidth: row.minWidth,
    minHeight: row.minHeight,
    maxWidth: row.maxWidth,
    maxHeight: row.maxHeight,
    exactWidth: row.exactWidth,
    exactHeight: row.exactHeight,
  )

proc encodeRow*(value: WfSnapshotAction): seq[byte] =
  result = newSeq[byte](140)
  var row = value
  sdkCheck(wfSnapshotActionEncode(addr result[0], csize_t(result.len), addr row))

proc decodeRow*(section: WfSection, index: int, row: var WfSnapshotAction) =
  const width = 140
  if index < 0 or uint64(index) >= uint64(section.count) or section.rows == nil or
      uint64(section.bytes) != uint64(section.count) * width:
    fail("invalid SDK snapshot row view")
  sdkCheck(wfSnapshotActionDecode(addr section.rows[index * width], width, addr row))

proc encodeRow*(value: WfSnapshotSessionOperation): seq[byte] =
  result = newSeq[byte](12)
  var row = value
  sdkCheck(
    wfSnapshotSessionOperationEncode(addr result[0], csize_t(result.len), addr row)
  )

proc decodeRow*(section: WfSection, index: int, row: var WfSnapshotSessionOperation) =
  const width = 12
  if index < 0 or uint64(index) >= uint64(section.count) or section.rows == nil or
      uint64(section.bytes) != uint64(section.count) * width:
    fail("invalid SDK snapshot row view")
  sdkCheck(
    wfSnapshotSessionOperationDecode(addr section.rows[index * width], width, addr row)
  )

proc policyValue*(row: WfSnapshotSessionOperation): SnapshotSessionOperation =
  SnapshotSessionOperation(
    operation: row.operation, slot: row.slot, targetBits: row.targetBits
  )

proc encodeRow*(value: WfProjectionOutput): seq[byte] =
  result = newSeq[byte](24)
  var row = value
  sdkCheck(wfProjectionOutputEncode(addr result[0], csize_t(result.len), addr row))

proc sdkValue*(row: ProjectionOutput): WfProjectionOutput =
  WfProjectionOutput(
    output: row.output,
    placementCount: row.placementCount,
    focusIndex: row.focusIndex,
    focusGeneration: row.focusGeneration,
  )

proc encodeRow*(value: WfProjectionPlacement): seq[byte] =
  result = newSeq[byte](60)
  var row = value
  sdkCheck(wfProjectionPlacementEncode(addr result[0], csize_t(result.len), addr row))

proc sdkValue*(row: ProjectionPlacement): WfProjectionPlacement =
  WfProjectionPlacement(
    surfaceIndex: row.surfaceIndex,
    surfaceGeneration: row.surfaceGeneration,
    stateGeneration: row.stateGeneration,
    x: row.x,
    y: row.y,
    width: row.width,
    height: row.height,
    requestedWidth: row.requestedWidth,
    requestedHeight: row.requestedHeight,
    cropX: row.cropX,
    cropY: row.cropY,
    cropWidth: row.cropWidth,
    cropHeight: row.cropHeight,
    transform: row.transform,
    presentationBits: row.presentationBits,
  )

proc encodeRow*(value: WfProjectionIndicator): seq[byte] =
  result = newSeq[byte](64)
  var row = value
  sdkCheck(wfProjectionIndicatorEncode(addr result[0], csize_t(result.len), addr row))

proc sdkValue*(row: ProjectionIndicator): WfProjectionIndicator =
  WfProjectionIndicator(
    output: row.output,
    slot: row.slot,
    indicator: row.indicator,
    action: row.action,
    stateBits: row.stateBits,
    labelLen: row.labelLen,
    label: row.label,
  )

proc encodeRow*(value: WfProjectionOutputStatus): seq[byte] =
  result = newSeq[byte](48)
  var row = value
  sdkCheck(
    wfProjectionOutputStatusEncode(addr result[0], csize_t(result.len), addr row)
  )

proc sdkValue*(row: ProjectionOutputStatus): WfProjectionOutputStatus =
  WfProjectionOutputStatus(
    output: row.output,
    focusBits: row.focusBits,
    layoutLen: row.layoutLen,
    layout: row.layout,
  )

proc encodeRow*(value: WfSnapshotSurfaceClassification): seq[byte] =
  result = newSeq[byte](16)
  var row = value
  sdkCheck(
    wfSnapshotSurfaceClassificationEncode(addr result[0], csize_t(result.len), addr row)
  )

proc decodeRow*(
    section: WfSection, index: int, row: var WfSnapshotSurfaceClassification
) =
  const width = 16
  if index < 0 or uint64(index) >= uint64(section.count) or section.rows == nil or
      uint64(section.bytes) != uint64(section.count) * width:
    fail("invalid SDK snapshot row view")
  sdkCheck(
    wfSnapshotSurfaceClassificationDecode(
      addr section.rows[index * width], width, addr row
    )
  )

proc policyValue*(row: WfSnapshotSurfaceClassification): SnapshotSurfaceClassification =
  SnapshotSurfaceClassification(
    surfaceIndex: row.surfaceIndex,
    surfaceGeneration: row.surfaceGeneration,
    classification: row.classification,
  )

proc encodeRow*(value: WfProjectionLaunchContext): seq[byte] =
  result = newSeq[byte](24)
  var row = value
  sdkCheck(
    wfProjectionLaunchContextEncode(addr result[0], csize_t(result.len), addr row)
  )

proc sdkValue*(row: LaunchOriginRecord): WfProjectionLaunchContext =
  WfProjectionLaunchContext(
    surfaceIndex: row.surfaceIndex,
    surfaceGeneration: row.surfaceGeneration,
    epoch: row.epoch,
    token: row.token,
  )

proc encodeRow*(value: WfProjectionOutputLaunchContext): seq[byte] =
  result = newSeq[byte](32)
  var row = value
  sdkCheck(
    wfProjectionOutputLaunchContextEncode(addr result[0], csize_t(result.len), addr row)
  )

proc sdkValue*(row: OutputLaunchContext): WfProjectionOutputLaunchContext =
  WfProjectionOutputLaunchContext(
    output: row.output, generation: row.generation, epoch: row.epoch, token: row.token
  )

proc encodeRow*(value: WfSnapshotLaunchOrigin): seq[byte] =
  result = newSeq[byte](24)
  var row = value
  sdkCheck(wfSnapshotLaunchOriginEncode(addr result[0], csize_t(result.len), addr row))

proc decodeRow*(section: WfSection, index: int, row: var WfSnapshotLaunchOrigin) =
  const width = 24
  if index < 0 or uint64(index) >= uint64(section.count) or section.rows == nil or
      uint64(section.bytes) != uint64(section.count) * width:
    fail("invalid SDK snapshot row view")
  sdkCheck(
    wfSnapshotLaunchOriginDecode(addr section.rows[index * width], width, addr row)
  )

proc policyValue*(row: WfSnapshotLaunchOrigin): LaunchOriginRecord =
  LaunchOriginRecord(
    surfaceIndex: row.surfaceIndex,
    surfaceGeneration: row.surfaceGeneration,
    epoch: row.epoch,
    token: row.token,
  )

proc encodeRow*(value: WfSnapshotOutputPolicyKey): seq[byte] =
  result = newSeq[byte](24)
  var row = value
  sdkCheck(
    wfSnapshotOutputPolicyKeyEncode(addr result[0], csize_t(result.len), addr row)
  )

proc decodeRow*(section: WfSection, index: int, row: var WfSnapshotOutputPolicyKey) =
  const width = 24
  if index < 0 or uint64(index) >= uint64(section.count) or section.rows == nil or
      uint64(section.bytes) != uint64(section.count) * width:
    fail("invalid SDK snapshot row view")
  sdkCheck(
    wfSnapshotOutputPolicyKeyDecode(addr section.rows[index * width], width, addr row)
  )

proc encodeRow*(value: WfProjectionTabGroup): seq[byte] =
  result = newSeq[byte](48)
  var row = value
  sdkCheck(wfProjectionTabGroupEncode(addr result[0], csize_t(result.len), addr row))

proc encodeRow*(value: WfProjectionTabMember): seq[byte] =
  result = newSeq[byte](24)
  var row = value
  sdkCheck(wfProjectionTabMemberEncode(addr result[0], csize_t(result.len), addr row))

proc encodeRow*(value: WfProjectionTranslationGroup): seq[byte] =
  result = newSeq[byte](32)
  var row = value
  sdkCheck(
    wfProjectionTranslationGroupEncode(addr result[0], csize_t(result.len), addr row)
  )

proc encodeRow*(value: WfProjectionTranslationMember): seq[byte] =
  result = newSeq[byte](24)
  var row = value
  sdkCheck(
    wfProjectionTranslationMemberEncode(addr result[0], csize_t(result.len), addr row)
  )

proc encodeRow*(value: WfProjectionPresentation): seq[byte] =
  result = newSeq[byte](32)
  var row = value
  sdkCheck(
    wfProjectionPresentationEncode(addr result[0], csize_t(result.len), addr row)
  )

proc encodeRow*(value: WfProjectionPresentationOutput): seq[byte] =
  result = newSeq[byte](40)
  var row = value
  sdkCheck(
    wfProjectionPresentationOutputEncode(addr result[0], csize_t(result.len), addr row)
  )

proc encodeRow*(value: WfProjectionSurfaceInstance): seq[byte] =
  result = newSeq[byte](80)
  var row = value
  sdkCheck(
    wfProjectionSurfaceInstanceEncode(addr result[0], csize_t(result.len), addr row)
  )

proc encodeRow*(value: WfProjectionPresentationRegion): seq[byte] =
  result = newSeq[byte](72)
  var row = value
  sdkCheck(
    wfProjectionPresentationRegionEncode(addr result[0], csize_t(result.len), addr row)
  )

proc encodeRow*(value: WfConfigurationActionLifecycle): seq[byte] =
  result = newSeq[byte](16)
  var row = value
  sdkCheck(
    wfConfigurationActionLifecycleEncode(addr result[0], csize_t(result.len), addr row)
  )

proc encodeRow*(value: WfProjectionPresentationBinding): seq[byte] =
  result = newSeq[byte](16)
  var row = value
  sdkCheck(
    wfProjectionPresentationBindingEncode(addr result[0], csize_t(result.len), addr row)
  )

proc policyValue*(row: WfSnapshotAction): SnapshotAction =
  if row.nameLen == 0 or row.nameLen > 128:
    fail("invalid SDK action name length")
  result.action = row.action
  result.sessionOperationSlot = row.sessionOperationSlot
  result.name = newString(int(row.nameLen))
  for i in 0 ..< result.name.len:
    result.name[i] = char(row.name[i])

proc sdkValue*(row: SnapshotAction): WfSnapshotAction =
  if row.name.len == 0 or row.name.len > 128:
    fail("invalid policy action name length")
  result.action = row.action
  result.sessionOperationSlot = row.sessionOperationSlot
  result.nameLen = uint16(row.name.len)
  for i, c in row.name:
    result.name[i] = byte(c)
