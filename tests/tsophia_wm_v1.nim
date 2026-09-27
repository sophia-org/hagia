import ./support/wire/sophia/wm_translation
import ./support/wire/sophia/wm_tab_groups
import ./support/wire/sophia/presentation_oracle
import types/wm_presentation
import types/core
import types/session
import std/os
import std/strutils
import std/unittest

import ./support/wire/sophia/wm_v1
import types/wm_v1 as wmTypes

proc hexNibble(character: char): int =
  case character
  of '0' .. '9':
    ord(character) - ord('0')
  of 'a' .. 'f':
    ord(character) - ord('a') + 10
  else:
    -1

proc decodeHex(text: string): seq[byte] =
  if text.len mod 2 != 0:
    raise newException(ValueError, "odd hexadecimal input")
  result = newSeq[byte](text.len div 2)
  for index in 0 ..< result.len:
    let high = text[index * 2].hexNibble()
    let low = text[index * 2 + 1].hexNibble()
    if high < 0 or low < 0:
      raise newException(ValueError, "invalid hexadecimal input")
    result[index] = byte((high shl 4) or low)

proc corpusLines(path: string): seq[string] =
  for line in readFile(path).splitLines():
    let stripped = line.strip()
    if stripped.len > 0 and not stripped.startsWith("#"):
      result.add(stripped)

proc checkRecords(path: string) =
  let lines = path.corpusLines()
  check lines.len == 22
  for line in lines:
    let fields = line.split('|')
    check fields.len == 2
    let bytes = fields[1].decodeHex()
    case fields[0]
    of "projection_presentation", "projection_presentation_output",
        "projection_surface_instance", "projection_presentation_region",
        "projection_presentation_binding":
      let bounds = Rect(width: 1280, height: 720)
      let thumbnail = Rect(x: 100, y: 100, width: 320, height: 180)
      let presentation = WmPresentation(
        generation: 1,
        keyboardOutput: 1,
        outputs: @[
          PresentationOutput(
            output: 1,
            generation: 1,
            coverage: bounds,
            mode: PresentationMode.replaceApplications,
          )
        ],
        instances: @[
          SurfaceInstance(
            id: 2,
            generation: 1,
            output: 1,
            sourceIndex: 1,
            sourceGeneration: 1,
            destination: thumbnail,
            clip: thumbnail,
            opacityMillis: 1000,
            zIndex: 1,
            action: 5,
          )
        ],
        regions: @[
          PresentationRegion(
            id: 1,
            generation: 1,
            output: 1,
            geometry: bounds,
            clip: bounds,
            zIndex: 0,
            role: PresentationRegionRole.backdrop,
          )
        ],
        bindings: @[PresentationBinding(action: 5, keycode: 28)],
      )
      let index = [
        "projection_presentation", "projection_presentation_output",
        "projection_surface_instance", "projection_presentation_region",
        "projection_presentation_binding",
      ].find(fields[0])
      check bytes == presentation.encodePresentation()[index]
    of "projection_output_launch_context":
      check bytes.len == outputLaunchContextSize
      let record = OutputLaunchContext(
        output: bytes.u64At(0),
        generation: bytes.u64At(8),
        epoch: bytes.u64At(16),
        token: bytes.u64At(24),
      )
      check record.output == 1 and record.generation == 1 and record.epoch == 1 and
        record.token == 1
      check record.encodeOutputLaunchContext() == bytes
    of "projection_launch_context", "snapshot_launch_origin":
      # One fixed layout in both directions. Index zero is a valid surface, so
      # the generation is what says a context is present at all.
      let record = bytes.decodeLaunchOriginRecord()
      check record.surfaceIndex == 3
      check record.surfaceGeneration == 1
      check record.epoch == 1
      check record.token == 1
    of "snapshot_output_policy_key":
      check bytes.len == 24
      check bytes.u64At(0) == 1
      check bytes.u64At(8) == 1
      check bytes.u64At(16) == 1
    of "snapshot_output":
      check bytes.decodeSnapshotOutput().output == 1
    of "snapshot_surface":
      check bytes.decodeSnapshotSurface().surfaceIndex == 3
    of "snapshot_action":
      let action = bytes.decodeSnapshotAction()
      check action.action == 5
      check action.name.len == 10
    of "snapshot_session_operation":
      let operation = bytes.decodeSnapshotSessionOperation()
      check operation.operation == 11
      check operation.slot == 1
      check operation.targetBits == 1
    of "snapshot_surface_classification":
      # The capability-gated extension record, proven from the same corpus the
      # generated codecs parse now that the schema declares it.
      let classification = bytes.decodeSnapshotSurfaceClassification()
      check classification.surfaceIndex == 3
      check classification.surfaceGeneration == 1
      check classification.classification == 2
    of "projection_tab_group", "projection_tab_member":
      let group = ProjectionTabGroup(
        output: 1,
        group: 1,
        x: 1,
        y: 1,
        width: 1,
        height: 1,
        selectedIndex: 1,
        selectedGeneration: 1,
        focused: true,
        members: @[ProjectionTabMember(surfaceIndex: 1, surfaceGeneration: 1)],
      )
      if fields[0] == "projection_tab_group":
        check group.encodeTabGroup() == bytes
      else:
        check group.encodeTabMember(group.members[0]) == bytes
    of "projection_translation_group", "projection_translation_member":
      let group = ProjectionTranslationGroup(
        output: 1,
        group: 1,
        x: 1,
        y: 0,
        members: @[ProjectionTabMember(surfaceIndex: 1, surfaceGeneration: 1)],
      )
      if fields[0] == "projection_translation_group":
        check group.encodeTranslationGroup() == bytes
      else:
        check group.encodeTranslationMember(group.members[0]) == bytes
    of "projection_output":
      check bytes.decodeProjectionOutput().output == 1
    of "projection_placement":
      check bytes.decodeProjectionPlacement().surfaceIndex == 3
    of "projection_indicator":
      let indicator = bytes.decodeProjectionIndicator()
      check indicator.output == 1
      check indicator.action == 5
      check indicator.labelLen == 3
      check indicator.label[0] == byte('w')
      check indicator.label[1] == byte('e')
      check indicator.label[2] == byte('b')
      check indicator.label[3] == 0
    of "projection_output_status":
      let status = bytes.decodeProjectionOutputStatus()
      check status.output == 1
      check status.layoutLen == 4
      check status.layout[0] == byte('T')
      check status.layout[3] == byte('l')
      check status.layout[4] == 0
    else:
      check false

suite "independent Sophia WM fixed rows":
  test "shared row corpus used by WM file objects":
    let root = currentSourcePath().parentDir.parentDir
    checkRecords(
      root / "vendor/sophia-desktop-sdk/source/spec/golden/sophia-wm-v1.records"
    )
