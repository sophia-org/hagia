import std/[json, os, strutils, times]

import chronicles

import ./types/observability

proc configuredLevel(): OperationalLevel =
  case getEnv("HAGIA_LOG_LEVEL", "info").toLowerAscii()
  of "debug": OperationalLevel.debug
  of "warn", "warning": OperationalLevel.warning
  of "error", "failure": OperationalLevel.failure
  else: OperationalLevel.info

proc operationalLog*(level: OperationalLevel, event: string, status = "", detail = "") =
  if level < configuredLevel():
    return
  # Callers pass bounded status categories, never application metadata or raw
  # Sophia handles. Details are length-limited as a second redaction boundary.
  let safeDetail =
    if detail.len > 160:
      detail[0 ..< 160]
    else:
      detail
  case level
  of OperationalLevel.debug:
    debug "hagia operational", event = event, status = status, detail = safeDetail
  of OperationalLevel.info:
    info "hagia operational", event = event, status = status, detail = safeDetail
  of OperationalLevel.warning:
    warn "hagia operational", event = event, status = status, detail = safeDetail
  of OperationalLevel.failure:
    error "hagia operational", event = event, status = status, detail = safeDetail

proc rotateEvidence(path: string, incomingBytes: int) =
  if not fileExists(path) or getFileSize(path) + int64(incomingBytes) <= maxEvidenceBytes:
    return
  let oldest = path & "." & $maxEvidenceFiles
  if fileExists(oldest):
    removeFile(oldest)
  for index in countdown(maxEvidenceFiles - 1, 1):
    let source = path & "." & $index
    if fileExists(source):
      moveFile(source, path & "." & $(index + 1))
  moveFile(path, path & ".1")

var evidenceSequence {.threadvar.}: int

proc recordEvidence*(event: EvidenceEvent) =
  let path = getEnv("HAGIA_EVIDENCE_NDJSON")
  if path.len == 0:
    return
  if not path.isAbsolute():
    raise newException(ValueError, "Hagia evidence path must be absolute")
  let parent = path.parentDir()
  if parent.len > 0:
    createDir(parent)
  inc evidenceSequence
  let record = %*{
    "schema": evidenceSchema,
    "time": getTime().toUnix(),
    "sequence": evidenceSequence,
    "kind": $event.kind,
    "event": event.event,
    "epoch": event.epoch,
    "generation": event.generation,
    "request": event.requestId,
    "transaction": event.transaction,
    "status": event.status,
    "digest": event.digest,
  }
  let encoded = $record & "\n"
  path.rotateEvidence(encoded.len)
  let existed = fileExists(path)
  var file = open(path, fmAppend)
  defer:
    file.close()
  if not existed:
    setFilePermissions(path, {fpUserRead, fpUserWrite})
  file.write(encoded)
