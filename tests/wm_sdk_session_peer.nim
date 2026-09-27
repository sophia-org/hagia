## Runs Hagia's actual C SDK PolicyWire callbacks against a supplied Session
## export. Configuration, projection and outcomes are fixture values. This
## proves adapter interoperability, not WM policy or authenticated launch.
import std/monotimes
import std/net
import std/options
import std/os
import std/strutils
import std/times
import types/config_values
import types/handoff
import types/session
import types/wm_presentation
import types/wm_v1
import sophia/profile_handoff
import sophia/policy_wire
import sophia/wm_file_wire

proc require(value: bool, message: string) =
  if not value:
    raise newException(IOError, message)

proc startup(wire: PolicyWire) =
  require(wire.connectionEpoch == 9, "wrong supplied epoch")
  var model = AuthorityCandidate(
    authority: ProfileAuthority.policy, generation: 3, digest: repeat("07", 32)
  ).initProfileHandoff(wire.connectionEpoch)
  for stage in [ProfileHandoffMsgKind.prepare, ProfileHandoffMsgKind.activate]:
    let msg = wire.receiveProfileCommand({stage})
    require(msg.isSome, "missing profile command")
    require(
      msg.get.command.transaction ==
        (if stage == ProfileHandoffMsgKind.prepare: 40'u64 else: 41'u64),
      "profile transaction",
    )
    let update = model.reduceProfileHandoff(msg.get)
    require(update.completion.outcome == ProfileOutcomeKind.accepted, "profile refused")
    model = update.model
    wire.completeProfile(stage, update.completion)
  require(model.phase == ProfileHandoffPhase.active, "profile not active")
  wire.enterPolicyTraffic()

proc cycle(wire: PolicyWire) =
  let config = PolicyConfiguration(transaction: 10, connectionEpoch: 9, generation: 3)
  let installed = wire.installConfiguration(config)
  installed.requireConfigurationOutcome(config)
  let scene = wire.receiveSnapshot()
  let request = wire.receiveRequest()
  require(
    scene.generation == 7 and scene.activeOutput == 1 and scene.outputs.len == 1 and
      scene.surfaces.len == 1,
    "snapshot shape",
  )
  require(
    request.connectionEpoch == 9 and request.requestId == 55 and
      request.sceneGeneration == 7 and request.policyGeneration == 3 and
      request.affectedOutputs == @[1'u64],
    "cycle identity",
  )
  let output = scene.outputs[0]
  let surface = scene.surfaces[0]
  require(
    output.output == 1 and output.generation == 3 and output.policyKey == 22,
    "output identity",
  )
  require(
    surface.surfaceIndex == 3 and surface.surfaceGeneration == 1 and
      surface.stateGeneration == 8,
    "surface identity",
  )
  let projection = PolicyProjection(
    activeOutput: output.output,
    outputs: @[
      PolicyOutputProjection(
        output: ProjectionOutput(
          output: output.output,
          placementCount: 1,
          focusIndex: surface.surfaceIndex,
          focusGeneration: surface.surfaceGeneration,
        ),
        placements: @[
          ProjectionPlacement(
            surfaceIndex: surface.surfaceIndex,
            surfaceGeneration: surface.surfaceGeneration,
            stateGeneration: surface.stateGeneration,
            x: surface.x,
            y: surface.y,
            width: surface.width,
            height: surface.height,
            transform: 1,
          )
        ],
      )
    ],
  )
  require(wire.allocateTransaction() == 11, "projection transaction")
  let completed = wire.submitProjection(request, 11, projection)
  require(
    completed.outcome.transaction == 11 and completed.outcome.requestId == 55 and
      completed.outcome.sceneGeneration == 7 and
      completed.outcome.kind == ProjectionOutcomeKind.committed and
      completed.expectSessionOperation == some(true),
    "projection outcome",
  )
  require(
    wire.submitSessionOperation(SessionOperationIntent(requestId: 55, operation: 1)) ==
      ProjectionOutcomeKind.committed,
    "operation outcome",
  )
  let deadline = getMonoTime() + initDuration(seconds = 3)
  var receipts: seq[PresentationReceipt]
  while receipts.len == 0:
    receipts = wire.takeReceipts()
    require(getMonoTime() < deadline, "receipt deadline")
    if receipts.len == 0:
      sleep(1)
  require(receipts.len == 1, "receipt count")
  let receipt = receipts[0]
  require(
    receipt.connectionEpoch == 9 and receipt.publicationGeneration == 1 and
      receipt.output == 1 and receipt.outputGeneration == 3 and
      receipt.presentationEpoch == 1 and
      receipt.outcome == PresentationOutcomeKind.presented,
    "receipt identity",
  )

if paramCount() != 2 or paramStr(2) notin ["startup", "cycle"]:
  quit("usage: wm_sdk_session_peer SOCKET_PATH startup|cycle", 2)
try:
  let socket = newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP)
  socket.connectUnix(paramStr(1))
  let wire = fileWire(
    socket,
    requestProfileActivation = true,
    requestPointerFocus = true,
    requestOutputAssignments = true,
  )
  try:
    wire.startup()
    if paramStr(2) == "cycle":
      wire.cycle()
    echo "hagia_sdk_adapter status=pass case=" & paramStr(2) &
      " supplied_admission=true scripted_outcomes=true native_presentation=false"
  finally:
    wire.close()
except CatchableError as error:
  quit("hagia_sdk_adapter status=failed reason=" & error.msg, 1)
