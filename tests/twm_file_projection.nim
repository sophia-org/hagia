import std/[options, sequtils, unittest]
import types/[session, wm_v1, wm_files, wm_file_arrays, wm_presentation]
import sophia/[wm_files, wm_file_arrays]
import support/wm_file_projection_fixture

proc header(): WmFileHeader =
  WmFileHeader(kind: WmFileKind.projection, connectionEpoch: 9, submissionId: 17)

proc encode(value: PolicyProjection, selected = high(uint64)): seq[byte] =
  header().encodeFileProjection(55, fileProjectionRequest(), value, selected)

proc sections(bytes: seq[byte]): seq[WmFileSectionView] =
  let start = wmFileHeaderBytes + wmFileProjectionPrefixBytes
  bytes.toOpenArray(start, bytes.high).decodeSections(
    bytes.readU16(wmFileHeaderBytes + 32)
  )

proc kinds(bytes: seq[byte]): seq[uint16] =
  for section in bytes.sections():
    result.add(section.kind)

suite "complete WM file projection candidates":
  test "every extension is one ascending complete section":
    let bytes = fileProjection().encode()
    check bytes.kinds() ==
      @[
        1'u16, 2, 3, 4, 0xff01, 0xff02, 0xff03, 0xff04, 0xff05, 0xff08, 0xff09, 0xff0a,
        0xff0b, 0xff0c, 0xff0d,
      ]
    check bytes.decodeRecord(WmFileClass.candidateRecord).submissionId == 17
    check bytes.readU64(wmFileHeaderBytes) == 55
    check bytes.readU64(wmFileHeaderBytes + 8) == 12
    check bytes.readU64(wmFileHeaderBytes + 16) == 19
    check bytes.readU64(wmFileHeaderBytes + 24) == 7
    let groups = bytes.sections()[4]
    let at = wmFileHeaderBytes + wmFileProjectionPrefixBytes + groups.offset
    check bytes.readU32(at + 32) == 0
    check bytes.readU32(at + 36) == 1

  test "tab selection is a canonical optional surface":
    # Surface index zero is present when its generation is nonzero.
    var value = fileProjection()
    check value.tabGroups[0].selectedIndex == 0
    check value.tabGroups[0].selectedGeneration == 1
    value.tabGroups[0].selectedGeneration = 0
    value.tabGroups[0].members = @[]
    let bytes = value.encode()
    let group = bytes.sections()[4]
    let at = wmFileHeaderBytes + wmFileProjectionPrefixBytes + group.offset
    check bytes.readU32(at + 32) == 0
    check bytes.readU32(at + 36) == 0
    check 0xff02'u16 notin bytes.kinds()
    value.tabGroups[0].selectedIndex = 5
    expect WmFileError:
      discard value.encode()

  test "unnegotiated optional hints are omitted":
    check baseFileProjection().encode(0).kinds() == @[1'u16, 2]
    check baseFileProjection().encode(capabilityOutputLaunchContext).kinds() ==
      @[1'u16, 2]
    check baseFileProjection().encode(capabilityLaunchOrigin).kinds() ==
      @[1'u16, 2, 0xff05]
    check baseFileProjection()
      .encode(capabilityLaunchOrigin or capabilityOutputLaunchContext)
      .kinds() == @[1'u16, 2, 0xff05, 0xff08]

  test "required policy and presentation capabilities refuse instead of disappearing":
    for bit in [
      capabilityIndicators, capabilityTabGroups, capabilitySurfaceInstances,
      capabilityActions, capabilityPresentationActions,
    ]:
      expect WmFileError:
        discard fileProjection().encode(high(uint64) xor bit)

  test "passive presentation needs only surface instances":
    var value = baseFileProjection()
    var presentation = fileProjection().presentation.get()
    presentation.keyboardOutput = 0
    presentation.bindings = @[]
    presentation.instances[0].action = 0
    value.presentation = some(presentation)
    check 0xff09'u16 in value.encode(capabilitySurfaceInstances).kinds()
    check 0xff0d'u16 notin value.encode(capabilitySurfaceInstances).kinds()

  test "base row maxima and exact output partitions are checked":
    var value = baseFileProjection()
    value.outputs[0].placements =
      repeat(value.outputs[0].placements[0], maxSurfaces + 1)
    value.outputs[0].output.placementCount = uint32(maxSurfaces + 1)
    expect WmFileError:
      discard value.encode()
    value = fileProjection()
    value.indicators = repeat(value.indicators[0], maxIndicators + 1)
    expect WmFileError:
      discard value.encode()
    value = fileProjection()
    value.outputStatuses = repeat(value.outputStatuses[0], maxOutputs + 1)
    expect WmFileError:
      discard value.encode()
    value = baseFileProjection()
    value.outputs[0].output.placementCount = 2
    expect WmFileError:
      discard value.encode()
    value = baseFileProjection()
    value.outputs[0].output.output = 8
    expect WmFileError:
      discard value.encode()

  test "group maxima identities and empty translation groups refuse":
    var value = fileProjection()
    value.tabGroups = repeat(value.tabGroups[0], maxTabGroups + 1)
    expect WmFileError:
      discard value.encode()
    value = fileProjection()
    value.tabGroups[0].members =
      repeat(value.tabGroups[0].members[0], maxTabMembers + 1)
    expect WmFileError:
      discard value.encode()
    value = fileProjection()
    value.tabGroups[0].selectedIndex = high(uint32)
    expect WmFileError:
      discard value.encode()
    value = fileProjection()
    value.tabGroups[0].members[0].surfaceGeneration = 0
    expect WmFileError:
      discard value.encode()
    value = fileProjection()
    value.translationGroups[0].members = @[]
    expect WmFileError:
      discard value.encode()

  test "epoch and placement byte shapes refuse":
    var request = fileProjectionRequest()
    request.connectionEpoch = 10
    expect WmFileError:
      discard header().encodeFileProjection(55, request, fileProjection(), high(uint64))
    var value = baseFileProjection()
    value.outputs[0].placements[0].transform = 2
    expect WmFileError:
      discard value.encode()
    value = baseFileProjection()
    value.outputs[0].placements[0].requestedWidth = 1
    expect WmFileError:
      discard value.encode()
    value = baseFileProjection()
    value.outputs[0].placements[0].cropX = 1
    expect WmFileError:
      discard value.encode()
    value = fileProjection()
    value.launchContexts[0].epoch = 10
    expect WmFileError:
      discard value.encode()

  test "labels need nonempty control-free UTF-8 and zero padding":
    for bad in [0'u16, 33]:
      var value = fileProjection()
      value.indicators[0].labelLen = bad
      expect WmFileError:
        discard value.encode()
    for bad in [0'u8, 0x1f, 0x7f, 0xff]:
      var value = fileProjection()
      value.indicators[0].label[0] = bad
      expect WmFileError:
        discard value.encode()
    var value = fileProjection()
    value.outputStatuses[0].layout[5] = byte('x')
    expect WmFileError:
      discard value.encode()

  test "a section can exceed the old chunk size without splitting":
    var value = baseFileProjection()
    var presentation = fileProjection().presentation.get()
    let original = presentation.instances[0]
    presentation.instances = @[]
    for index in 0 ..< maxSurfaceInstances:
      var instance = original
      instance.id = uint64(100 + index)
      instance.zIndex = uint16(index + 1)
      presentation.instances.add(instance)
    value.presentation = some(presentation)
    let bytes = value.encode()
    var found = 0
    for section in bytes.sections():
      if section.kind == 0xff0b:
        inc found
        check section.count == uint32(maxSurfaceInstances)
        check section.length == maxSurfaceInstances * presentationRecordSizes[2]
        check section.length > 65536
    check found == 1
