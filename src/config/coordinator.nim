import std/[os, posix, sets, tables, tempfiles]

import ./profile

type
  EffectiveSetting* = object
    key*: string
    value*: string
    provenance*: ValueProvenance

  EffectiveAuthorityConfig* = object
    authority*: ProfileAuthority
    settings*: Table[string, EffectiveSetting]

proc overlayCandidate*(
    effective: EffectiveAuthorityConfig,
    candidate: AuthorityCandidate,
    cliOverrides: HashSet[string],
    hardLimits: HashSet[string],
): EffectiveAuthorityConfig =
  if effective.authority != candidate.authority:
    raise newException(
      DesktopProfileError, "desktop profile candidate crossed an authority boundary"
    )
  result = effective
  for value in candidate.values:
    if value.key in hardLimits:
      raise newException(
        DesktopProfileError,
        "desktop profile attempts to override hard limit " & value.key,
      )
    if value.key notin cliOverrides:
      result.settings[value.key] = EffectiveSetting(
        key: value.key, value: value.encoded, provenance: value.provenance
      )

proc syncDirectory(path: string) =
  let handle = posix.open(path.cstring, O_RDONLY)
  if handle < 0:
    raiseOSError(osLastError())
  let synced = posix.fsync(handle) == 0
  discard posix.close(handle)
  if not synced:
    raiseOSError(osLastError())

proc replaceOwnerOnly(path, contents: string) =
  let directory = path.parentDir()
  createDir(directory)
  var temporary = ""
  var file: File
  try:
    (file, temporary) =
      createTempFile(path.extractFilename() & ".candidate-", "", directory)
    setFilePermissions(temporary, {fpUserRead, fpUserWrite})
    file.write(contents)
    file.flushFile()
    if posix.fsync(file.getFileHandle()) != 0:
      raiseOSError(osLastError())
    file.close()
    file = nil
    moveFile(temporary, path)
    directory.syncDirectory()
  except CatchableError:
    if file != nil:
      file.close()
    if temporary.len > 0 and fileExists(temporary):
      removeFile(temporary)
    raise

proc candidateFragment(candidate: AuthorityCandidate): string =
  result.add("schema 1\n")
  result.add("profile-generation " & $candidate.generation & "\n")
  result.add("profile-digest \"" & candidate.digest & "\"\n")
  result.add($candidate.authority & " {\n")
  for value in candidate.values:
    result.add("  " & value.encoded & "\n")
  result.add("}\n")

proc stageDesktopProfile*(
    profile: DesktopProfileGeneration, privateRuntimeDirectory: string
): seq[string] =
  if privateRuntimeDirectory.len == 0 or not privateRuntimeDirectory.isAbsolute():
    raise newException(
      DesktopProfileError, "profile staging directory must be an absolute private path"
    )
  createDir(privateRuntimeDirectory)
  setFilePermissions(privateRuntimeDirectory, {fpUserRead, fpUserWrite, fpUserExec})
  for authority in ProfileAuthority:
    let path = privateRuntimeDirectory / ($authority & ".kdl")
    path.replaceOwnerOnly(profile.candidates[authority].candidateFragment())
    result.add(path)
  let manifest =
    "generation=" & $profile.generation & "\ndigest=" & profile.digest & "\n"
  let manifestPath = privateRuntimeDirectory / "profile.manifest"
  manifestPath.replaceOwnerOnly(manifest)
  result.add(manifestPath)
