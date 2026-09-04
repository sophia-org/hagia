import std/[json, options, os, posix, tempfiles]

import ./policy_adapter

export checkpointPayload

type PolicyCheckpointError* = object of CatchableError

const maxPolicyCheckpointBytes = 1_048_576'i64

proc checkpointPath*(): string =
  getEnv("HAGIA_POLICY_CHECKPOINT")

proc loadPolicyCheckpoint*(path: string): Option[PolicyAdapter] =
  if path.len == 0 or not fileExists(path):
    return none(PolicyAdapter)
  if getFileSize(path) < 1 or getFileSize(path) > maxPolicyCheckpointBytes:
    raise
      newException(PolicyCheckpointError, "private policy checkpoint size is invalid")
  try:
    some(readFile(path).restoreCheckpointPayload())
  except CatchableError as error:
    raise newException(
      PolicyCheckpointError, "private policy checkpoint is invalid: " & error.msg
    )

proc savePolicyCheckpoint*(path: string, adapter: PolicyAdapter) =
  if path.len == 0:
    return
  let parent = path.parentDir()
  if parent.len > 0:
    createDir(parent)
  let directory = if parent.len > 0: parent else: "."
  var temporary = ""
  var candidate: File
  try:
    (candidate, temporary) =
      createTempFile(path.extractFilename() & ".candidate-", "", directory)
    let payload = adapter.checkpointPayload()
    if payload.len == 0 or int64(payload.len) > maxPolicyCheckpointBytes:
      raise
        newException(PolicyCheckpointError, "private policy checkpoint is excessive")
    setFilePermissions(temporary, {fpUserRead, fpUserWrite})
    candidate.write(payload)
    candidate.flushFile()
    if posix.fsync(candidate.getFileHandle()) != 0:
      raiseOSError(osLastError())
    candidate.close()
    candidate = nil
    moveFile(temporary, path)
    let directoryFd = posix.open(directory.cstring, O_RDONLY)
    if directoryFd < 0:
      raiseOSError(osLastError())
    let directorySynced = posix.fsync(directoryFd) == 0
    discard posix.close(directoryFd)
    if not directorySynced:
      raiseOSError(osLastError())
  except CatchableError as error:
    if candidate != nil:
      candidate.close()
    if temporary.len > 0 and fileExists(temporary):
      removeFile(temporary)
    raise newException(
      PolicyCheckpointError,
      "private policy checkpoint replacement failed: " & error.msg,
    )

proc dumpCheckpointJson*(payload: string): string =
  ## Pretty-print a checkpoint payload. The first line is the schema banner the
  ## restore path checks; everything after it is the DTO.
  let split = payload.find('\n')
  if split < 0:
    raise newException(PolicyCheckpointError, "checkpoint payload has no banner")
  pretty(parseJson(payload[split + 1 .. ^1]))
