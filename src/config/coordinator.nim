import std/[os, posix, sets, tables, tempfiles]

import ../types/config_values
import ./profile

proc clearCandidate(model: var ProfileActivationModel) =
  model.candidateGeneration = 0
  model.candidateDigest.setLen(0)
  model.preparedAuthorities = {}
  model.activatedAuthorities = {}
  model.rollbackPending = {}
  model.phase = ProfileActivationPhase.idle

proc matchingCandidate(
    model: ProfileActivationModel, message: ProfileActivationMsg
): bool =
  message.generation == model.candidateGeneration and
    message.digest == model.candidateDigest

proc addEffects(
    update: var ProfileActivationUpdate,
    kind: ProfileActivationEffectKind,
    authorities: set[ProfileAuthority],
) =
  for authority in ProfileAuthority:
    if authority in authorities:
      update.effects.add(
        ProfileActivationEffect(
          kind: kind,
          authority: authority,
          generation: update.model.candidateGeneration,
          digest: update.model.candidateDigest,
        )
      )

proc beginRollback(update: var ProfileActivationUpdate) =
  update.model.phase = ProfileActivationPhase.rollingBack
  # Prepare/activate effects are dispatched as a generation-wide batch. A
  # participant that reports failure may still hold local candidate state, so
  # every authority receives the same idempotent rollback.
  update.model.rollbackPending = allProfileAuthorities
  update.addEffects(
    ProfileActivationEffectKind.rollbackAuthority, update.model.rollbackPending
  )

proc reduceProfileActivation*(
    model: ProfileActivationModel, message: ProfileActivationMsg
): ProfileActivationUpdate =
  ## The coordinator promotes a digest only after every authority prepared and
  ## activated it. Any failure rolls every prepared participant back while the
  ## previous active digest remains unchanged.
  result.model = model
  case message.kind
  of ProfileActivationMsgKind.beginCandidate:
    if model.phase != ProfileActivationPhase.idle or message.generation == 0 or
        message.generation <= model.activeGeneration or
        message.generation <= model.latestGeneration or message.digest.len == 0 or
        message.digest == model.activeDigest:
      raise newException(DesktopProfileError, "profile candidate identity is invalid")
    result.model.phase = ProfileActivationPhase.preparing
    result.model.latestGeneration = message.generation
    result.model.candidateGeneration = message.generation
    result.model.candidateDigest = message.digest
    result.addEffects(
      ProfileActivationEffectKind.prepareAuthority, allProfileAuthorities
    )
  of ProfileActivationMsgKind.authorityPrepared:
    if not model.matchingCandidate(message):
      return
    if model.phase != ProfileActivationPhase.preparing or
        message.authority in model.preparedAuthorities:
      raise newException(DesktopProfileError, "authority preparation is out of order")
    if not message.success:
      result.beginRollback()
      return
    result.model.preparedAuthorities.incl(message.authority)
    if result.model.preparedAuthorities == allProfileAuthorities:
      result.model.phase = ProfileActivationPhase.prepared
  of ProfileActivationMsgKind.activationRequested:
    if not model.matchingCandidate(message) or
        model.phase != ProfileActivationPhase.prepared or
        model.preparedAuthorities != allProfileAuthorities:
      raise
        newException(DesktopProfileError, "profile activation barrier is incomplete")
    result.model.phase = ProfileActivationPhase.activating
    result.addEffects(
      ProfileActivationEffectKind.activateAuthority, allProfileAuthorities
    )
  of ProfileActivationMsgKind.authorityActivated:
    if not model.matchingCandidate(message):
      return
    if model.phase == ProfileActivationPhase.rollingBack:
      return
    if model.phase != ProfileActivationPhase.activating or
        message.authority in model.activatedAuthorities:
      raise newException(DesktopProfileError, "authority activation is out of order")
    if not message.success:
      result.beginRollback()
      return
    result.model.activatedAuthorities.incl(message.authority)
    if result.model.activatedAuthorities == allProfileAuthorities:
      result.model.activeGeneration = result.model.candidateGeneration
      result.model.activeDigest = result.model.candidateDigest
      result.model.clearCandidate()
  of ProfileActivationMsgKind.rollbackCompleted:
    if not model.matchingCandidate(message):
      return
    if model.phase != ProfileActivationPhase.rollingBack or
        message.authority notin model.rollbackPending or not message.success:
      raise newException(DesktopProfileError, "authority rollback is incomplete")
    result.model.rollbackPending.excl(message.authority)
    if result.model.rollbackPending == {}:
      result.model.clearCandidate()

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
