import std/[options, os, strutils, tempfiles, unittest]

import types/[config_values, handoff, session, wm_presentation, wm_v1]
import sophia/[policy_loop, policy_transport, policy_wire]

## The policy loop over a fake wire: where the loop checks, settles, sends and
## closes, independent of any wire's bytes.

type FakeWire = ref object
  log: seq[string]
  profile: seq[Option[ProfileHandoffMsg]]
  expected: seq[set[ProfileHandoffMsgKind]]
  snapshots: seq[PolicySnapshot]
  requests: seq[ProjectionRequest]
  completions: seq[ProjectionCompletion]
  operationOutcome: ProjectionOutcomeKind
  receipts: seq[PresentationReceipt] ## returned by every takeReceipts
  corruptIdentity: bool ## the outcome names another request
  nextTransaction: uint64
  closes: int

proc wire(fake: FakeWire, capabilities = capabilitySessionOperations): PolicyWire =
  proc receiveProfileCommand(
      expected: set[ProfileHandoffMsgKind]
  ): Option[ProfileHandoffMsg] =
    fake.log.add("profile")
    fake.expected.add(expected)
    if fake.profile.len == 0:
      fail("fake wire has no profile command")
    result = fake.profile[0]
    fake.profile.delete(0)

  proc completeProfile(kind: ProfileHandoffMsgKind, completion: ProfileCompletion) =
    fake.log.add("complete " & $kind)

  proc enterPolicyTraffic() =
    fake.log.add("enter")

  proc allocate(): uint64 =
    fake.log.add("allocate")
    inc fake.nextTransaction
    fake.nextTransaction

  proc install(configuration: PolicyConfiguration): PolicyConfigurationOutcome =
    fake.log.add("configure")
    PolicyConfigurationOutcome(
      transaction: configuration.transaction,
      connectionEpoch: configuration.connectionEpoch,
      generation: configuration.generation,
      kind: ProjectionOutcomeKind.committed,
    )

  proc snapshot(): PolicySnapshot =
    fake.log.add("snapshot")
    if fake.snapshots.len == 0:
      fail("fake wire has no snapshot")
    result = fake.snapshots[0]
    fake.snapshots.delete(0)

  proc request(): ProjectionRequest =
    fake.log.add("request")
    result = fake.requests[0]
    fake.requests.delete(0)

  proc project(
      request: ProjectionRequest, transaction: uint64, projection: PolicyProjection
  ): ProjectionCompletion =
    fake.log.add("project")
    result = fake.completions[0]
    result.outcome.transaction = transaction
    result.outcome.connectionEpoch = request.connectionEpoch
    result.outcome.requestId = request.requestId + ord(fake.corruptIdentity).uint64
    result.outcome.sceneGeneration = request.sceneGeneration + 1
    fake.completions.delete(0)

  proc operate(intent: SessionOperationIntent): ProjectionOutcomeKind =
    fake.log.add("operate")
    fake.operationOutcome

  proc dirty(value: PolicyDirty) =
    fake.log.add("dirty")

  proc receipts(): seq[PresentationReceipt] =
    fake.log.add("receipts")
    fake.receipts

  proc close() =
    fake.log.add("close")
    inc fake.closes

  PolicyWire(
    connectionEpoch: 9,
    capabilities: capabilities,
    receiveProfileCommand: receiveProfileCommand,
    completeProfile: completeProfile,
    enterPolicyTraffic: enterPolicyTraffic,
    allocateTransaction: allocate,
    installConfiguration: install,
    receiveSnapshot: snapshot,
    receiveRequest: request,
    submitProjection: project,
    submitSessionOperation: operate,
    requestDirty: dirty,
    takeReceipts: receipts,
    close: close,
  )

proc scene(generation: uint64): PolicySnapshot =
  ## One output with a focused surface and the close-window session operation.
  let output = SnapshotOutput(
    output: 10,
    generation: 1,
    focusIndex: 1,
    focusGeneration: 1,
    width: 900,
    height: 600,
  )
  PolicySnapshot(
    generation: generation,
    activeOutput: 10,
    outputs: @[output],
    surfaces: @[
      SnapshotSurface(
        surfaceIndex: 1,
        surfaceGeneration: 1,
        stateGeneration: 1,
        currentOutput: 10,
        capabilityBits: 31,
        width: 400,
        height: 300,
      )
    ],
    actions:
      @[SnapshotAction(action: 31, name: "close-window", sessionOperationSlot: 3)],
    sessionOperations:
      @[SnapshotSessionOperation(operation: 700, slot: 3, targetBits: 1)],
  )

proc request(requestId, generation: uint64, operation: bool): ProjectionRequest =
  ProjectionRequest(
    connectionEpoch: 9,
    requestId: requestId,
    sceneGeneration: generation,
    policyGeneration: 1,
    affectedOutputs: @[10'u64],
    cause:
      if operation:
        ProjectionCause(
          kind: ProjectionCauseKind.action, activationSerial: 19, action: 31
        )
      else:
        ProjectionCause(kind: ProjectionCauseKind.sceneChanged),
  )

proc completion(
    kind: ProjectionOutcomeKind, expectation: Option[bool]
): ProjectionCompletion =
  ProjectionCompletion(
    outcome: ProjectionOutcome(kind: kind), expectSessionOperation: expectation
  )

proc oneCycle(
    operation: bool, kind: ProjectionOutcomeKind, expectation: Option[bool]
): FakeWire =
  FakeWire(
    snapshots: @[scene(1)],
    requests: @[request(11, 1, operation)],
    completions: @[completion(kind, expectation)],
    operationOutcome: ProjectionOutcomeKind.disconnected,
  )

proc raisedMessage(body: proc()): string =
  try:
    body()
  except CatchableError as error:
    return error.msg
  "no error"

proc withCheckpoint(body: proc(path: string)) =
  let directory = createTempDir("hagia-wire-", "")
  let path = directory / "policy.checkpoint"
  putEnv("HAGIA_POLICY_CHECKPOINT", path)
  try:
    body(path)
  finally:
    delEnv("HAGIA_POLICY_CHECKPOINT")
    if fileExists(path):
      removeFile(path)
    removeDir(directory)

proc profileCandidate(): AuthorityCandidate =
  AuthorityCandidate(
    authority: ProfileAuthority.policy,
    generation: 1,
    digest: repeat("5a", profileDigestLen),
  )

proc prepareCommand(): ProfileHandoffMsg =
  var identity = ProfileIdentity(connectionEpoch: 9, profileGeneration: 1)
  for index in 0 ..< profileDigestLen:
    identity.profileDigest[index] = 0x5a
  ProfileHandoffMsg(
    kind: ProfileHandoffMsgKind.prepare,
    command: ProfileCommand(transaction: 1, identity: identity),
  )

const disagreement =
  "Sophia's session-operation expectation disagrees with the projection"

suite "Hagia policy loop over a typed wire":
  test "a disagreeing expectation fails before settlement, checkpoint or operation":
    for (operation, kind, expectation) in [
      (true, ProjectionOutcomeKind.committed, some(false)),
      (false, ProjectionOutcomeKind.committed, some(true)),
      (true, ProjectionOutcomeKind.rejectedStale, some(true)),
      (false, ProjectionOutcomeKind.timedOut, some(true)),
    ]:
      withCheckpoint(
        proc(path: string) =
          let fake = oneCycle(operation, kind, expectation)
          check raisedMessage(
            proc() =
              fake.wire().runPolicySession(false)
          ) == disagreement
          check not fileExists(path)
          check "operate" notin fake.log
          check "dirty" notin fake.log
          check fake.log[^1] == "close"
          check fake.closes == 1
      )

  test "the expectation is refused before settlement judges the outcome identity":
    # With an agreeing expectation the corrupt identity reaches settlement and
    # is refused there; with a disagreeing one the expectation is refused
    # first, so settlement never sees the outcome.
    for (expectation, message) in [
      (some(true), "policy outcome identity is invalid"), (some(false), disagreement)
    ]:
      withCheckpoint(
        proc(path: string) =
          let fake = oneCycle(true, ProjectionOutcomeKind.committed, expectation)
          fake.corruptIdentity = true
          check raisedMessage(
            proc() =
              fake.wire().runPolicySession(false)
          ) == message
          check not fileExists(path)
          check "operate" notin fake.log
          check fake.closes == 1
      )

  test "an agreeing or absent expectation settles and sends the operation":
    for expectation in [none(bool), some(true)]:
      withCheckpoint(
        proc(path: string) =
          let fake = oneCycle(true, ProjectionOutcomeKind.committed, expectation)
          fake.wire().runPolicySession(false)
          check fileExists(path)
          check fake.log ==
            @[
              "snapshot", "request", "allocate", "receipts", "project", "operate",
              "close",
            ]
          check fake.closes == 1
      )

  test "an absent expectation, as the legacy wire reports, is never checked":
    let ended = oneCycle(false, ProjectionOutcomeKind.disconnected, none(bool))
    ended.wire().runPolicySession(false)
    check "operate" notin ended.log
    check ended.closes == 1

    # A rejected projection settles and the session waits for the next cycle,
    # which this fake does not have.
    let rejected = oneCycle(true, ProjectionOutcomeKind.rejectedStale, none(bool))
    check raisedMessage(
      proc() =
        rejected.wire().runPolicySession(false)
    ) == "fake wire has no snapshot"
    check rejected.log[4 .. ^1] == @["project", "snapshot", "close"]
    check rejected.closes == 1

  test "a rejected projection with a false expectation settles without an operation":
    let fake = oneCycle(true, ProjectionOutcomeKind.disconnected, some(false))
    fake.wire().runPolicySession(false)
    check "operate" notin fake.log
    check fake.closes == 1

  test "each profile phase refuses another command in its own words":
    let early = FakeWire(profile: @[none(ProfileHandoffMsg)])
    check raisedMessage(
      proc() =
        discard early.wire().activateProfileCandidate(profileCandidate())
    ) == "desktop profile command is out of phase"
    check early.expected == @[{ProfileHandoffMsgKind.prepare}]
    check early.log == @["profile"]

    let late = FakeWire(profile: @[some(prepareCommand()), none(ProfileHandoffMsg)])
    check raisedMessage(
      proc() =
        discard late.wire().activateProfileCandidate(profileCandidate())
    ) == "normal policy traffic preceded desktop profile activation"
    check late.expected ==
      @[
        {ProfileHandoffMsgKind.prepare},
        {ProfileHandoffMsgKind.activate, ProfileHandoffMsgKind.rollback},
      ]
    check late.log == @["profile", "complete prepare", "profile"]

  test "receipts are taken and applied before each preparation":
    # The session refuses a receipt while a projection is pending, so applying
    # this one anywhere after preparation would fail the run.
    let fake = FakeWire(
      receipts: @[
        PresentationReceipt(
          connectionEpoch: 9,
          publicationGeneration: 1,
          output: 10,
          outputGeneration: 1,
          presentationEpoch: 1,
          outcome: PresentationOutcomeKind.presented,
        )
      ],
      snapshots: @[scene(1), scene(2)],
      requests: @[request(11, 1, false), request(12, 2, false)],
      completions: @[
        completion(ProjectionOutcomeKind.committed, none(bool)),
        completion(ProjectionOutcomeKind.committed, none(bool)),
      ],
    )
    fake.wire().runPolicyCycles(2)
    check fake.log ==
      @[
        "snapshot", "request", "allocate", "receipts", "project", "snapshot", "request",
        "allocate", "receipts", "project", "close",
      ]

  test "a wire cycle count outside one to sixteen is refused and closes the wire":
    for count in [0, 17]:
      let fake = FakeWire()
      check raisedMessage(
        proc() =
          fake.wire().runPolicyCycles(count)
      ) == "policy proof cycle count is invalid"
      check fake.log == @["close"]

  test "a raised wire operation still closes the wire":
    let session = FakeWire()
    check raisedMessage(
      proc() =
        session.wire().runPolicySession(false)
    ) == "fake wire has no snapshot"
    check session.log == @["snapshot", "close"]

    let cycles = oneCycle(false, ProjectionOutcomeKind.committed, none(bool))
    check raisedMessage(
      proc() =
        cycles.wire().runPolicyCycles(2)
    ) == "fake wire has no snapshot"
    check cycles.log[^2 .. ^1] == @["snapshot", "close"]
    check cycles.closes == 1
