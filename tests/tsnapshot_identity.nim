import std/unittest

import types/[session, wm_v1]
import sophia/[policy_codec, policy_transport]
from sophia/policy_snapshot import validateFileSnapshot

proc snapshot(index: uint32): PolicySnapshot =
  PolicySnapshot(
    generation: 1,
    activeOutput: 7,
    outputs: @[
      SnapshotOutput(
        output: 7,
        generation: 1,
        width: 640,
        height: 480,
        workWidth: 640,
        workHeight: 480,
      )
    ],
    surfaces: @[
      SnapshotSurface(
        surfaceIndex: index,
        surfaceGeneration: 1,
        stateGeneration: 1,
        currentOutput: 7,
        capabilityBits: surfaceFocusable,
        kind: 1,
        width: 320,
        height: 240,
      )
    ],
  )

suite "legacy snapshot identity characterization":
  # These pin the direct validator, not runtime admission or file semantics.
  test "legacy permits index zero as a surface but refuses it as focus":
    var value = snapshot(0)
    value.validateSnapshot()
    value.outputs[0].focusIndex = 0
    value.outputs[0].focusGeneration = 1
    expect PolicyClientError:
      value.validateSnapshot()

  test "legacy direct validator does not reject the all-ones surface index":
    snapshot(high(uint32)).validateSnapshot()

  test "legacy ignores a transient index when its generation is zero":
    var value = snapshot(1)
    value.surfaces[0].transientIndex = 9
    value.surfaces[0].transientGeneration = 0
    value.validateSnapshot()

suite "strict snapshot identities":
  test "index zero can be focused when the live surface is eligible":
    var value = snapshot(0)
    value.outputs[0].focusGeneration = 1
    value.validateFileSnapshot()
    value.surfaces[0].capabilityBits = 0
    expect PolicyClientError:
      value.validateFileSnapshot()

  test "the all-ones surface index is refused":
    expect PolicyClientError:
      snapshot(high(uint32)).validateFileSnapshot()

  test "an absent transient is exactly zero zero":
    var value = snapshot(1)
    value.surfaces[0].transientIndex = 9
    expect PolicyClientError:
      value.validateFileSnapshot()
