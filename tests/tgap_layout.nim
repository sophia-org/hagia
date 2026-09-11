import std/[json, os, strutils, tempfiles, unittest]
import config/[migration, policy_candidate, profile]
import policy/[projection, state]
import types/[config_values, core, model, projection]
import sophia/policy_adapter

proc gapCandidate(gap: int32, struts = LayoutStruts()): AuthorityCandidate =
  AuthorityCandidate(
    authority: ProfileAuthority.policy,
    generation: 1,
    digest: repeat('a', 64),
    values: @[
      ProfileValue(key: "policy.gaps", encoded: "gaps " & $gap),
      ProfileValue(
        key: "policy.struts",
        encoded:
          "struts { left " & $struts.left & "; right " & $struts.right & "; top " &
          $struts.top & "; bottom " & $struts.bottom & "; }",
      ),
    ],
  )

proc stripModel(bounds: Rect, vertical = false): PolicyModel =
  result = initPolicyModel()
  result.applyPolicyCandidate(gapCandidate(8))
  let output = result.addOutput(bounds)
  if vertical:
    result.setLayout(output, LayoutMode.verticalScroller)
  for i in 0 .. 2:
    discard result.addWindow(
      output,
      WindowCapabilities(
        movable: true, resizable: true, focusable: true, fullscreenable: true
      ),
      SizeConstraints(),
    )
  result.setFocus(output, WindowId(1))

proc projected(model: PolicyModel): LogicalOutputProjection =
  let (outer, inner) = model.effectiveGaps()
  model.projectLayout(
    [OutputId(1)],
    outer,
    inner,
    physicalBounds = [(OutputId(1), Rect(width: 2560, height: 1440))],
  )[0]

proc geometry(projected: LogicalOutputProjection, id: uint32): Rect =
  for placement in projected.placements:
    if placement.window == WindowId(id):
      return placement.geometry
  raise newException(ValueError, "missing placement")

suite "uniform gaps and explicit struts":
  test "half-width columns meet monitor edges without a forced neighbor sliver":
    var model = stripModel(Rect(y: 32, width: 2560, height: 1408))
    let layout = model.projected()
    check layout.geometry(1) == Rect(x: 8, y: 40, width: 1268, height: 1392)
    check layout.geometry(2) == Rect(x: 1284, y: 40, width: 1268, height: 1392)
    check layout.geometry(3).x == 2560
    # Navigation may leave a partial neighbor visible; the gap model removes
    # the forced inset, not the ordinary scrolling strip.
    model.rememberViewportOffset(OutputId(1), layout.viewportOffset, layout.camera)
    model.setFocus(OutputId(1), WindowId(3))
    let moved = model.projected()
    check moved.geometry(1).x + moved.geometry(1).width == 0
    check moved.geometry(3).x + moved.geometry(3).width == 2552

  test "vertical scrolling transposes gaps and asymmetric struts once":
    var model = stripModel(Rect(x: -1440, y: 32, width: 1440, height: 2560), true)
    let layout = model.projected()
    check layout.geometry(1) == Rect(x: -1432, y: 40, width: 1424, height: 1268)
    check layout.geometry(3).y == 2592
    model.applyPolicyCandidate(
      gapCandidate(8, LayoutStruts(left: 12, right: 20, top: 8, bottom: 8))
    )
    let inset = model.projected()
    check inset.geometry(1) == Rect(x: -1420, y: 48, width: 1392, height: 1260)
    check inset.geometry(3).y == 2584

  test "side struts opt into edge previews and vertical struts add space":
    var model = stripModel(Rect(y: 32, width: 2560, height: 1408))
    model.applyPolicyCandidate(
      gapCandidate(8, LayoutStruts(left: 8, right: 8, top: 12, bottom: 20))
    )
    let layout = model.projected()
    check layout.geometry(1) == Rect(x: 16, y: 52, width: 1260, height: 1360)
    check layout.geometry(3).x == 2552

  test "gap actions preserve struts and clamp the single configured gap":
    var model = stripModel(Rect(width: 2560, height: 1440))
    let struts = LayoutStruts(left: 8, right: 8, top: 12, bottom: 20)
    model.applyPolicyCandidate(gapCandidate(8, struts))
    model.toggleGaps()
    check model.projected().geometry(1) == Rect(x: 8, y: 12, width: 1272, height: 1408)
    model.adjustGaps(1)
    check model.settings.gaps == 10
    check model.settings.gapsEnabled
    check model.settings.struts == struts
    model.adjustGaps(1000)
    check model.settings.gaps == maxGap
    model.adjustGaps(-1000)
    check model.settings.gaps == 0
    check model.settings.struts == struts

  test "M respects gaps and struts while F and fullscreen keep their bounds":
    var model = stripModel(Rect(y: 32, width: 2560, height: 1408))
    model.applyPolicyCandidate(
      gapCandidate(8, LayoutStruts(left: 12, right: 20, top: 24, bottom: 32))
    )
    model.toggleColumnMaximized(OutputId(1))
    check model.projected().geometry(1) == Rect(x: 20, y: 64, width: 2512, height: 1336)
    model.toggleFocusedMaximized()
    let edge = model.projected()
    check edge.geometry(1) == Rect(y: 32, width: 2560, height: 1408)
    check edge.placements.len == 1
    model.toggleFocusedFullscreen()
    check model.projected().geometry(1) == Rect(width: 2560, height: 1440)

  test "other native and tree layouts reserve struts once":
    var model = stripModel(Rect(y: 32, width: 2560, height: 1408))
    model.applyPolicyCandidate(
      gapCandidate(8, LayoutStruts(left: 12, right: 20, top: 24, bottom: 32))
    )
    for mode in [LayoutMode.monocle, LayoutMode.frameTree]:
      model.setLayout(OutputId(1), mode)
      let rect = model.projected().geometry(1)
      check rect.x >= 20
      check rect.y >= 64
      check rect.x + rect.width <= 2532
      check rect.y + rect.height <= 1400

  test "checkpoint keeps new settings and v15 restores exact legacy spacing":
    let candidate = gapCandidate(8, LayoutStruts(left: 12, bottom: 20))
    let adapter = initPolicyAdapter(candidate)
    check restoreCheckpointPayload(adapter.checkpointPayload()).model.settings ==
      candidate.policyCandidateSettings()
    var legacy = parseJson(adapter.checkpointPayload().split('\n', 1)[1])
    legacy["schema"] = %15
    legacy["settings"]["outerGap"] = %8
    legacy["settings"]["innerGap"] = %8
    for key in ["gapModel", "gaps", "struts"]:
      legacy["settings"].delete(key)
    let restored = restoreCheckpointPayload("HAGIA-POLICY-CHECKPOINT-15\n" & $legacy)
    check restored.model.settings.gapModel == GapModel.legacy
    var model = stripModel(Rect(y: 32, width: 2560, height: 1408))
    model.settings = restored.model.settings
    check model.projected().geometry(1) == Rect(x: 16, y: 40, width: 1260, height: 1392)
    check model.projected().geometry(3).x == 2552

  test "profile rejects ambiguous or malformed gap definitions":
    let directory = createTempDir("hagia-gap-profile-", "")
    defer:
      removeDir(directory)
    let path = directory / "config.kdl"
    for body in [
      "gaps -1;", "gaps 513;", "gaps 2147483648;", "gaps 1.5;", "gaps \"8\";",
      "gaps 8 extra=1;", "gaps 8 { left 1; }", "gaps 8; gaps 9;",
      "gaps 8; outer-gap 8;", "inner-gap 8; gaps 8;", "struts { left 8; }",
      "gaps 8; struts 8;", "gaps 8; struts { left -1; }",
      "gaps 8; struts { left 513; }", "gaps 8; struts { left 8; left 9; }",
      "gaps 8; struts { sideways 1; }", "gaps 8; struts { left 8 extra=1; }",
      "gaps 8; struts { left 8 { top 1; } }",
    ]:
      writeFile(path, "schema 1\npolicy { " & body & " }\n")
      setFilePermissions(path, {fpUserRead, fpUserWrite})
      expect DesktopProfileError:
        discard loadDesktopProfile(path).candidates[ProfileAuthority.policy].policyCandidateSettings()
    writeFile(path, "schema 1\npolicy { struts { left 8; bottom 20; }; gaps 8; }\n")
    let settings = loadDesktopProfile(path).candidates[ProfileAuthority.policy].policyCandidateSettings()
    check settings.gaps == 8
    check settings.struts == LayoutStruts(left: 8, bottom: 20)

  test "Triad gap migration emits the uniform model":
    let migrated = migrateTriadProfile("layout { gaps 8; }")
    check migrated.outputProfile.contains("gaps 8")
    check not migrated.outputProfile.contains("outer-gap")
