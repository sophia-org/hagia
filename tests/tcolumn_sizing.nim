import std/[options, os, strutils, tempfiles, unittest]
import config/[policy_candidate, profile]
import policy/[entity_store, projection, state]
import types/[config_values, core, model, projection]
import state/values
import systems/layout

## Column and row sizing as a profile states it. niri spells a size as either
## `{ proportion N }` or `{ fixed N }`; the first is a share of the room a
## column can occupy and rescales with the output, the second is logical
## pixels and does not. These pin that difference, and the settings that had
## no parsing test at all before the vocabulary moved.

proc policyCandidate(values: openArray[(string, string)]): AuthorityCandidate =
  result = AuthorityCandidate(
    authority: ProfileAuthority.policy, generation: 1, digest: repeat('a', 64)
  )
  for (name, encoded) in values:
    result.values.add(ProfileValue(key: "policy." & name, encoded: encoded))

proc sizingModel(
    candidate: AuthorityCandidate,
    bounds = Rect(width: 2560, height: 1440),
    windows = 3,
    constraints = SizeConstraints(),
): PolicyModel =
  result = initPolicyModel()
  result.applyPolicyCandidate(candidate)
  let output = result.addOutput(bounds)
  for _ in 0 ..< windows:
    discard result.addWindow(
      output,
      WindowCapabilities(
        movable: true, resizable: true, focusable: true, fullscreenable: true
      ),
      constraints,
    )
  result.setFocus(output, WindowId(1))

proc widths(model: PolicyModel): seq[int32] =
  let (outer, inner) = model.effectiveGaps()
  for placement in model.projectLayout([OutputId(1)], outer, inner)[0].placements:
    result.add(placement.geometry.width)

proc loadedSettings(body: string): PolicySettings =
  ## What a profile actually resolves to, through the file loader rather than a
  ## hand-built candidate, so the grammar is exercised where an operator meets
  ## it.
  let directory = createTempDir("hagia-sizing-", "")
  defer:
    removeDir(directory)
  let path = directory / "config.kdl"
  writeFile(path, "schema 1\npolicy { " & body & " }\n")
  path.setFilePermissions({fpUserRead, fpUserWrite})
  loadDesktopProfile(path).candidates[ProfileAuthority.policy].policyCandidateSettings()

suite "column sizing vocabulary":
  test "a proportion resolves to the width the percentage it replaced did":
    ## The conversion is the reason a profile can be rewritten without anything
    ## moving: `proportion 0.5` truncates to the same Q16.16 scale `50` did.
    let settings = loadedSettings("default-column-width { proportion 0.5; }")
    check settings.defaultColumnWidth == proportionExtent(scaleFromRatio(50, 100))
    check settings.defaultColumnWidth == proportionExtent(Scale(32768))

    let model = sizingModel(
      policyCandidate(
        [
          ("gaps", "gaps 8"),
          ("default-column-width", "default-column-width { proportion 0.5; }"),
        ]
      )
    )
    # (2560 - 8) / 2 - 8, the same arithmetic niri uses.
    check model.widths()[0] == 1268

  test "a fixed size is pixels, taking neither the base nor the gap":
    let model = sizingModel(
      policyCandidate(
        [
          ("gaps", "gaps 8"),
          ("default-column-width", "default-column-width { fixed 1280; }"),
        ]
      )
    )
    # Exactly 1280, not 1280 - 8: a fixed extent is already a size.
    check model.widths()[0] == 1280

  test "a fixed size does not move when the output does":
    ## The property that makes "fixed" mean anything. A proportion is included
    ## beside it so the test fails if both stop responding to the output.
    for bounds in [Rect(width: 2560, height: 1440), Rect(width: 1920, height: 1080)]:
      let fixed = sizingModel(
        policyCandidate(
          [
            ("gaps", "gaps 8"),
            ("default-column-width", "default-column-width { fixed 1280; }"),
          ]
        ),
        bounds,
      )
      check fixed.widths()[0] == 1280
    let wide = sizingModel(
      policyCandidate(
        [
          ("gaps", "gaps 8"),
          ("default-column-width", "default-column-width { proportion 0.5; }"),
        ]
      ),
      Rect(width: 2560, height: 1440),
    )
    let narrow = sizingModel(
      policyCandidate(
        [
          ("gaps", "gaps 8"),
          ("default-column-width", "default-column-width { proportion 0.5; }"),
        ]
      ),
      Rect(width: 1920, height: 1080),
    )
    check wide.widths()[0] != narrow.widths()[0]

  test "a client minimum still outranks a fixed request":
    ## A proportion is a preference and a fixed extent a stronger one, but a
    ## minimum is a fact: a column narrower than its window would leave the
    ## window overflowing it.
    let tall = sizingModel(
      policyCandidate(
        [
          ("gaps", "gaps 8"),
          ("default-column-width", "default-column-width { fixed 1280; }"),
        ]
      ),
      constraints = SizeConstraints(minWidth: 1500, minHeight: 100),
    )
    check tall.widths()[0] == 1500
    let capped = sizingModel(
      policyCandidate(
        [
          ("gaps", "gaps 8"),
          ("default-column-width", "default-column-width { fixed 1280; }"),
        ]
      ),
      constraints = SizeConstraints(maxWidth: 900, maxHeight: 2000),
    )
    check capped.widths()[0] == 900

  test "the preset cycle walks proportions and fixed sizes in pixel order":
    ## Mixed kinds share no common scale, so the cycle compares in pixels. The
    ## list is deliberately out of pixel order in its fixed entry to prove the
    ## comparison is on resolved width rather than on position.
    var model = sizingModel(
      policyCandidate(
        [
          ("gaps", "gaps 8"),
          ("default-column-width", "default-column-width { proportion 0.5; }"),
          (
            "preset-column-widths",
            "preset-column-widths { proportion 0.25; fixed 1280; proportion 0.75; }",
          ),
        ]
      )
    )
    let column = model.window(WindowId(1)).get().column
    # The column is showing 1268 at the 0.5 default. Resolved, the presets are
    # 630, 1280 and 1906 pixels, so the first one wider than what is showing is
    # the fixed entry -- which a comparison in scale space could not reach at
    # all, because a fixed extent has no scale to compare.
    model.cycleColumnWidthPreset(OutputId(1), 1)
    check model.columns[column].width == fixedExtent(1280)
    # Stored as written, so it stays fixed rather than becoming a proportion of
    # whichever output happened to be current when the key was pressed.
    check model.widths()[0] == 1280
    model.cycleColumnWidthPreset(OutputId(1), 1)
    check model.columns[column].width == proportionExtent(scaleFromProportion(0.75))
    model.cycleColumnWidthPreset(OutputId(1), 1)
    check model.columns[column].width == proportionExtent(scaleFromProportion(0.25))
    model.cycleColumnWidthPreset(OutputId(1), -1)
    check model.columns[column].width == proportionExtent(scaleFromProportion(0.75))
    model.validate()

  test "row keys inherit the column ones and override them by axis":
    let inherited = loadedSettings("default-column-width { proportion 0.5; }")
    check inherited.defaultRowHeight == automaticExtent
    check inherited.presetRowHeights.len == 0

    let stated = loadedSettings(
      "default-row-height { proportion 0.4; }; " &
        "preset-row-heights { proportion 0.25; fixed 720; }"
    )
    check stated.defaultRowHeight == proportionExtent(scaleFromProportion(0.4))
    check stated.presetRowHeights ==
      @[proportionExtent(scaleFromProportion(0.25)), fixedExtent(720)]

  test "the divergent centring defaults are what this profile actually ships":
    ## Both keys exist in niri with the opposite default. Pinning them here is
    ## what keeps a deliberate divergence from becoming an accidental one.
    let bare = loadedSettings("layout \"scroller\"")
    check bare.centerFocusedColumn == CenterFocusedColumn.onOverflow
    check bare.alwaysCenterSingleColumn

    for mode in ["never", "always", "on-overflow"]:
      discard loadedSettings("center-focused-column \"" & mode & "\"")
    check loadedSettings("center-focused-column \"never\"").centerFocusedColumn ==
      CenterFocusedColumn.never
    check not loadedSettings("always-center-single-column #false").alwaysCenterSingleColumn

  test "a retired spelling is answered with the one that replaced it":
    for (retired, replacement) in retiredPolicySettings:
      var message = ""
      try:
        discard loadedSettings(retired & " 33 50 67")
      except DesktopProfileError as err:
        message = err.msg
      check replacement in message

  test "malformed sizes fail closed":
    for body in [
      "default-column-width 50", # the percentage form it replaced
      "default-column-width",
      "default-column-width { }",
      "default-column-width { proportion 0.5; fixed 100; }",
      "default-column-width { percent 50; }",
      "default-column-width { proportion 0.5 extra=1; }",
      "default-column-width { proportion; }",
      "default-column-width { proportion 0.5 0.6; }",
      "default-column-width { proportion 0.0; }",
      "default-column-width { proportion -0.5; }",
      "default-column-width { proportion 0.01; }",
      "default-column-width { proportion 11.0; }",
      "default-column-width { proportion \"0.5\"; }",
      "default-column-width { fixed 0; }",
      "default-column-width { fixed -10; }",
      "default-column-width { fixed 99999; }",
      "default-column-width { fixed 0.5; }",
      "default-column-width { fixed 1280 { nested 1; } }",
      "preset-column-widths",
      "preset-column-widths { }",
      "preset-column-widths 33 50 67",
      "preset-row-heights { proportion 0.1; proportion 0.2; proportion 0.3; " &
        "proportion 0.4; proportion 0.5; proportion 0.6; proportion 0.7; " &
        "proportion 0.8; proportion 0.9; }",
    ]:
      expect DesktopProfileError:
        discard loadedSettings(body)
