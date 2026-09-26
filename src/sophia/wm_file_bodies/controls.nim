import std/options
import ../../types/[session, wm_file_bodies, wm_files, wm_presentation, wm_v1]
import ../[policy_semantics, wm_file_payload, wm_files]

## Scalar control bodies: Dirty and SessionOperation candidates, the three
## outcome events, presentation receipts and Submitted custody. Delivery of any
## of them is not admission, commit, presentation or retirement.

const h = wmFileHeaderBytes

proc addReserved(body: var seq[byte], count: int) =
  for _ in 0 ..< count:
    body.add(0)

proc projectionOutcome(code: uint16): ProjectionOutcomeKind =
  let kind = projectionOutcomeFromCode(code)
  if kind.isNone:
    failWmFile(WmFileErrorKind.value, "projection outcome is unknown")
  kind.get

proc encodeDirty*(
    header: WmFileHeader, dirty: WmFileDirty, selected: uint64
): seq[byte] =
  requireCapabilities(selected, capabilityPolicyDirty)
  requireNonzero([dirty.policyGeneration])
  var body = newSeqOfCap[byte](wmFileDirtyPrefixBytes + dirty.affectedOutputs.len * 8)
  body.addU64(dirty.policyGeneration)
  if dirty.affectedOutputs.len > maxOutputs:
    failWmFile(WmFileErrorKind.value, "WM file output count is out of range")
  body.addU16(uint16(dirty.affectedOutputs.len))
  body.addReserved(6)
  body.addOutputs(dirty.affectedOutputs)
  header.encodePayload(WmFileKind.dirty, body)

proc decodeDirty*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFileDirty =
  discard bytes.prefixedPayload(WmFileKind.dirty, expectedEpoch, wmFileDirtyPrefixBytes)
  requireCapabilities(selected, capabilityPolicyDirty)
  requireReserved(bytes.toOpenArray(h, bytes.high), 10, 6)
  result.policyGeneration = bytes.readU64(h)
  requireNonzero([result.policyGeneration])
  result.affectedOutputs = readOutputs(
    bytes.toOpenArray(h, bytes.high), wmFileDirtyPrefixBytes, bytes.readU16(h + 8)
  )

proc requireSessionOperation(value: WmFileSessionOperation) =
  requireNonzero([value.transaction, value.intent.requestId, value.intent.operation])
  if not validOptionalSurface(value.intent.targetIndex, value.intent.targetGeneration):
    failWmFile(WmFileErrorKind.value, "session operation target is not a surface")

proc encodeSessionOperation*(
    header: WmFileHeader, value: WmFileSessionOperation, selected: uint64
): seq[byte] =
  requireCapabilities(selected, capabilitySessionOperations)
  value.requireSessionOperation()
  var body = newSeqOfCap[byte](wmFileSessionOperationBytes)
  body.addU64(value.transaction)
  body.addU64(value.intent.requestId)
  body.addU64(value.intent.operation)
  body.addSurface(value.intent.targetIndex, value.intent.targetGeneration)
  header.encodePayload(WmFileKind.sessionOperation, body)

proc decodeSessionOperation*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFileSessionOperation =
  discard bytes.fixedPayload(
    WmFileKind.sessionOperation, expectedEpoch, wmFileSessionOperationBytes
  )
  requireCapabilities(selected, capabilitySessionOperations)
  let target = bytes.toOpenArray(h, bytes.high).readSurface(24)
  result = WmFileSessionOperation(
    transaction: bytes.readU64(h),
    intent: SessionOperationIntent(
      requestId: bytes.readU64(h + 8),
      operation: bytes.readU64(h + 16),
      targetIndex: target.index,
      targetGeneration: target.generation,
    ),
  )
  result.requireSessionOperation()

proc encodeConfigurationOutcome*(
    header: WmFileHeader, value: WmFileConfigurationOutcome, selected: uint64
): seq[byte] =
  requireCapabilities(selected, capabilityConfiguration)
  requireNonzero([value.transaction, value.generation])
  var body = newSeqOfCap[byte](wmFileConfigurationOutcomeBytes)
  body.addU64(value.transaction)
  body.addU64(value.generation)
  body.addU16(uint16(ord(value.kind)))
  body.addReserved(6)
  header.encodePayload(WmFileKind.configurationOutcome, body)

proc decodeConfigurationOutcome*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFileConfigurationOutcome =
  discard bytes.fixedPayload(
    WmFileKind.configurationOutcome, expectedEpoch, wmFileConfigurationOutcomeBytes
  )
  requireCapabilities(selected, capabilityConfiguration)
  requireReserved(bytes.toOpenArray(h, bytes.high), 18, 6)
  result = WmFileConfigurationOutcome(
    transaction: bytes.readU64(h),
    generation: bytes.readU64(h + 8),
    kind: projectionOutcome(bytes.readU16(h + 16)),
  )
  requireNonzero([result.transaction, result.generation])

proc encodeProjectionOutcome*(
    header: WmFileHeader, value: WmFileProjectionOutcome, selected: uint64
): seq[byte] =
  let outcome = value.outcome
  header.requireEpoch(outcome.connectionEpoch)
  requireNonzero([outcome.transaction, outcome.requestId, outcome.sceneGeneration])
  if value.expectSessionOperation:
    requireCapabilities(selected, capabilitySessionOperations)
  var body = newSeqOfCap[byte](wmFileProjectionOutcomeBytes)
  body.addU64(outcome.transaction)
  body.addU64(outcome.requestId)
  body.addU64(outcome.sceneGeneration)
  body.addU16(uint16(ord(outcome.kind)))
  body.addU16(uint16(ord(value.expectSessionOperation)))
  body.addReserved(4)
  header.encodePayload(WmFileKind.projectionOutcome, body)

proc decodeProjectionOutcome*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFileProjectionOutcome =
  let header = bytes.fixedPayload(
    WmFileKind.projectionOutcome, expectedEpoch, wmFileProjectionOutcomeBytes
  )
  requireReserved(bytes.toOpenArray(h, bytes.high), 28, 4)
  let flag = bytes.readU16(h + 26)
  if flag > 1:
    failWmFile(WmFileErrorKind.value, "session-operation expectation is not a flag")
  if flag == 1:
    requireCapabilities(selected, capabilitySessionOperations)
  result = WmFileProjectionOutcome(
    outcome: ProjectionOutcome(
      transaction: bytes.readU64(h),
      connectionEpoch: header.connectionEpoch,
      requestId: bytes.readU64(h + 8),
      sceneGeneration: bytes.readU64(h + 16),
      kind: projectionOutcome(bytes.readU16(h + 24)),
    ),
    expectSessionOperation: flag == 1,
  )
  requireNonzero(
    [
      result.outcome.transaction, result.outcome.requestId,
      result.outcome.sceneGeneration,
    ]
  )

proc encodeSessionOperationOutcome*(
    header: WmFileHeader, value: WmFileSessionOperationOutcome, selected: uint64
): seq[byte] =
  requireCapabilities(selected, capabilitySessionOperations)
  requireNonzero([value.transaction, value.requestId])
  var body = newSeqOfCap[byte](wmFileSessionOperationOutcomeBytes)
  body.addU64(value.transaction)
  body.addU64(value.requestId)
  body.addU16(uint16(ord(value.kind)))
  body.addReserved(6)
  header.encodePayload(WmFileKind.sessionOperationOutcome, body)

proc decodeSessionOperationOutcome*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFileSessionOperationOutcome =
  discard bytes.fixedPayload(
    WmFileKind.sessionOperationOutcome, expectedEpoch,
    wmFileSessionOperationOutcomeBytes,
  )
  requireCapabilities(selected, capabilitySessionOperations)
  requireReserved(bytes.toOpenArray(h, bytes.high), 18, 6)
  result = WmFileSessionOperationOutcome(
    transaction: bytes.readU64(h),
    requestId: bytes.readU64(h + 8),
    kind: projectionOutcome(bytes.readU16(h + 16)),
  )
  requireNonzero([result.transaction, result.requestId])

proc requireReceipt(value: WmFilePresentationReceipt) =
  requireNonzero([value.transaction])
  if not validReceiptIdentity(value.receipt):
    failWmFile(WmFileErrorKind.identity, "presentation receipt identity is null")

proc encodePresentationReceipt*(
    header: WmFileHeader, value: WmFilePresentationReceipt, selected: uint64
): seq[byte] =
  requireCapabilities(selected, capabilitySurfaceInstances)
  header.requireEpoch(value.receipt.connectionEpoch)
  value.requireReceipt()
  let receipt = value.receipt
  var body = newSeqOfCap[byte](wmFilePresentationReceiptBytes)
  for field in [
    value.transaction, receipt.publicationGeneration, receipt.output,
    receipt.outputGeneration, receipt.presentationEpoch,
  ]:
    body.addU64(field)
  body.addU16(uint16(ord(receipt.outcome)))
  body.addReserved(6)
  header.encodePayload(WmFileKind.presentationReceipt, body)

proc decodePresentationReceipt*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFilePresentationReceipt =
  let header = bytes.fixedPayload(
    WmFileKind.presentationReceipt, expectedEpoch, wmFilePresentationReceiptBytes
  )
  requireCapabilities(selected, capabilitySurfaceInstances)
  requireReserved(bytes.toOpenArray(h, bytes.high), 42, 6)
  let outcome = presentationOutcomeFromCode(bytes.readU16(h + 40))
  if outcome.isNone:
    failWmFile(WmFileErrorKind.value, "presentation outcome is unknown")
  result = WmFilePresentationReceipt(
    transaction: bytes.readU64(h),
    receipt: PresentationReceipt(
      connectionEpoch: header.connectionEpoch,
      publicationGeneration: bytes.readU64(h + 8),
      output: bytes.readU64(h + 16),
      outputGeneration: bytes.readU64(h + 24),
      presentationEpoch: bytes.readU64(h + 32),
      outcome: outcome.get,
    ),
  )
  result.requireReceipt()

proc requireSubmitted(value: WmFileSubmitted) =
  requireNonzero([value.acceptedSubmissionId])
  if value.candidateKind.class != WmFileClass.candidateRecord:
    failWmFile(
      WmFileErrorKind.class, "Submitted names a record that is not a candidate"
    )

proc encodeSubmitted*(header: WmFileHeader, value: WmFileSubmitted): seq[byte] =
  value.requireSubmitted()
  var body = newSeqOfCap[byte](wmFileSubmittedBytes)
  body.addU64(value.acceptedSubmissionId)
  body.addU16(uint16(ord(value.candidateKind)))
  body.addReserved(6)
  header.encodePayload(WmFileKind.submitted, body)

proc decodeSubmitted*(bytes: openArray[byte], expectedEpoch: uint64): WmFileSubmitted =
  ## Candidate custody only; it carries no policy outcome.
  discard bytes.fixedPayload(WmFileKind.submitted, expectedEpoch, wmFileSubmittedBytes)
  requireReserved(bytes.toOpenArray(h, bytes.high), 10, 6)
  result = WmFileSubmitted(
    acceptedSubmissionId: bytes.readU64(h),
    candidateKind: fileKind(bytes.readU16(h + 8)),
  )
  result.requireSubmitted()
