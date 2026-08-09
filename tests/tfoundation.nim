import std/[json, options, os, sets, strutils, tables, tempfiles, unittest]

import config/[coordinator, migration, policy_candidate, profile]
import observability
import policy/[actions, entity_store, reducer, state, types]
import runtime/reducer as runtimeReducer
import runtime/effect_executor
import sophia/policy_adapter

proc focusable(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

proc ownerOnly(path: string) =
  setFilePermissions(path, {fpUserRead, fpUserWrite})

suite "Hagia foundation":
  test "dense entity removal swaps storage without changing semantic order":
    var store: EntityStore[WindowId, WindowData]
    for raw in 1'u32 .. 3'u32:
      let id = WindowId(raw)
      store[id] = WindowData(id: id)
    store.del(WindowId(2))
    check store.len == 2
    check WindowId(1) in store
    check WindowId(2) notin store
    check WindowId(3) in store
    check store.index[WindowId(3)] == 1
    check store.validateDense()

  test "logical ids never recycle and tag relationships clean up":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    let first = model.addWindow(output, focusable(), SizeConstraints())
    let firstTags = model.windowTagIds(first)
    model.removeWindow(first)
    let second = model.addWindow(output, focusable(), SizeConstraints())
    check uint32(second) > uint32(first)
    check first notin model.windowTags
    check firstTags.len == 1
    model.validate()

  test "identity exhaustion is terminal before wraparound":
    var model = initPolicyModel()
    model.counters.outputs = high(uint32)
    expect PolicyStateError:
      discard model.addOutput(Rect(width: 800, height: 600))
    check model.counters.outputs == high(uint32)

  test "policy reduction is deterministic and leaves its input untouched":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    discard model.addWindow(output, focusable(), SizeConstraints())
    let message = PolicyMsg(
      kind: PolicyMsgKind.action, output: output, action: PolicyAction.focusNext
    )
    let first = model.reducePolicy(message)
    let second = model.reducePolicy(message)
    check model.output(output).get().focusedWindow == nullWindowId
    check first.candidate.output(output).get().focusedWindow ==
      second.candidate.output(output).get().focusedWindow
    check first.affectedOutputs == second.affectedOutputs

  test "Hagia accepts only its provenance-bearing policy candidate":
    var model = initPolicyModel()
    let profile = loadDesktopProfile()
    model.applyPolicyCandidate(profile.candidates[ProfileAuthority.policy])
    check model.settings == defaultPolicySettings
    expect DesktopProfileError:
      model.applyPolicyCandidate(profile.candidates[ProfileAuthority.session])

  test "runtime rejection preserves last-known-good profile":
    var runtime = RuntimeModel(
      phase: RuntimePhase.idle,
      connectionEpoch: 4,
      profileGeneration: 2,
      activeProfileDigest: "old",
    )
    runtime = runtime.reduceRuntime(
      RuntimeMsg(
        kind: RuntimeMsgKind.configurationPrepared, generation: 3, digest: "candidate"
      )
    ).model
    runtime = runtime.reduceRuntime(
      RuntimeMsg(kind: RuntimeMsgKind.configurationRejected)
    ).model
    check runtime.activeProfileDigest == "old"
    check runtime.candidateProfileDigest.len == 0
    check runtime.profileGeneration == 2

  test "effect execution returns typed reducer completion":
    let executor = RuntimeEffectExecutor(
      persistCheckpoint: proc(effect: RuntimeEffect): bool =
        effect.generation == 9
    )
    let completion = executor.executeEffect(
      RuntimeEffect(kind: RuntimeEffectKind.persistCheckpoint, generation: 9)
    )
    check completion.kind == RuntimeMsgKind.effectCompleted
    check completion.success
    check completion.generation == 9
    check completion.completedEffect == RuntimeEffectKind.persistCheckpoint

  test "only checkpoint completion clears checkpoint dirtiness":
    var runtime = RuntimeModel(checkpointDirty: true)
    runtime = runtime.reduceRuntime(
      RuntimeMsg(
        kind: RuntimeMsgKind.effectCompleted,
        completedEffect: RuntimeEffectKind.emitProjection,
        success: true,
      )
    ).model
    check runtime.checkpointDirty
    runtime = runtime.reduceRuntime(
      RuntimeMsg(
        kind: RuntimeMsgKind.effectCompleted,
        completedEffect: RuntimeEffectKind.persistCheckpoint,
        success: true,
      )
    ).model
    check not runtime.checkpointDirty

  test "checkpoint v1 is rejected with a targeted diagnostic":
    expect PolicyAdapterError:
      discard restoreCheckpointPayload("HAGIA-POLICY-CHECKPOINT-1\n{}")

  test "profile includes are deterministic and provenance is retained":
    let directory = createTempDir("hagia-profile-", "")
    defer:
      removeDir(directory)
    let policyPath = directory / "policy.kdl"
    let rootPath = directory / "config.kdl"
    writeFile(policyPath, "policy { layout \"scroller\"; view-count 9; }\n")
    writeFile(
      rootPath,
      "schema 1\ninclude \"policy.kdl\"\nshell { enabled #false; }\n" &
        "shortcut { profile \"test\"; }\nsession {}\n" &
        "input { inherit-sophia #true; }\noutput { inherit-sophia #true; }\n" &
        "broker { enabled #false; }\n",
    )
    policyPath.ownerOnly()
    rootPath.ownerOnly()
    let first = loadDesktopProfile(rootPath)
    let second = loadDesktopProfile(rootPath)
    check first.digest == second.digest
    check first.sources == @[rootPath.expandFilename(), policyPath.expandFilename()]
    check first.candidates[ProfileAuthority.policy].values.len == 2
    check first.candidates[ProfileAuthority.policy].values[0].provenance.path ==
      policyPath.expandFilename()

  test "profile cycles, duplicates, and unsafe modes fail closed":
    let directory = createTempDir("hagia-invalid-profile-", "")
    defer:
      removeDir(directory)
    let firstPath = directory / "first.kdl"
    let secondPath = directory / "second.kdl"
    writeFile(firstPath, "include \"second.kdl\"\n")
    writeFile(secondPath, "include \"first.kdl\"\n")
    firstPath.ownerOnly()
    secondPath.ownerOnly()
    expect DesktopProfileError:
      discard loadDesktopProfile(firstPath)

    let duplicatePath = directory / "duplicate.kdl"
    writeFile(
      duplicatePath,
      "schema 1\npolicy { layout \"scroller\"; }\n" & "policy { layout \"scroller\"; }\n",
    )
    duplicatePath.ownerOnly()
    expect DesktopProfileError:
      discard loadDesktopProfile(duplicatePath)

    let unsafePath = directory / "unsafe.kdl"
    writeFile(unsafePath, compiledDesktopProfile)
    setFilePermissions(unsafePath, {fpUserRead, fpUserWrite, fpGroupRead, fpGroupWrite})
    expect DesktopProfileError:
      discard loadDesktopProfile(unsafePath)

  test "profile file, byte, capability, and partition bounds fail closed":
    let directory = createTempDir("hagia-profile-bounds-", "")
    defer:
      removeDir(directory)
    let manyPath = directory / "many.kdl"
    var many = "schema 1\n"
    for index in 0 ..< maxProfileFiles:
      let child = directory / ("part-" & $index & ".kdl")
      writeFile(child, "session {}\n")
      child.ownerOnly()
      many.add("include \"" & child.extractFilename() & "\"\n")
    writeFile(manyPath, many)
    manyPath.ownerOnly()
    expect DesktopProfileError:
      discard loadDesktopProfile(manyPath)

    let excessivePath = directory / "excessive.kdl"
    writeFile(excessivePath, repeat(' ', int(maxProfileBytes) + 1))
    excessivePath.ownerOnly()
    expect DesktopProfileError:
      discard loadDesktopProfile(excessivePath)

    let reservedPath = directory / "reserved.kdl"
    writeFile(reservedPath, "schema 1\npolicy { renderer \"unsafe\"; }\n")
    reservedPath.ownerOnly()
    expect DesktopProfileError:
      discard loadDesktopProfile(reservedPath)

    let profile = loadDesktopProfile()
    for authority in ProfileAuthority:
      for value in profile.candidates[authority].values:
        check value.key.startsWith($authority & ".")

  test "candidate overlays respect CLI precedence and hard limits":
    let profile = loadDesktopProfile()
    var effective = EffectiveAuthorityConfig(authority: ProfileAuthority.policy)
    effective.settings["policy.outer-gap"] =
      EffectiveSetting(key: "policy.outer-gap", value: "outer-gap 4")
    var cli = initHashSet[string]()
    cli.incl("policy.outer-gap")
    let overlaid = effective.overlayCandidate(
      profile.candidates[ProfileAuthority.policy], cli, initHashSet[string]()
    )
    check overlaid.settings["policy.outer-gap"].value == "outer-gap 4"
    var hard = initHashSet[string]()
    hard.incl("policy.layout")
    expect DesktopProfileError:
      discard effective.overlayCandidate(
        profile.candidates[ProfileAuthority.policy], initHashSet[string](), hard
      )

  test "staged authority fragments share generation and digest":
    let profile = loadDesktopProfile(generation = 7)
    let directory = createTempDir("hagia-stage-", "")
    defer:
      removeDir(directory)
    let paths = profile.stageDesktopProfile(directory)
    check paths.len == 8
    for path in paths:
      let source = readFile(path)
      check source.contains("generation=7") or source.contains("profile-generation 7")
      check source.contains(profile.digest)

  test "all authorities prepare and activate one shared profile generation":
    var activation =
      ProfileActivationModel(activeGeneration: 1, activeDigest: "known-good")
    var update = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.beginCandidate,
        generation: 2,
        digest: "candidate",
      )
    )
    check update.effects.len == allProfileAuthorities.card
    activation = update.model
    for authority in ProfileAuthority:
      activation = activation.reduceProfileActivation(
        ProfileActivationMsg(
          kind: ProfileActivationMsgKind.authorityPrepared,
          authority: authority,
          generation: 2,
          digest: "candidate",
          success: true,
        )
      ).model
    check activation.phase == ProfileActivationPhase.prepared
    update = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.activationRequested,
        generation: 2,
        digest: "candidate",
      )
    )
    check update.effects.len == allProfileAuthorities.card
    activation = update.model
    for authority in ProfileAuthority:
      activation = activation.reduceProfileActivation(
        ProfileActivationMsg(
          kind: ProfileActivationMsgKind.authorityActivated,
          authority: authority,
          generation: 2,
          digest: "candidate",
          success: true,
        )
      ).model
    check activation.phase == ProfileActivationPhase.idle
    check activation.activeGeneration == 2
    check activation.activeDigest == "candidate"
    check activation.candidateDigest.len == 0

  test "prepare rejection rolls every authority back to last known good":
    var activation =
      ProfileActivationModel(activeGeneration: 4, activeDigest: "known-good")
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.beginCandidate, generation: 5, digest: "rejected"
      )
    ).model
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.authorityPrepared,
        authority: ProfileAuthority.policy,
        generation: 5,
        digest: "rejected",
        success: true,
      )
    ).model
    let rejected = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.authorityPrepared,
        authority: ProfileAuthority.shell,
        generation: 5,
        digest: "rejected",
        success: false,
      )
    )
    check rejected.model.phase == ProfileActivationPhase.rollingBack
    check rejected.effects.len == allProfileAuthorities.card
    check rejected.model.activeDigest == "known-good"
    activation = rejected.model
    for authority in ProfileAuthority:
      activation = activation.reduceProfileActivation(
        ProfileActivationMsg(
          kind: ProfileActivationMsgKind.rollbackCompleted,
          authority: authority,
          generation: 5,
          digest: "rejected",
          success: true,
        )
      ).model
    check activation.phase == ProfileActivationPhase.idle
    check activation.activeGeneration == 4
    check activation.activeDigest == "known-good"

  test "partial activation cannot promote and stale completions are ignored":
    var activation =
      ProfileActivationModel(activeGeneration: 8, activeDigest: "known-good")
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.beginCandidate, generation: 9, digest: "partial"
      )
    ).model
    for authority in ProfileAuthority:
      activation = activation.reduceProfileActivation(
        ProfileActivationMsg(
          kind: ProfileActivationMsgKind.authorityPrepared,
          authority: authority,
          generation: 9,
          digest: "partial",
          success: true,
        )
      ).model
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.activationRequested,
        generation: 9,
        digest: "partial",
      )
    ).model
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.authorityActivated,
        authority: ProfileAuthority.policy,
        generation: 9,
        digest: "partial",
        success: true,
      )
    ).model
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.authorityActivated,
        authority: ProfileAuthority.shell,
        generation: 9,
        digest: "partial",
        success: false,
      )
    ).model
    let beforeStale = activation
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.authorityActivated,
        authority: ProfileAuthority.shortcut,
        generation: 7,
        digest: "stale",
        success: true,
      )
    ).model
    check activation == beforeStale
    check activation.activeGeneration == 8
    check activation.activeDigest == "known-good"
    check activation.phase == ProfileActivationPhase.rollingBack

  test "semantic migration classifies every accepted setting and refuses overwrite":
    let source = """
layout { gaps 8; center-focused-column "on-overflow"; }
bindings { bind "Super+q" "close-window"; bind "Super+x" "unknown"; }
input { keyboard {}; }
window-rule { match app-id="browser"; }
"""
    let report = migrateTriadProfile(source)
    check report.items.len == 7
    for item in report.items:
      check item.result.len > 0
      if item.disposition in
          {MigrationDisposition.retained, MigrationDisposition.transformed}:
        check item.authority.len > 0
    let directory = createTempDir("hagia-migration-", "")
    defer:
      removeDir(directory)
    let input = directory / "triad.kdl"
    let output = directory / "result"
    writeFile(input, source)
    discard writeMigration(input, output)
    check fileExists(output / "config.kdl")
    check fileExists(output / "migration-report.txt")
    expect DesktopProfileError:
      discard writeMigration(input, output)

  test "evidence is opt-in, schema-versioned, bounded, and metadata-free":
    let directory = createTempDir("hagia-evidence-", "")
    let previousEvidencePath = getEnv("HAGIA_EVIDENCE_NDJSON")
    defer:
      if previousEvidencePath.len > 0:
        putEnv("HAGIA_EVIDENCE_NDJSON", previousEvidencePath)
      else:
        delEnv("HAGIA_EVIDENCE_NDJSON")
      removeDir(directory)
    let path = directory / "evidence.ndjson"
    delEnv("HAGIA_EVIDENCE_NDJSON")
    recordEvidence(EvidenceEvent(kind: EvidenceKind.reducer, status: "disabled"))
    check not fileExists(path)
    putEnv("HAGIA_EVIDENCE_NDJSON", path)
    recordEvidence(
      EvidenceEvent(
        kind: EvidenceKind.settlement,
        epoch: 2,
        generation: 3,
        requestId: 4,
        transaction: 5,
        status: "committed",
      )
    )
    let node = parseJson(readFile(path).strip())
    check node["schema"].getInt() == evidenceSchema
    check node["kind"].getStr() == "settlement"
    check not node.hasKey("application")
    check not node.hasKey("sophia_handle")
    check getFilePermissions(path) == {fpUserRead, fpUserWrite}
    writeFile(path, repeat('x', int(maxEvidenceBytes)))
    recordEvidence(EvidenceEvent(kind: EvidenceKind.connection, status: "rotated"))
    check fileExists(path & ".1")
    check parseJson(readFile(path).strip())["status"].getStr() == "rotated"
