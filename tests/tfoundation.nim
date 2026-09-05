import std/[json, options, os, posix, sets, strutils, tables, tempfiles, unittest]

import kdl

import config/[coordinator, migration, policy_candidate, profile]
import observability
import policy/[actions, entity_store, reducer, state]
import
  types/[
    actions, config_values, core, migration, model, observability, policy_messages,
    runtime,
  ]
import runtime/reducer as runtimeReducer
import runtime/effect_executor
import sophia/[policy_signals, policy_trace]
import types/[session, wm_v1]
import sophia/policy_adapter

const trackedDefaultDesktopProfile = staticRead("../examples/config/default.kdl")

proc focusable(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

proc ownerOnly(path: string) =
  setFilePermissions(path, {fpUserRead, fpUserWrite})

suite "Hagia foundation":
  test "a trace entry round-trips so a replay sees the recorded inputs":
    # Replay is only worth anything if what is written is what is read back.
    # A lossy field would make a trace disagree with the session it came from
    # while still looking like a valid recording.
    let entry = PolicyTraceEntry(
      snapshot: PolicySnapshot(
        generation: 7,
        activeOutput: 3,
        outputs: @[SnapshotOutput(output: 3, generation: 1, width: 800, height: 600)],
      ),
      request: ProjectionRequest(
        connectionEpoch: 2, requestId: 9, sceneGeneration: 7, affectedOutputs: @[3'u64]
      ),
      transaction: 5,
    )
    let restored = entry.traceLine().parseTraceLine()
    check restored.transaction == entry.transaction
    check restored.snapshot.generation == entry.snapshot.generation
    check restored.snapshot.activeOutput == entry.snapshot.activeOutput
    check restored.snapshot.outputs.len == 1
    check restored.snapshot.outputs[0].width == 800
    check restored.request.requestId == entry.request.requestId
    check restored.request.affectedOutputs == entry.request.affectedOutputs
    expect PolicyTraceError:
      discard "not json".parseTraceLine()
    expect PolicyTraceError:
      discard """{"snapshot":{}}""".parseTraceLine()

  test "a reload request is taken exactly once":
    # The session loop refuses a reload it cannot make durable, so a request
    # that is read must not remain set and fire against a later cycle.
    installPolicySignals()
    check not takeReloadRequest()
    discard posix.raise(posix.SIGHUP)
    check takeReloadRequest()
    check not takeReloadRequest()

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

  test "config init seeds once and never overwrites":
    let directory = createTempDir("hagia-init-", "")
    let previousConfigHome = getEnv("XDG_CONFIG_HOME")
    defer:
      if previousConfigHome.len > 0:
        putEnv("XDG_CONFIG_HOME", previousConfigHome)
      else:
        delEnv("XDG_CONFIG_HOME")
      removeDir(directory)
    putEnv("XDG_CONFIG_HOME", directory)
    let expected = directory / "hagia" / "config.kdl"

    # First run installs the compiled default byte-for-byte, and the result
    # loads: a seed that cannot be loaded must not count as installed.
    let first = initDesktopProfile()
    check first.path == expected
    check first.installed
    check readFile(expected) == compiledDesktopProfile
    check loadDesktopProfile(expected).generation == 1

    # Second run leaves the file untouched, even after a user edit.
    writeFile(expected, "schema 1\n")
    let second = initDesktopProfile()
    check not second.installed
    check readFile(expected) == "schema 1\n"

    # A symlink occupying the path is also left alone: seeding must never
    # write through or replace something the user pointed elsewhere.
    removeFile(expected)
    createSymlink(directory / "nowhere.kdl", expected)
    let third = initDesktopProfile()
    check not third.installed
    check symlinkExists(expected)

  test "Hagia accepts only its provenance-bearing policy candidate":
    var model = initPolicyModel()
    let directory = createTempDir("hagia-compiled-profile-", "")
    defer:
      removeDir(directory)
    let path = directory / "config.kdl"
    writeFile(path, compiledDesktopProfile)
    path.ownerOnly()
    let profile = loadDesktopProfile(path)
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

    runtime = runtime.reduceRuntime(
      RuntimeMsg(
        kind: RuntimeMsgKind.configurationPrepared, generation: 4, digest: "candidate-2"
      )
    ).model
    runtime = runtime.reduceRuntime(
      RuntimeMsg(
        kind: RuntimeMsgKind.effectCompleted,
        generation: 4,
        digest: "candidate-2",
        completedEffect: RuntimeEffectKind.prepareProfile,
        success: false,
      )
    ).model
    check runtime.phase == RuntimePhase.idle
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

  test "every superseded checkpoint is rejected with a targeted diagnostic":
    # A schema that gained fields cannot be read by guessing what the older
    # payload meant to say, so it is refused and a complete snapshot rebuilds.
    for version in ["1", "2", "3"]:
      expect PolicyAdapterError:
        discard restoreCheckpointPayload("HAGIA-POLICY-CHECKPOINT-" & version & "\n{}")

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

  test "shortcut candidates require typed chords and explicit target authorities":
    let directory = createTempDir("hagia-shortcut-profile-", "")
    defer:
      removeDir(directory)
    let path = directory / "config.kdl"
    writeFile(
      path,
      "schema 1\nshortcut { profile \"daily\"; " &
        "bind \"Super+q\" \"session:close-window\"; " &
        "bind \"Super+1\" \"policy:activate-view 1\"; " &
        "pointer-bind \"Super+left\" \"policy:move\"; }\n",
    )
    path.ownerOnly()
    let profile = loadDesktopProfile(path)
    check profile.candidates[ProfileAuthority.shortcut].values.len == 4

    for source in [
      "schema 1\nshortcut { profile \"daily\"; bind \"Super+q\" \"close-window\"; }\n",
      "schema 1\nshortcut { profile \"daily\"; bind \"Ctrl+Alt+Backspace\" \"session:logout\"; }\n",
      "schema 1\nshortcut { profile \"daily\"; pointer-bind \"Super+left\" \"session:logout\"; }\n",
      "schema 1\nshortcut { profile \"daily\"; bind \"Super+q\" \"policy:first\"; bind \"super+Q\" \"policy:second\"; }\n",
    ]:
      writeFile(path, source)
      path.ownerOnly()
      expect DesktopProfileError:
        discard loadDesktopProfile(path)

  test "the compiled freeze profile names only implemented policy actions":
    check compiledDesktopProfile == trackedDefaultDesktopProfile
    check compiledDesktopProfile.contains("profile \"default\"")
    check compiledDesktopProfile.contains("panel 28")
    check compiledDesktopProfile.contains(
      "session {\n  terminal \"terminal\"\n  browser \"browser\"\n}"
    )
    check not compiledDesktopProfile.contains("named \"")
    let directory = createTempDir("hagia-compiled-shortcuts-", "")
    defer:
      removeDir(directory)
    let path = directory / "config.kdl"
    writeFile(path, compiledDesktopProfile)
    path.ownerOnly()
    let profile = loadDesktopProfile(path)
    let shortcuts = profile.candidates[ProfileAuthority.shortcut]
    var policyBindings = 0
    for value in shortcuts.values:
      if not value.encoded.contains("policy:"):
        continue
      var implemented =
        value.encoded.contains("pointer-bind") and (
          value.encoded.contains("policy:move") or
          value.encoded.contains("policy:resize")
        )
      for ordinal in ord(low(PolicyAction)) .. ord(high(PolicyAction)):
        let action = PolicyAction(ordinal)
        if action.raw().isPolicyAction() and
            value.encoded.contains("policy:" & action.profileName()):
          implemented = true
          break
      check implemented
      inc policyBindings
    # Ninety-three bindings, of which eighty-five name a policy action --
    # three of those being the camera keys, which move the view without
    # moving focus. The other eight are session capabilities Sophia carries
    # out, including the two that reload the profile and replace this process.
    check shortcuts.values.len == 93
    check policyBindings == 85

  test "a trigger Sophia cannot bind is refused before a session is attempted":
    # A chord that passes the character check but names no key used to reach
    # Sophia, which rejected the whole policy configuration and killed the
    # session at login, after `config check` had already called the profile
    # valid. The keysym spellings below are the ones that actually did it.
    let directory = createTempDir("hagia-trigger-", "")
    defer:
      removeDir(directory)
    for spelling in ["bracketleft", "bracketright", "comma", "period", "minus", "equal"]:
      let path = directory / "config.kdl"
      writeFile(
        path,
        "schema 1\nshortcut { profile \"t\"; bind \"Super+" & spelling &
          "\" \"policy:focus-next\"; }\n",
      )
      path.ownerOnly()
      expect DesktopProfileError:
        discard loadDesktopProfile(path)

    # The characters those spellings stand for are bindable.
    for literal in ["[", "]", ",", ".", "-", "="]:
      let path = directory / "config.kdl"
      writeFile(
        path,
        "schema 1\nshortcut { profile \"t\"; bind \"Super+" & literal &
          "\" \"policy:focus-next\"; }\n",
      )
      path.ownerOnly()
      discard loadDesktopProfile(path)

  test "every shipped default binding names a key Sophia can resolve":
    # The compiled fallback is what an unconfigured desktop starts with, so a
    # trigger it cannot bind is a broken default, not a broken profile.
    let directory = createTempDir("hagia-default-triggers-", "")
    defer:
      removeDir(directory)
    let path = directory / "config.kdl"
    writeFile(path, compiledDesktopProfile)
    path.ownerOnly()
    let profile = loadDesktopProfile(path)
    var checked = 0
    for value in profile.candidates[ProfileAuthority.shortcut].values:
      let node = parseKdl(value.encoded)[0]
      if node.name != "bind" or node.args.len == 0:
        continue
      check node.args[0].get(string).split('+')[^1].toLowerAscii() in
        bindableTriggerNames
      inc checked
    check checked > 0

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

  test "Hagia loads only a bounded owner-safe staged policy candidate":
    let directory = createTempDir("hagia-policy-candidate-", "")
    defer:
      removeDir(directory)
    let digest = repeat('a', 64)
    let policyPath = directory / "policy.profile.kdl"
    writeFile(
      policyPath,
      "schema 1\nprofile-generation 8\nprofile-digest \"" & digest &
        "\"\npolicy { layout \"grid\"; " &
        "layout-cycle \"scroller\" \"grid\" \"monocle\"; " &
        "view-count 8; outer-gap 3; }\n",
    )
    policyPath.ownerOnly()
    let candidate = loadAuthorityCandidate(policyPath, ProfileAuthority.policy)
    check candidate.authority == ProfileAuthority.policy
    check candidate.generation == 8
    check candidate.digest == digest
    check candidate.values.len == 4
    check candidate.values[0].provenance.path == policyPath.expandFilename()
    var model = initPolicyModel()
    model.applyPolicyCandidate(candidate)
    check model.settings.layoutCycle ==
      @[LayoutMode.grid, LayoutMode.scroller, LayoutMode.monocle]

    let sessionPath = directory / "session.profile.kdl"
    writeFile(
      sessionPath,
      "schema 1\nprofile-generation 8\nprofile-digest \"" & digest &
        "\"\nsession { terminal \"foot\"; }\n",
    )
    sessionPath.ownerOnly()
    expect DesktopProfileError:
      discard loadAuthorityCandidate(sessionPath, ProfileAuthority.policy)

    setFilePermissions(policyPath, {fpUserRead, fpUserWrite, fpGroupRead, fpGroupWrite})
    expect DesktopProfileError:
      discard loadAuthorityCandidate(policyPath, ProfileAuthority.policy)

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

  test "rejected profile generations never recycle":
    var activation =
      ProfileActivationModel(activeGeneration: 4, activeDigest: "known-good")
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.beginCandidate,
        generation: 5,
        digest: "candidate",
      )
    ).model
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.authorityPrepared,
        authority: ProfileAuthority.policy,
        generation: 5,
        digest: "candidate",
        success: false,
      )
    ).model
    for authority in ProfileAuthority:
      activation = activation.reduceProfileActivation(
        ProfileActivationMsg(
          kind: ProfileActivationMsgKind.rollbackCompleted,
          authority: authority,
          generation: 5,
          digest: "candidate",
          success: true,
        )
      ).model

    check activation.latestGeneration == 5
    expect DesktopProfileError:
      discard activation.reduceProfileActivation(
        ProfileActivationMsg(
          kind: ProfileActivationMsgKind.beginCandidate,
          generation: 5,
          digest: "candidate",
        )
      )

    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.beginCandidate,
        generation: 6,
        digest: "candidate",
      )
    ).model
    let beforeStale = activation
    activation = activation.reduceProfileActivation(
      ProfileActivationMsg(
        kind: ProfileActivationMsgKind.authorityPrepared,
        authority: ProfileAuthority.policy,
        generation: 5,
        digest: "candidate",
        success: true,
      )
    ).model
    check activation == beforeStale

    let exhausted = ProfileActivationModel(latestGeneration: high(uint64))
    expect DesktopProfileError:
      discard exhausted.reduceProfileActivation(
        ProfileActivationMsg(
          kind: ProfileActivationMsgKind.beginCandidate,
          generation: high(uint64),
          digest: "exhausted",
        )
      )

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
scratchpad { width-ratio 0.8; }
workspaces { default-count 3; }
protocol-surfaces { enabled #true; }
    window-rule { match app-id="browser"; }
"""
    let report = migrateTriadProfile(source)
    check report.items.len >= 10
    for item in report.items:
      check item.result.len > 0
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
    check readFile(output / "migration-report.txt").startsWith("migration-report-v2\n")
    expect DesktopProfileError:
      discard writeMigration(input, output)

  test "semantic migration retains typed input output workspace and session values":
    let fixture =
      currentSourcePath().parentDir() / "fixtures" / "triad-daily-driver-authorities.kdl"
    let source = readFile(fixture)
    let report = migrateTriadProfile(source)
    check "  view-count 3" in report.outputProfile
    check "  terminal kitty" in report.outputProfile
    check "        repeat-rate 40" in report.outputProfile
    check "        numlock #true" in report.outputProfile
    check "    pointer {" in report.outputProfile
    check "        accel-profile flat" in report.outputProfile
    check "    named DP-1 {" in report.outputProfile
    check "        focus-at-startup #true" in report.outputProfile
    check "    named DP-2 {" in report.outputProfile
    check "        position 2560 0" in report.outputProfile
    check "        enabled #true" in report.outputProfile

    var classified = initHashSet[string]()
    var layoutUnsupported = false
    for item in report.items:
      classified.incl(item.source)
      if item.source == "output.layout":
        layoutUnsupported = item.disposition == MigrationDisposition.unsupported
      check item.authority.len > 0
      check item.authority != "unowned"
      check item.result.len > 0
    for source in [
      "workspaces.default-count", "workspaces.default-layout", "terminal.command",
      "allow-exit-session", "input.keyboard.repeat-rate", "input.keyboard.repeat-delay",
      "input.keyboard.numlock", "input.keyboard.capslock", "input.keyboard.xkb.rules",
      "input.keyboard.xkb.model", "input.keyboard.xkb.layout",
      "input.keyboard.xkb.variant", "input.keyboard.xkb.options",
      "input.mouse.natural-scroll", "input.mouse.accel-profile",
      "input.mouse.accel-speed", "input.mouse.left-handed",
      "input.mouse.middle-emulation", "input.mouse.scroll-factor", "output.layout",
      "output.monitor[DP-1].mode", "output.monitor[DP-1].scale",
      "output.monitor[DP-1].position", "output.monitor[DP-1].focus-at-startup",
      "output.monitor[DP-1].vrr", "output.monitor[DP-2].mode",
      "output.monitor[DP-2].scale", "output.monitor[DP-2].position",
      "output.monitor[DP-2].disabled",
    ]:
      check source in classified
    check layoutUnsupported

  test "semantic migration reports ambiguity and unsupported device policy":
    let report = migrateTriadProfile(
      """
input {
  mouse { natural-scroll #true; natural-scroll #false; }
  touchpad { tap #true; natural-scroll #true; }
}
output {
  monitor "DP-1" { vrr 3; enabled #true; disabled #false; }
  monitor "DP-1" { mode "preferred"; }
}
"""
    )
    check report.outputProfile.count("natural-scroll") == 1
    check report.outputProfile.count("named DP-1") == 1
    var unsupported = initHashSet[string]()
    for item in report.items:
      if item.disposition == MigrationDisposition.unsupported:
        unsupported.incl(item.source)
    check "input.mouse.natural-scroll" in unsupported
    check "input.touchpad" in unsupported
    check "input.touchpad.tap" in unsupported
    check "input.touchpad.natural-scroll" in unsupported
    check "output.monitor[DP-1].vrr" in unsupported
    check "output.monitor[DP-1].disabled" in unsupported
    check "output.monitor[DP-1]" in unsupported

  test "recorded Triad default has a complete physical binding inventory":
    let fixture =
      currentSourcePath().parentDir() / "fixtures" / "triad-default-bindings.kdl"
    let report = readFile(fixture).migrateTriadProfile()
    var keyBindings = 0
    var pointerBindings = 0
    var unsupportedBindings = 0
    var excludedBindings = 0
    var deferredBindings = 0
    for item in report.items:
      if item.kind != MigrationItemKind.physicalBinding:
        continue
      check item.settingAuthority == "shortcut"
      check item.authority.len > 0
      check item.authority != "unowned"
      check item.result.len > 0
      check item.trigger.len > 0
      check item.command.len > 0
      case item.bindingKind
      of MigrationBindingKind.key:
        inc keyBindings
      of MigrationBindingKind.pointer:
        inc pointerBindings
      else:
        check false
      case item.disposition
      of MigrationDisposition.unsupported:
        inc unsupportedBindings
      of MigrationDisposition.excluded:
        inc excludedBindings
      of MigrationDisposition.deferred:
        inc deferredBindings
        check item.authority == "policy"
        check "tab bar" in item.result
      else:
        discard
    check report.physicalBindingCount() == 137
    check keyBindings == 132
    check pointerBindings == 5
    check unsupportedBindings == 0
    check excludedBindings > 0
    check deferredBindings == 0
    # One more than the old count: triad-reload is carried now instead of
    # refused, because the session gained a reload capability for it to name.
    check report.outputProfile.count("\n  bind ") == 108
    check report.outputProfile.count("\n  pointer-bind ") == 2
    check "bind Super+p \"session:window-switcher\"" in report.outputProfile
    check "pointer-bind Super+middle" notin report.outputProfile
    for carried in [
      "bind Super+h \"policy:focus-column-prev\"",
      "bind Super+l \"policy:focus-column-next\"",
      "bind Super+k \"policy:focus-window-above\"",
      "bind Super+j \"policy:focus-window-below\"",
      "bind Super+Tab \"policy:focus-last\"", "bind Super+d \"policy:layout-tile\"",
      "bind Super+Ctrl+x \"policy:layout-monocle\"",
      "bind Super+Ctrl+e \"policy:toggle-named-scratchpad 1\"",
      "bind Super+Shift+a \"policy:move-to-named-scratchpad 2\"",
      "bind Super+Ctrl+h \"policy:move-window-column-prev\"",
      "bind Super+Ctrl+k \"policy:move-window-above\"",
      "bind Super+Alt+l \"policy:move-column-next\"",
      "bind Super+Alt+Home \"policy:move-column-first\"",
      "bind Super+z \"policy:promote-column\"",
      "bind Super+Ctrl+u \"policy:move-to-view-next\"",
      "bind Super+Shift+1 \"policy:swap-with-view 1\"",
      "bind Super+Shift+h \"policy:move-view-to-output-prev\"",
      "bind Super+Shift+l \"policy:move-view-to-output-next\"",
      "bind Super+m \"policy:maximize-column\"", "bind Super+0 \"policy:toggle-gaps\"",
      "bind Super+. \"policy:increase-master-ratio\"",
      "bind Super+, \"policy:decrease-master-ratio\"",
      "bind \"Super+]\" \"policy:increase-master-count\"",
      "bind \"Super+[\" \"policy:decrease-master-count\"",
      "bind Super+Ctrl+c \"policy:layout-center-tile\"",
      "bind Super+Shift+c \"policy:layout-right-tile\"",
      "bind Super+Shift+g \"policy:layout-vertical-grid\"",
      "bind Super+Ctrl+v \"policy:layout-deck\"",
      "bind Super+y \"policy:group-windows\"",
      "bind Super+Shift+y \"policy:ungroup-window\"",
      "bind Super+Ctrl+y \"policy:focus-next-in-group\"",
      "bind Super+Alt+6 \"policy:layout-spiral\"",
      "bind Super+Alt+3 \"policy:layout-dwindle\"",
      "bind Super+Alt+j \"policy:split-down\"", "bind Super+Alt+k \"policy:split-up\"",
    ]:
      check carried in report.outputProfile

  test "every policy-authority Triad command is carried or names its refusal":
    # The parity criterion the whole port effort pointed at: migrating Triad's
    # recorded default excludes no policy command for lack of a capability.
    # The exclusions that remain are structural facts of a flat profile, and
    # each must say which fact: a chord already spent, a binding scoped to a
    # shell mode Hagia does not model, or a pointer chord whose command
    # belongs to another authority.
    let fixture =
      currentSourcePath().parentDir() / "fixtures" / "triad-default-bindings.kdl"
    let report = readFile(fixture).migrateTriadProfile()
    for item in report.items:
      if item.kind != MigrationItemKind.physicalBinding:
        continue
      if item.authority != "policy":
        continue
      if item.disposition in
          {MigrationDisposition.retained, MigrationDisposition.transformed}:
        continue
      check item.disposition == MigrationDisposition.excluded
      check (
        "duplicate shortcut identity" in item.result or
        "contextual shell modes" in item.result or
        "pointer binding cannot cross" in item.result or
        "retains only move and resize pointer actions" in item.result
      )

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
        event: "projection",
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
    # Schema 2 names the event and orders records within a second. Without both,
    # the structured stream cannot say what happened or in what order, and the
    # only stream that can is Chronicles stdout, which a supervised session
    # hands to Sophia rather than to Hagia.
    check node["event"].getStr() == "projection"
    let firstSequence = node["sequence"].getInt()
    recordEvidence(
      EvidenceEvent(
        kind: EvidenceKind.settlement, event: "projection", status: "second"
      )
    )
    let records = readFile(path).strip().splitLines()
    check parseJson(records[^1])["sequence"].getInt() == firstSequence + 1
    check not node.hasKey("application")
    check not node.hasKey("sophia_handle")
    check getFilePermissions(path) == {fpUserRead, fpUserWrite}
    writeFile(path, repeat('x', int(maxEvidenceBytes)))
    recordEvidence(EvidenceEvent(kind: EvidenceKind.connection, status: "rotated"))
    check fileExists(path & ".1")
    check parseJson(readFile(path).strip())["status"].getStr() == "rotated"

suite "WM-owned profile validation":
  test "policy settings retain workspace identities and accept their bounds":
    let directory = createTempDir("hagia-policy-owner-", "")
    defer:
      removeDir(directory)
    let path = directory / "config.kdl"
    for policy in [
      "scratchpad-size 10 100; floating-size 0 10; column-width-presets 5 95;",
      "scratchpad-size 70 60; floating-size 100 0; column-width-presets 33 50 67;",
      "view-name 1 \"code\"; view-name 2 \"web\"; view-layout 1 \"dwindle\"; view-layout 2 \"split-tree\";",
    ]:
      writeFile(path, "schema 1\npolicy { " & policy & " }\n")
      path.ownerOnly()
      let candidate = loadDesktopProfile(path).candidates[ProfileAuthority.policy]
      discard initPolicyAdapter(candidate)
      if policy.startsWith("view-name"):
        check candidate.values[0].key == "policy.view-name.1"
        check candidate.values[1].key == "policy.view-name.2"

  test "malformed and unknown settings fail in the owning WM":
    let directory = createTempDir("hagia-policy-invalid-", "")
    defer:
      removeDir(directory)
    let path = directory / "config.kdl"
    for policy in [
      "scratchpad-size 0 60;",
      "scratchpad-size 9 60;",
      "scratchpad-size 70 101;",
      "scratchpad-size 70;",
      "floating-size 1 0;",
      "floating-size -1 60;",
      "column-width-presets;",
      "column-width-presets 4 50;",
      "column-width-presets 50 96;",
      "column-width-presets 5 10 15 20 25 30 35 40 45;",
      "column-width-presets \"50\";",
      "column-width-presets 50 extra=1;",
      "view-name 0 \"code\";",
      "view-name 10 \"code\";",
      "view-name 1 \" code\";",
      "view-name 1 \"\";",
      "view-name 1 \"" & repeat("x", 33) & "\";",
      "view-name 1 \"a\"; view-name 1 \"b\";",
      "view-layout 1 \"unknown\";",
      "view-layout 10 \"tile\";",
      "view-layout 1 \"tile\"; view-layout 1 \"grid\";",
      "future-wm-setting 1;",
      "layout \"unknown\";",
      "layout-cycle \"i3\" \"split-tree\";",
      "outer-gap 513;",
    ]:
      writeFile(path, "schema 1\npolicy { " & policy & " }\n")
      path.ownerOnly()
      expect DesktopProfileError:
        let candidate = loadDesktopProfile(path).candidates[ProfileAuthority.policy]
        discard initPolicyAdapter(candidate)
