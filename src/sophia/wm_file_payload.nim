import std/strutils
import ../types/[wm_files, wm_v1]
import ./wm_files

## Strict-file checks every typed body codec shares, scalar and array alike:
## the exact kind in its expected class, the admitted epoch, fixed and prefixed
## body sizes, reserved bytes, negotiated capabilities, nonzero identities,
## affected-output lists and surface byte shape. Bodies are read through
## `bytes.toOpenArray(wmFileHeaderBytes, bytes.high)`, with body-relative
## offsets. Every bound is checked by subtraction before any conversion or
## allocation, so malformed input raises `WmFileError`, never a defect.
## Whether a surface is valid is judged by `policy_semantics`, not here.

proc payloadRecord*(
    bytes: openArray[byte], kind: WmFileKind, expectedEpoch: uint64
): WmFileHeader =
  if expectedEpoch == 0:
    failWmFile(WmFileErrorKind.epoch, "no admitted WM file epoch")
  result = bytes.decodeRecord(kind.class)
  result.requireKind(kind)
  if result.connectionEpoch != expectedEpoch:
    failWmFile(WmFileErrorKind.epoch, "WM file record belongs to another epoch")

proc fixedPayload*(
    bytes: openArray[byte], kind: WmFileKind, expectedEpoch: uint64, size: int
): WmFileHeader =
  result = bytes.payloadRecord(kind, expectedEpoch)
  if bytes.len - wmFileHeaderBytes != size:
    failWmFile(WmFileErrorKind.length, "WM file body has the wrong size")

proc prefixedPayload*(
    bytes: openArray[byte], kind: WmFileKind, expectedEpoch: uint64, prefix: int
): WmFileHeader =
  ## The tail after `prefix` belongs to the caller, which must account for all
  ## of it.
  result = bytes.payloadRecord(kind, expectedEpoch)
  if bytes.len - wmFileHeaderBytes < prefix:
    failWmFile(WmFileErrorKind.length, "WM file body is shorter than its prefix")

proc requireReserved*(body: openArray[byte], offset, count: int) =
  if offset < 0 or count < 0 or offset > body.len or count > body.len - offset:
    failWmFile(WmFileErrorKind.length, "WM file reserved field is out of bounds")
  for index in offset ..< offset + count:
    if body[index] != 0:
      failWmFile(WmFileErrorKind.reserved, "WM file reserved field is nonzero")

proc requireCapabilities*(selected, required: uint64) =
  let missing = required and not selected
  if missing != 0:
    failWmFile(
      WmFileErrorKind.capability,
      "WM file body needs unnegotiated capabilities 0x" & missing.toHex,
    )

proc requireNonzero*(values: openArray[uint64]) =
  for value in values:
    if value == 0:
      failWmFile(WmFileErrorKind.identity, "WM file body identity is null")

proc requireEpoch*(header: WmFileHeader, epoch: uint64) =
  ## For encoders whose domain value carries its own epoch.
  if header.connectionEpoch != epoch:
    failWmFile(WmFileErrorKind.epoch, "WM file value belongs to another epoch")

proc encodePayload*(
    header: WmFileHeader, kind: WmFileKind, body: openArray[byte]
): seq[byte] =
  header.requireKind(kind)
  header.encodeRecord(body)

proc readOutputs*(body: openArray[byte], offset: int, count: uint16): seq[uint64] =
  ## Exactly `count` distinct nonzero output ids, filling the body from
  ## `offset` to its end.
  let expected = int(count)
  if expected < 1 or expected > maxOutputs:
    failWmFile(WmFileErrorKind.value, "WM file output count is out of range")
  if offset < 0 or offset > body.len or
      body.len - offset != expected * wmFileOutputIdBytes:
    failWmFile(WmFileErrorKind.length, "WM file output list has the wrong size")
  result = newSeqOfCap[uint64](expected)
  for index in 0 ..< expected:
    let output = body.readU64(offset + index * wmFileOutputIdBytes)
    if output == 0 or output in result:
      failWmFile(WmFileErrorKind.value, "WM file output list is null or repeats")
    result.add(output)

proc addOutputs*(body: var seq[byte], outputs: openArray[uint64]) =
  if outputs.len < 1 or outputs.len > maxOutputs:
    failWmFile(WmFileErrorKind.value, "WM file output count is out of range")
  for index, output in outputs:
    if output == 0 or output in outputs.toOpenArray(0, index - 1):
      failWmFile(WmFileErrorKind.value, "WM file output list is null or repeats")
  for output in outputs:
    body.addU64(output)

proc readSurface*(
    body: openArray[byte], offset: int
): tuple[index, generation: uint32] =
  ## Byte shape only; `validSurface` and `validOptionalSurface` judge it.
  (body.readU32(offset), body.readU32(offset + 4))

proc addSurface*(body: var seq[byte], index, generation: uint32) =
  body.addU32(index)
  body.addU32(generation)
