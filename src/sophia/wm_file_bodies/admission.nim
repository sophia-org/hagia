import std/options
import ../../types/[handoff, wm_file_bodies, wm_files, wm_v1]
import ../[policy_semantics, wm_file_payload, wm_files]

## Admission bodies: the published Limits object, the WM's Negotiate offer,
## Sophia's Negotiated selection, and the profile handoff commands and
## completions. These carry values only. Selection, refusal and the handoff
## phase belong to their existing owners; the caller names the exact kind.

const h = wmFileHeaderBytes

proc encodeLimits*(header: WmFileHeader, limits: WmFileLimits): seq[byte] =
  if limits.profileRequired:
    requireCapabilities(limits.capabilityCeiling, capabilityProfileActivation)
  var body = newSeqOfCap[byte](wmFileLimitsBytes)
  body.addU64(limits.capabilityCeiling)
  body.addU32(uint32(wmFileMaxBytes))
  body.addU32(uint32(wmFileMaxBytes))
  body.addU16(wmFileMaxJournalRecords)
  body.addU16(uint16(wmFileMaxSections))
  body.addU32(wmFileAssemblyTimeoutMillis)
  body.addU32(wmFileSendTimeoutMillis)
  body.addU16(uint16(ord(limits.profileRequired)))
  body.addU16(0)
  header.encodePayload(WmFileKind.limits, body)

proc decodeLimits*(bytes: openArray[byte], expectedEpoch: uint64): WmFileLimits =
  ## API 1 publishes fixed custody bounds, so a Limits object that promises
  ## any other value is refused rather than believed.
  discard bytes.fixedPayload(WmFileKind.limits, expectedEpoch, wmFileLimitsBytes)
  requireReserved(bytes.toOpenArray(h, bytes.high), 30, 2)
  let profileRequired = bytes.readU16(h + 28)
  if bytes.readU32(h + 8) != uint32(wmFileMaxBytes) or
      bytes.readU32(h + 12) != uint32(wmFileMaxBytes) or
      bytes.readU16(h + 16) != wmFileMaxJournalRecords or
      bytes.readU16(h + 18) != uint16(wmFileMaxSections) or
      bytes.readU32(h + 20) != wmFileAssemblyTimeoutMillis or
      bytes.readU32(h + 24) != wmFileSendTimeoutMillis or profileRequired > 1:
    failWmFile(WmFileErrorKind.value, "WM file limits differ from API 1")
  result = WmFileLimits(
    capabilityCeiling: bytes.readU64(h), profileRequired: profileRequired == 1
  )
  if result.profileRequired:
    requireCapabilities(result.capabilityCeiling, capabilityProfileActivation)

proc requireDisjoint(offer: WmFileNegotiationOffer) =
  if (offer.required and offer.optional) != 0:
    failWmFile(WmFileErrorKind.value, "a capability is both required and optional")

proc encodeNegotiate*(header: WmFileHeader, offer: WmFileNegotiationOffer): seq[byte] =
  ## Unknown bits are the admission owner's to refuse or ignore.
  offer.requireDisjoint()
  var body = newSeqOfCap[byte](wmFileNegotiateBytes)
  body.addU64(offer.required)
  body.addU64(offer.optional)
  header.encodePayload(WmFileKind.negotiate, body)

proc decodeNegotiate*(
    bytes: openArray[byte], expectedEpoch: uint64
): WmFileNegotiationOffer =
  discard bytes.fixedPayload(WmFileKind.negotiate, expectedEpoch, wmFileNegotiateBytes)
  result =
    WmFileNegotiationOffer(required: bytes.readU64(h), optional: bytes.readU64(h + 8))
  result.requireDisjoint()

proc encodeNegotiated*(header: WmFileHeader, selected: uint64): seq[byte] =
  var body = newSeqOfCap[byte](wmFileNegotiatedBytes)
  body.addU64(selected)
  header.encodePayload(WmFileKind.negotiated, body)

proc decodeNegotiated*(bytes: openArray[byte], expectedEpoch: uint64): uint64 =
  discard
    bytes.fixedPayload(WmFileKind.negotiated, expectedEpoch, wmFileNegotiatedBytes)
  bytes.readU64(h)

proc commandFileKind*(kind: ProfileHandoffMsgKind): WmFileKind =
  case kind
  of ProfileHandoffMsgKind.prepare: WmFileKind.profilePrepare
  of ProfileHandoffMsgKind.activate: WmFileKind.profileActivate
  of ProfileHandoffMsgKind.rollback: WmFileKind.profileRollback

proc completionFileKind*(kind: ProfileHandoffMsgKind): WmFileKind =
  case kind
  of ProfileHandoffMsgKind.prepare: WmFileKind.profilePrepared
  of ProfileHandoffMsgKind.activate: WmFileKind.profileActive
  of ProfileHandoffMsgKind.rollback: WmFileKind.profileRolledBack

proc handoffKind(kind: WmFileKind, completion: bool): ProfileHandoffMsgKind =
  for candidate in ProfileHandoffMsgKind:
    let named =
      if completion: candidate.completionFileKind else: candidate.commandFileKind
    if named == kind:
      return candidate
  failWmFile(WmFileErrorKind.kind, "WM file record is not a profile stage")

proc requireIdentity(transaction: uint64, identity: ProfileIdentity) =
  requireNonzero([transaction, identity.profileGeneration])
  if identity.profileDigest == default(array[profileDigestLen, byte]):
    failWmFile(WmFileErrorKind.identity, "profile digest is null")

proc addProfile(body: var seq[byte], transaction: uint64, identity: ProfileIdentity) =
  body.addU64(transaction)
  body.addU64(identity.profileGeneration)
  body.add(identity.profileDigest)

proc readProfile(
    bytes: openArray[byte], epoch: uint64
): tuple[transaction: uint64, identity: ProfileIdentity] =
  result.transaction = bytes.readU64(h)
  result.identity.connectionEpoch = epoch
  result.identity.profileGeneration = bytes.readU64(h + 8)
  for index in 0 ..< profileDigestLen:
    result.identity.profileDigest[index] = bytes[h + 16 + index]
  requireIdentity(result.transaction, result.identity)

proc encodeProfileCommand*(
    header: WmFileHeader, command: ProfileCommand, selected: uint64
): seq[byte] =
  discard handoffKind(header.kind, completion = false)
  requireCapabilities(selected, capabilityProfileActivation)
  header.requireEpoch(command.identity.connectionEpoch)
  requireIdentity(command.transaction, command.identity)
  var body = newSeqOfCap[byte](wmFileProfileCommandBytes)
  body.addProfile(command.transaction, command.identity)
  header.encodePayload(header.kind, body)

proc decodeProfileCommand*(
    bytes: openArray[byte],
    expected: ProfileHandoffMsgKind,
    expectedEpoch, selected: uint64,
): ProfileCommand =
  let header = bytes.fixedPayload(
    expected.commandFileKind, expectedEpoch, wmFileProfileCommandBytes
  )
  requireCapabilities(selected, capabilityProfileActivation)
  let (transaction, identity) = bytes.readProfile(header.connectionEpoch)
  ProfileCommand(transaction: transaction, identity: identity)

proc encodeProfileCompletion*(
    header: WmFileHeader, completion: ProfileCompletion, selected: uint64
): seq[byte] =
  discard handoffKind(header.kind, completion = true)
  requireCapabilities(selected, capabilityProfileActivation)
  header.requireEpoch(completion.identity.connectionEpoch)
  requireIdentity(completion.transaction, completion.identity)
  var body = newSeqOfCap[byte](wmFileProfileCompletionBytes)
  body.addProfile(completion.transaction, completion.identity)
  body.addU16(uint16(ord(completion.outcome)))
  for _ in 0 ..< 6:
    body.add(0)
  header.encodePayload(header.kind, body)

proc decodeProfileCompletion*(
    bytes: openArray[byte],
    expected: ProfileHandoffMsgKind,
    expectedEpoch, selected: uint64,
): ProfileCompletion =
  let header = bytes.fixedPayload(
    expected.completionFileKind, expectedEpoch, wmFileProfileCompletionBytes
  )
  requireCapabilities(selected, capabilityProfileActivation)
  requireReserved(bytes.toOpenArray(h, bytes.high), 50, 6)
  let (transaction, identity) = bytes.readProfile(header.connectionEpoch)
  let outcome = profileOutcomeFromCode(bytes.readU16(h + 48))
  if outcome.isNone:
    failWmFile(WmFileErrorKind.value, "profile outcome is unknown")
  ProfileCompletion(transaction: transaction, identity: identity, outcome: outcome.get)
