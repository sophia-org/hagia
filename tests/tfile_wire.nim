import std/[net, unittest]
import types/wm_v1
import sophia/[policy_transport, wm_file_wire]
import support/sdk_admission_peer

## Hagia-specific admission against the pinned SDK's scripted peer.
## SDK transport/custody controls and the real Sophia export gate are separate;
## docs/sdk-test-migration.md maps the retired direct-client assertions.
const
  everyBit = (1'u64 shl 20) - 1
  required =
    capabilityBindings or capabilityActions or capabilityMultiOutput or
    capabilityPointerInteractions or capabilityIndicators or capabilityLaunchPlacement or
    capabilityChrome or capabilityPolicyDirty or capabilityConfiguration or
    capabilitySessionOperations
  extras =
    capabilityTabGroups or capabilityTranslationGroups or capabilityOutputActions or
    capabilityOutputPolicyKeys or capabilityLaunchOrigin or capabilityOutputLaunchContext or
    capabilitySurfaceInstances or capabilityPresentationActions

suite "Hagia SDK file admission":
  test "admission offers exactly the implemented vocabulary and adopts selection":
    let log = runPeer(
      everyBit,
      required or extras,
      proc(socket: Socket) =
        let wire = socket.fileWire()
        check wire.connectionEpoch == 41
        check wire.capabilities == (required or extras)
        wire.close(),
    )
    check log.status == 0
    check log.offers == 1
    check log.required == required
    check log.optional == extras

  test "requested focus activation and assignments become required":
    let wanted =
      required or capabilityPointerFocus or capabilityProfileActivation or
      capabilityOutputActions or capabilityOutputPolicyKeys
    let log = runPeer(
      everyBit,
      wanted or extras,
      proc(socket: Socket) =
        socket.fileWire(true, true, true).close(),
      profileRequired = true,
    )
    check log.status == 0
    check log.offers == 1
    check log.required == wanted
    check log.optional == (extras and not wanted)

  test "selection outside the offer or ceiling refuses and closes":
    for ceiling in [everyBit, everyBit and not capabilityTabGroups]:
      let selected =
        if ceiling == everyBit:
          everyBit
        else:
          required or extras
      let log = runPeer(
        ceiling,
        selected,
        proc(socket: Socket) =
          expect PolicyClientError:
            discard socket.fileWire()
        ,
      )
      check log.status == 0
      check log.configurations == 0

  test "insufficient ceiling and required profile refuse before any candidate":
    for profile in [false, true]:
      let ceiling =
        if profile:
          everyBit
        else:
          everyBit and not capabilityConfiguration
      let log = runPeer(
        ceiling,
        required or extras,
        proc(socket: Socket) =
          expect PolicyClientError:
            discard socket.fileWire()
        ,
        profileRequired = profile,
      )
      check log.status == 0
      check log.offers == 0
      check log.configurations == 0
