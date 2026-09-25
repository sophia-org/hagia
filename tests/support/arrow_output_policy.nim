## Sophia t080: policy settings survive restart, while a new profile wins on reload.
proc arrowOutputCandidate(generation: uint64, value: string): AuthorityCandidate =
  result = AuthorityCandidate(
    authority: ProfileAuthority.policy, generation: generation, digest: repeat('a', 64)
  )
  if value.len > 0:
    result.values.add(
      ProfileValue(
        key: "policy.arrow-crosses-outputs", encoded: "arrow-crosses-outputs " & value
      )
    )

suite "directional output policy checkpoint and reload":
  test "checkpoint retains opt out and reload preserves monitor state":
    var adapter = initPolicyAdapter(arrowOutputCandidate(2, "#false"))
    adapter.reconcile(twoOutputScene(1))
    var restored = adapter.checkpointPayload().restoreCheckpointPayload()
    check not restored.model().settings.arrowCrossesOutputs
    restored.reconcile(twoOutputScene(2))
    let before = restored.model()
    for value in ["#true", "#false", ""]:
      restored.applyPolicyCandidate(arrowOutputCandidate(3, value))
      let after = restored.model()
      check after.settings.arrowCrossesOutputs == (value != "#false")
      check after.activeOutput == before.activeOutput
      for output in before.outputOrder:
        check after.outputs[output].focusedWindow == before.outputs[output].focusedWindow
        check after.outputs[output].activeView == before.outputs[output].activeView
        check after.outputs[output].focusHistory == before.outputs[output].focusHistory
      check restored
        .checkpointPayload()
        .restoreCheckpointPayload()
        .model().settings.arrowCrossesOutputs == (value != "#false")

  test "version 18 checkpoints retain the historical enabled default":
    var adapter = initPolicyAdapter(arrowOutputCandidate(2, "#false"))
    adapter.reconcile(twoOutputScene(1))
    var payload = parseJson(adapter.checkpointPayload().dumpCheckpointJson())
    payload["schema"] = %18
    payload["settings"].delete("arrowCrossesOutputs")
    let restored = restoreCheckpointPayload("HAGIA-POLICY-CHECKPOINT-18\n" & $payload)
    check restored.model().settings.arrowCrossesOutputs
    check restored.checkpointPayload().startsWith("HAGIA-POLICY-CHECKPOINT-19\n")
