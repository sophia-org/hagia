suite "output return focus custody":
  test "return removes migrated windows from the fallback focus history":
    for migratedIsFocused in [false, true]:
      var model = initPolicyModel()
      let fallback = model.addOutput(Rect(width: 1000, height: 700))
      let returning = model.addOutput(Rect(x: 1000, width: 1000, height: 700))
      let stationary =
        model.addWindow(fallback, focusableCapabilities(), SizeConstraints())
      let migrated =
        model.addWindow(returning, focusableCapabilities(), SizeConstraints())
      model.setFocus(returning, migrated)
      discard model.removeOutput(returning, fallback)
      model.setFocus(fallback, stationary)
      model.setFocus(fallback, migrated)
      if not migratedIsFocused:
        model.setFocus(fallback, stationary)
      let stationaryHistory =
        model.outputs[fallback].focusHistory.filterIt(it != migrated)
      model.validate()

      model.restoreOutput(returning, Rect(x: 1000, width: 1000, height: 700))

      check model.outputs[fallback].focusHistory == stationaryHistory
      check model.outputs[fallback].focusedWindow ==
        (if migratedIsFocused: nullWindowId else: stationary)
      check model.outputs[returning].focusedWindow == migrated
      check model.window(migrated).get().homeOutput == returning
      model.validate()

  test "hidden migrated window can return after a checkpoint restart":
    for restarted in [false, true]:
      var adapter = initPolicyAdapter(assignedCandidate())
      let left = SnapshotOutput(
        output: 10, generation: 1, policyKey: 1, width: 1000, height: 700
      )
      let right = SnapshotOutput(
        output: 20, generation: 1, policyKey: 2, width: 1000, height: 700
      )
      var scene = snapshot(1, @[left, right], @[surface(1, 10), surface(2, 20)])
      scene.outputs[0].focusIndex = 1
      scene.outputs[0].focusGeneration = 1
      scene.outputs[1].focusIndex = 2
      scene.outputs[1].focusGeneration = 1
      adapter.reconcile(scene)
      let original = adapter.logicalWindow(1, 1).get()
      let returning = adapter.logicalWindow(2, 1).get()
      let owner = adapter.logicalOutput(20).get()

      scene.generation = 2
      scene.outputs.setLen(1)
      scene.outputs[0].focusIndex = 2
      scene.surfaces[1].currentOutput = 10
      adapter.reconcile(scene)
      adapter.applyCause(workspaceAction(scene, 4))
      scene.generation = 3
      scene.surfaces[0].currentOutput = 0
      adapter.reconcile(scene)
      adapter.applyCause(workspaceAction(scene, 1))
      scene.generation = 4
      scene.surfaces[0].currentOutput = 10
      scene.surfaces[1].currentOutput = 0
      scene.outputs[0].focusIndex = 1
      adapter.reconcile(scene)
      let fallback = adapter.logicalOutput(10).get()
      check returning in adapter.model().outputs[fallback].focusHistory
      if restarted:
        adapter = restoreCheckpointPayload(adapter.checkpointPayload())

      scene.generation = 5
      var returned = right
      returned.generation = 2
      scene.outputs.add(returned)
      # Hidden windows have no committed placement. The restored affinity,
      # rather than a current placement on the fallback, chooses their home.
      scene.surfaces[1].currentOutput = 0
      adapter.reconcile(scene)

      check adapter.logicalWindow(1, 1).get() == original
      check adapter.logicalWindow(2, 1).get() == returning
      check adapter.model().window(returning).get().homeOutput == owner
      check returning notin
        adapter.model().outputs[adapter.logicalOutput(10).get()].focusHistory
      adapter.model().validate()
