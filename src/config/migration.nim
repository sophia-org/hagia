import std/[os, sets, strutils]

import kdl

import ./[migration_common, migration_output, profile]

export migration_common

type CommandMigration = object
  authority: string
  disposition: MigrationDisposition
  result: string
  outputCommand: string

proc commandMigration(
    authority: string,
    disposition: MigrationDisposition,
    outcome: string,
    outputCommand = "",
): CommandMigration =
  CommandMigration(
    authority: authority,
    disposition: disposition,
    result: outcome,
    outputCommand: outputCommand,
  )

proc commandArgument(command, prefix: string): string =
  if command.startsWith(prefix) and command.len > prefix.len:
    result = command[prefix.len .. ^1].strip()

proc boundedWorkspaceCommand(command, prefix: string): bool =
  let argument = command.commandArgument(prefix)
  if argument.len == 0:
    return false
  try:
    result = parseInt(argument) in 1 .. 9
  except ValueError:
    result = false

proc classifyTriadCommand(command: string): CommandMigration =
  ## The shortcut authority owns the physical match. This classification owns
  ## the distinct fact of which least-authority participant may execute the
  ## resulting semantic command.
  case command
  of "close-window":
    commandMigration(
      "session", MigrationDisposition.transformed, "opaque close-focused capability",
      "close-window",
    )
  of "exit-session":
    commandMigration(
      "session", MigrationDisposition.transformed, "opaque logout capability", "logout"
    )
  of "spawn-terminal":
    commandMigration(
      "session", MigrationDisposition.transformed, "opaque terminal capability",
      "spawn-terminal",
    )
  of "spawn kitty":
    commandMigration(
      "session", MigrationDisposition.transformed, "declared terminal capability",
      "spawn-terminal",
    )
  of "spawn helium":
    commandMigration(
      "session", MigrationDisposition.transformed, "declared browser capability",
      "spawn-browser",
    )
  of "lock-session", "toggle-keyboard-shortcuts-inhibit":
    commandMigration(
      "session", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; requires a dedicated security transition capability",
    )
  of "triad-reload":
    commandMigration(
      "session", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; watched reload requires a cross-authority recovery protocol",
    )
  of "select-window":
    commandMigration(
      "session", MigrationDisposition.transformed, "bounded generic window switcher",
      "window-switcher",
    )
  of "toggle-hotkey-overlay", "toggle-overview", "focus-shell-ui", "close-overview",
      "recent-window-next", "recent-window-prev", "recent-window-next --filter app-id",
      "recent-window-prev --filter app-id", "focus-window-or-workspace-down",
      "focus-window-or-workspace-up":
    commandMigration(
      "shell", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; requires broader shell state or MRU semantics",
    )
  of "screenshot", "screenshot-screen", "screenshot-window",
      "screenshot --clipboard-only", "screenshot --show-pointer",
      "screenshot --no-clipboard --hide-pointer",
      "screenshot --clipboard-only --hide-pointer":
    commandMigration(
      "portal", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; requires an explicit capture portal grant",
    )
  of "toggle-fullscreen", "fullscreen-window":
    commandMigration(
      "policy", MigrationDisposition.transformed, "toggleFullscreen policy action",
      "toggle-fullscreen",
    )
  of "toggle-maximized", "maximize-column", "maximize-window-to-edges":
    commandMigration(
      "policy", MigrationDisposition.transformed, "toggleMaximized policy action",
      "toggle-maximized",
    )
  of "minimize":
    commandMigration(
      "policy", MigrationDisposition.retained, "minimizeFocused policy action", command
    )
  of "restore-minimized":
    commandMigration(
      "policy", MigrationDisposition.retained, "restoreMinimized policy action", command
    )
  of "toggle-floating":
    commandMigration(
      "policy", MigrationDisposition.retained, "toggleFloating policy action", command
    )
  of "focus-next":
    commandMigration(
      "policy", MigrationDisposition.retained, "focusNext policy action", command
    )
  of "focus-prev":
    commandMigration(
      "policy", MigrationDisposition.retained, "focusPrevious policy action", command
    )
  of "focus-tag-right":
    commandMigration(
      "policy", MigrationDisposition.transformed, "viewNext policy action",
      "focus-view-next",
    )
  of "focus-occupied-tag-right":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "focusNextOccupiedWorkspace policy action", "focus-occupied-workspace-next",
    )
  of "move-to-scratchpad":
    commandMigration(
      "policy", MigrationDisposition.retained, "moveToScratchpad policy action", command
    )
  of "toggle-scratchpad":
    commandMigration(
      "policy", MigrationDisposition.retained, "toggleScratchpad policy action", command
    )
  of "restore-scratchpad":
    commandMigration(
      "policy", MigrationDisposition.retained, "restoreScratchpad policy action",
      command,
    )
  of "switch-layout":
    commandMigration(
      "policy", MigrationDisposition.retained, "switchLayout policy action", command
    )
  of "new-workspace":
    commandMigration(
      "policy", MigrationDisposition.retained, "newWorkspace policy action", command
    )
  of "consume-window":
    commandMigration(
      "policy", MigrationDisposition.transformed, "consumeNextColumn policy action",
      command,
    )
  of "expel-window":
    commandMigration(
      "policy", MigrationDisposition.transformed, "expelFocusedWindow policy action",
      command,
    )
  of "resize-width -0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "shrinkColumn policy action", command
    )
  of "resize-width 0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "growColumn policy action", command
    )
  of "resize-height -0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "shrinkWindow policy action", command
    )
  of "resize-height 0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "growWindow policy action", command
    )
  of "move", "resize":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "Engine-owned completed pointer interaction", command,
    )
  else:
    if command.boundedWorkspaceCommand("focus-workspace "):
      return commandMigration(
        "policy", MigrationDisposition.transformed, "activateView policy action",
        command,
      )
    if command.boundedWorkspaceCommand("move-to-workspace "):
      return commandMigration(
        "policy", MigrationDisposition.transformed, "moveToView policy action", command
      )
    if command.startsWith("spawn "):
      return commandMigration(
        "session", MigrationDisposition.excluded,
        "excluded from the WM freeze profile; arbitrary launch requires a declared application capability",
      )
    if command.startsWith("switch-shell ") or command == "cycle-shell":
      return commandMigration(
        "shell", MigrationDisposition.excluded,
        "excluded from the WM freeze profile; requires a bounded shell selection capability",
      )
    let parts = command.splitWhitespace()
    if parts.len == 0:
      return commandMigration(
        "unowned", MigrationDisposition.unsupported, "command must not be empty"
      )
    let name = parts[0]
    if name.startsWith("split-tree-") or name.startsWith("frame-"):
      return commandMigration(
        "policy", MigrationDisposition.excluded,
        "excluded from the WM freeze profile; structural layout command belongs to a later policy and shell tranche",
      )
    if name in [
      "adjust-gaps", "adjust-master-count", "adjust-master-ratio", "center-tile",
      "deck", "dwindle", "dwindle-split-down", "dwindle-split-left",
      "dwindle-split-right", "dwindle-split-up", "focus-column-first",
      "focus-column-last", "focus-down", "focus-last", "focus-left",
      "focus-next-in-group", "focus-right", "focus-up", "frame-split-horizontal",
      "frame-split-vertical", "frame-tab-next", "frame-tab-prev", "frame-unsplit",
      "grid", "group-windows", "i3", "monocle", "move-column-left", "move-column-right",
      "move-column-to-first", "move-column-to-last", "move-to-named-scratchpad",
      "move-to-tag-left", "move-to-tag-right", "move-window-down", "move-window-left",
      "move-window-right", "move-window-up", "move-workspace-to-output", "notion",
      "right-tile", "scroller", "spiral", "split-tree-layout-stacking",
      "split-tree-layout-tabbed", "split-tree-layout-toggle-split",
      "split-tree-split-horizontal", "split-tree-split-vertical", "swap-to-tag",
      "tgmix", "tile", "toggle-gaps", "toggle-named-scratchpad", "ungroup-window",
      "vertical-grid", "zoom",
    ]:
      return commandMigration(
        "policy", MigrationDisposition.excluded,
        "historical spatial command is not selected by the checked-in freeze profile",
      )
    commandMigration(
      "unowned", MigrationDisposition.unsupported,
      "command has no classified retained authority",
    )

proc bindingKind(name: string): MigrationBindingKind =
  case name
  of "bind": MigrationBindingKind.key
  of "pointer-bind": MigrationBindingKind.pointer
  of "axis-bind": MigrationBindingKind.axis
  of "gesture-bind": MigrationBindingKind.gesture
  of "switch-bind": MigrationBindingKind.switch
  else: MigrationBindingKind.none

proc bindingContext(node: KdlNode, inherited: string): string =
  result = inherited
  for key, value in node.props.pairs:
    if key == "mode" and value.kind == KString:
      result = "mode:" & value.kString()

proc collectPhysicalBindings(
    node: KdlNode,
    path, inheritedContext: string,
    ordinal: var int,
    emitted: var HashSet[string],
    shortcutSettings: var seq[string],
    report: var MigrationReport,
) =
  let kind = node.name.bindingKind()
  if kind != MigrationBindingKind.none:
    inc ordinal
    let source = path & "." & node.name & "[" & $ordinal & "]"
    var item = MigrationItem(
      kind: MigrationItemKind.physicalBinding,
      source: source,
      settingAuthority: "shortcut",
      bindingKind: kind,
      context: node.bindingContext(inheritedContext),
    )
    if node.args.len < 2 or node.args[0].kind != KString or node.args[1].kind != KString:
      item.authority = "shortcut"
      item.disposition = MigrationDisposition.unsupported
      item.result = "binding requires string trigger and command arguments"
      report.items.add(item)
      return
    item.trigger = node.args[0].kString()
    item.command = node.args[1].kString()
    let migration = item.command.classifyTriadCommand()
    item.authority = migration.authority
    item.disposition = migration.disposition
    item.result = migration.result
    let reserved =
      kind == MigrationBindingKind.key and item.trigger.isReservedDesktopShortcut()
    let crossesPointerAuthority =
      kind == MigrationBindingKind.pointer and migration.authority != "policy"
    let unsupportedPointerAction =
      kind == MigrationBindingKind.pointer and
      migration.outputCommand notin ["move", "resize"]
    if reserved:
      item.disposition = MigrationDisposition.excluded
      item.result = migration.result & "; Sophia reserves this emergency chord"
    elif crossesPointerAuthority:
      item.disposition = MigrationDisposition.excluded
      item.result =
        migration.result &
        "; excluded because a pointer binding cannot cross into this authority"
    elif unsupportedPointerAction:
      item.disposition = MigrationDisposition.excluded
      item.result =
        migration.result &
        "; the freeze profile retains only move and resize pointer actions"
    let settingName =
      case kind
      of MigrationBindingKind.key: "bind"
      of MigrationBindingKind.pointer: "pointer-bind"
      else: ""
    let identity = settingName & ":" & item.trigger
    if migration.outputCommand.len > 0 and settingName.len > 0 and not reserved and
        not crossesPointerAuthority and not unsupportedPointerAction and
        item.context == "global" and identity notin emitted:
      shortcutSettings.add(
        "  " & settingName & " " & node.args[0].pretty() & " \"" & migration.authority &
          ":" & migration.outputCommand & "\""
      )
      emitted.incl(identity)
    elif migration.outputCommand.len > 0 and item.context != "global":
      item.disposition = MigrationDisposition.excluded
      item.result =
        migration.result &
        "; contextual shell modes are excluded from the freeze profile"
    elif migration.outputCommand.len > 0 and identity in emitted:
      item.disposition = MigrationDisposition.excluded
      item.result =
        migration.result &
        "; the freeze profile excludes this later duplicate shortcut identity"
    report.items.add(item)
    return

  var childContext = inheritedContext
  if node.name == "layout" and node.args.len > 0 and node.args[0].kind == KString:
    childContext = "layout:" & node.args[0].kString()
  let childPath =
    if path.len == 0:
      node.name
    else:
      path & "." & node.name
  for child in node.children:
    child.collectPhysicalBindings(
      childPath, childContext, ordinal, emitted, shortcutSettings, report
    )

proc physicalBindingCount*(report: MigrationReport): int =
  for item in report.items:
    if item.kind == MigrationItemKind.physicalBinding:
      inc result

proc reportField(value: string): string =
  value.multiReplace(("\\", "\\\\"), ("\t", "\\t"), ("\r", "\\r"), ("\n", "\\n"))

proc migrateXkb(
    node: KdlNode,
    settings: var seq[string],
    emitted: var HashSet[string],
    report: var MigrationReport,
) =
  report.add(
    "input.keyboard.xkb", "input", MigrationDisposition.retained,
    "input keyboard XKB candidate",
  )
  var children: seq[string]
  for child in node.children:
    let source = "input.keyboard.xkb." & child.name
    if child.name notin ["rules", "model", "layout", "variant", "options"]:
      report.unsupportedSetting(source, "input", "unsupported XKB setting")
      continue
    let minimum = if child.name == "layout": 1 else: 0
    let maximum = if child.name == "options": 256 else: 64
    let value = child.oneString(minimum, maximum)
    let outputKey = "xkb." & child.name
    if not value.valid:
      report.unsupportedSetting(source, "input", "value is outside Hagia XKB bounds")
    elif outputKey in emitted:
      report.unsupportedSetting(
        source, "input", "duplicate setting is ambiguous; no last-writer-wins migration"
      )
    else:
      children.add("            " & child.name & " " & value.encoded)
      emitted.incl(outputKey)
      report.add(source, "input", MigrationDisposition.retained, outputKey)
  if children.len > 0:
    settings.add("        xkb {\n" & children.join("\n") & "\n        }")

proc migrateKeyboard(
    node: KdlNode,
    settings: var seq[string],
    emitted: var HashSet[string],
    report: var MigrationReport,
) =
  report.add(
    "input.keyboard", "input", MigrationDisposition.retained, "input keyboard candidate"
  )
  var children: seq[string]
  for child in node.children:
    let source = "input.keyboard." & child.name
    case child.name
    of "repeat-rate":
      let value = child.oneInteger(1, 1_000)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "input", child.name, value.encoded,
          "input keyboard repeat rate",
        )
      else:
        report.unsupportedSetting(source, "input", "repeat rate must be in 1..1000")
    of "repeat-delay":
      let value = child.oneInteger(1, 10_000)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "input", child.name, value.encoded,
          "input keyboard repeat delay",
        )
      else:
        report.unsupportedSetting(source, "input", "repeat delay must be in 1..10000")
    of "numlock", "capslock":
      let value = child.oneBoolean(true)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "input", child.name, value.encoded,
          "explicit input keyboard lock state", MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(source, "input", "lock state requires a flag or bool")
    of "xkb":
      if child.args.len != 0 or child.props.len != 0:
        report.unsupportedSetting(source, "input", "XKB setting requires child values")
      elif "xkb" in emitted:
        report.unsupportedSetting(
          source, "input",
          "duplicate setting is ambiguous; no last-writer-wins migration",
        )
      else:
        emitted.incl("xkb")
        child.migrateXkb(children, emitted, report)
    else:
      report.unsupportedSetting(source, "input", "unsupported keyboard setting")
  if children.len > 0:
    settings.add("    keyboard {\n" & children.join("\n") & "\n    }")

proc migrateMouse(
    node: KdlNode,
    settings: var seq[string],
    emitted: var HashSet[string],
    report: var MigrationReport,
) =
  report.add(
    "input.mouse", "input", MigrationDisposition.transformed,
    "global Sophia pointer candidate",
  )
  var children: seq[string]
  for child in node.children:
    let source = "input.mouse." & child.name
    case child.name
    of "natural-scroll", "left-handed", "middle-emulation":
      let value = child.oneBoolean(true)
      if value.valid:
        report.emitSetting(
          children,
          emitted,
          source,
          "input",
          child.name,
          value.encoded,
          "input pointer " & child.name,
          MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(
          source, "input", "pointer setting requires a flag or bool"
        )
    of "accel-profile":
      let value = child.oneString(1, 16)
      if value.valid and value.value in ["flat", "adaptive"]:
        report.emitSetting(
          children, emitted, source, "input", child.name, value.encoded,
          "input pointer acceleration profile", MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(
          source, "input", "unsupported pointer acceleration profile"
        )
    of "accel-speed":
      let value = child.oneNumber(-1.0, 1.0)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "input", child.name, value.encoded,
          "input pointer acceleration speed", MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(
          source, "input", "acceleration speed must be in -1..1"
        )
    of "scroll-factor":
      let value = child.oneNumber(0.01, 10.0)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "input", child.name, value.encoded,
          "input pointer scroll factor", MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(source, "input", "scroll factor must be in 0.01..10")
    else:
      report.unsupportedSetting(
        source, "input", "input candidate does not support this pointer setting"
      )
  if children.len > 0:
    settings.add("    pointer {\n" & children.join("\n") & "\n    }")

proc migrateInput(
    node: KdlNode, settings: var seq[string], report: var MigrationReport
) =
  report.add(
    "input", "input", MigrationDisposition.transformed,
    "partitioned into the immutable Sophia input candidate",
  )
  var emitted = initHashSet[string]()
  var keyboardSeen = false
  var pointerSeen = false
  for child in node.children:
    case child.name
    of "keyboard":
      if keyboardSeen:
        report.unsupportedSetting(
          "input.keyboard", "input",
          "duplicate keyboard block is ambiguous; no last-writer-wins migration",
        )
      else:
        keyboardSeen = true
        child.migrateKeyboard(settings, emitted, report)
    of "mouse":
      if pointerSeen:
        report.unsupportedSetting(
          "input.mouse", "input",
          "duplicate mouse block is ambiguous; no last-writer-wins migration",
        )
      else:
        pointerSeen = true
        child.migrateMouse(settings, emitted, report)
    of "touchpad", "trackpoint", "trackball":
      report.unsupportedSetting(
        "input." & child.name,
        "input",
        "device-class-specific policy cannot be represented by the global pointer candidate",
      )
      for setting in child.children:
        report.unsupportedSetting(
          "input." & child.name & "." & setting.name,
          "input",
          "device-class-specific input setting is not yet representable",
        )
    else:
      report.unsupportedSetting(
        "input." & child.name, "input", "unsupported input setting"
      )

proc classifyTree(
    report: var MigrationReport,
    node: KdlNode,
    path, authority: string,
    disposition: MigrationDisposition,
    reason: string,
) =
  report.add(path, authority, disposition, reason)
  for child in node.children:
    report.classifyTree(child, path & "." & child.name, authority, disposition, reason)

proc migrateTriadProfile*(source: string): MigrationReport =
  var document: KdlDoc
  try:
    document = parseKdl(source)
  except CatchableError as error:
    raise newException(DesktopProfileError, "Triad profile syntax error: " & error.msg)
  var policySettings = @["  layout \"scroller\""]
  var viewCount = 9
  var shortcutSettings = @["  profile \"triad-migration\""]
  var sessionSettings: seq[string]
  var inputSettings = @["  inherit-sophia #true"]
  var outputSettings = @["  inherit-sophia #true"]
  var bindingOrdinal = 0
  var emittedBindings = initHashSet[string]()
  var workspaceSettings = initHashSet[string]()
  var sessionSettingsSeen = initHashSet[string]()
  var inputSeen = false
  var outputSeen = false
  for node in document:
    let rootContext = if node.name == "bindings": "global" else: node.name
    node.collectPhysicalBindings(
      "", rootContext, bindingOrdinal, emittedBindings, shortcutSettings, result
    )
    case node.name
    of "layout":
      result.add(
        "layout", "policy", MigrationDisposition.transformed, "scroller policy"
      )
      for child in node.children:
        case child.name
        of "gaps":
          if child.args.len == 1:
            policySettings.add("  outer-gap " & child.args[0].pretty())
            policySettings.add("  inner-gap " & child.args[0].pretty())
            result.add(
              "layout.gaps", "policy", MigrationDisposition.transformed,
              "outer-gap and inner-gap",
            )
          else:
            result.add(
              "layout.gaps", "policy", MigrationDisposition.unsupported,
              "invalid argument shape",
            )
        of "center-focused-column", "default-column-width":
          result.add(
            "layout." & child.name,
            "policy",
            MigrationDisposition.retained,
            "compiled scroller equivalent",
          )
          for setting in child.children:
            result.add(
              "layout." & child.name & "." & setting.name,
              "policy",
              MigrationDisposition.retained,
              "compiled scroller equivalent",
            )
        of "layout-cycle":
          var layouts: seq[string]
          var valid = child.args.len > 0 and child.args.len <= 5
          for argument in child.args:
            if argument.kind != KString or
                argument.kString() notin
                ["scroller", "tile", "grid", "monocle", "vertical-scroller"]:
              valid = false
            else:
              layouts.add(argument.pretty())
          if valid:
            policySettings.add("  layout-cycle " & layouts.join(" "))
            result.add(
              "layout.layout-cycle", "policy", MigrationDisposition.transformed,
              "native policy layout cycle",
            )
          else:
            result.add(
              "layout.layout-cycle", "policy", MigrationDisposition.unsupported,
              "contains an unavailable native layout",
            )
        else:
          result.classifyTree(
            child,
            "layout." & child.name,
            "policy",
            MigrationDisposition.unsupported,
            "not available in foundation milestone",
          )
    of "bindings":
      for child in node.children:
        if child.name == "mirror-hjkl-arrows":
          result.add(
            "bindings.mirror-hjkl-arrows", "shortcut", MigrationDisposition.unsupported,
            "requires deterministic shortcut expansion before candidate validation",
          )
    of "input":
      if inputSeen:
        result.classifyTree(
          node, "input", "input", MigrationDisposition.unsupported,
          "duplicate input block is ambiguous; no last-writer-wins migration",
        )
      else:
        inputSeen = true
        node.migrateInput(inputSettings, result)
    of "output":
      if outputSeen:
        result.classifyTree(
          node, "output", "output", MigrationDisposition.unsupported,
          "duplicate output block is ambiguous; no last-writer-wins migration",
        )
      else:
        outputSeen = true
        node.migrateOutput(outputSettings, result)
    of "scratchpad":
      result.classifyTree(
        node, "scratchpad", "policy", MigrationDisposition.unsupported,
        "scratchpad geometry is not yet configurable",
      )
    of "workspaces":
      result.add(
        "workspaces", "policy", MigrationDisposition.transformed,
        "bounded initial Hagia view policy",
      )
      for child in node.children:
        let source = "workspaces." & child.name
        if child.name in workspaceSettings:
          result.unsupportedSetting(
            source, "policy",
            "duplicate setting is ambiguous; no last-writer-wins migration",
          )
          continue
        case child.name
        of "default-count":
          let value = child.oneInteger(1, 9)
          if value.valid:
            viewCount = int(value.value)
            workspaceSettings.incl(child.name)
            result.add(
              source,
              "policy",
              MigrationDisposition.transformed,
              "policy view-count " & value.encoded,
            )
          else:
            result.unsupportedSetting(source, "policy", "view count must be in 1..9")
        of "default-layout":
          let value = child.oneString(1, 32)
          if value.valid and
              value.value in [
                "scroller", "tile", "grid", "monocle", "vertical-scroller"
              ]:
            policySettings[0] = "  layout " & value.encoded
            workspaceSettings.incl(child.name)
            result.add(
              source,
              "policy",
              MigrationDisposition.transformed,
              "native policy layout " & value.value,
            )
          else:
            result.unsupportedSetting(source, "policy", "default layout is unavailable")
        else:
          result.unsupportedSetting(
            source, "policy", "workspace setting is not yet representable"
          )
    of "protocol-surfaces":
      result.classifyTree(
        node, "protocol-surfaces", "shell", MigrationDisposition.unsupported,
        "requires the bounded Sophia-native Hagia shell interface",
      )
    of "terminal":
      result.add(
        "terminal", "session", MigrationDisposition.transformed,
        "opaque terminal application selector",
      )
      for child in node.children:
        let source = "terminal." & child.name
        let value = child.oneString(1, 64)
        if child.name != "command":
          result.unsupportedSetting(source, "session", "unsupported terminal setting")
        elif "terminal" in sessionSettingsSeen:
          result.unsupportedSetting(
            source, "session",
            "duplicate terminal selector is ambiguous; no last-writer-wins migration",
          )
        elif not value.valid or not value.value.validConnector():
          result.unsupportedSetting(
            source, "session", "terminal command is not an opaque application identity"
          )
        else:
          sessionSettings.add("  terminal " & value.encoded)
          sessionSettingsSeen.incl("terminal")
          result.add(
            source,
            "session",
            MigrationDisposition.transformed,
            "session terminal application " & value.value,
          )
    of "allow-exit-session":
      let value = node.oneBoolean(false)
      if not value.valid:
        result.unsupportedSetting(
          node.name, "session", "logout permission requires one bool"
        )
      elif "logout" in sessionSettingsSeen:
        result.unsupportedSetting(
          node.name, "session",
          "duplicate logout selector is ambiguous; no last-writer-wins migration",
        )
      else:
        sessionSettings.add("  logout " & value.encoded)
        sessionSettingsSeen.incl("logout")
        result.add(
          node.name, "session", MigrationDisposition.transformed,
          "session logout capability policy",
        )
    of "spawn-at-startup", "screen-lock":
      result.classifyTree(
        node, node.name, "session", MigrationDisposition.unsupported,
        "requires an opaque Sophia session capability",
      )
    of "shells", "hotkey-overlay", "layout-switch-toast", "recent-windows":
      result.classifyTree(
        node, node.name, "shell", MigrationDisposition.unsupported,
        "Hagia shell runtime is deferred",
      )
    of "window-rule", "workspace-rules":
      result.classifyTree(
        node, node.name, "broker", MigrationDisposition.excluded,
        "application metadata is outside Hagia policy authority",
      )
    of "janet":
      result.classifyTree(
        node, node.name, "policy", MigrationDisposition.excluded,
        "Janet runtime is deferred by the foundation milestone",
      )
    of "overview":
      result.classifyTree(
        node, node.name, "shell", MigrationDisposition.unsupported,
        "overview shell projection is deferred",
      )
    of "floating":
      result.classifyTree(
        node, node.name, "policy", MigrationDisposition.unsupported,
        "default floating geometry is not yet configurable",
      )
    of "screenshot":
      result.classifyTree(
        node, node.name, "portal", MigrationDisposition.unsupported,
        "capture settings require an explicit portal grant",
      )
    of "cursor":
      result.classifyTree(
        node, node.name, "input", MigrationDisposition.unsupported,
        "cursor presentation is not yet part of the input candidate",
      )
    of "presentation-mode":
      result.add(
        node.name, "output", MigrationDisposition.unsupported,
        "presentation timing policy is not yet part of the output candidate",
      )
    else:
      result.add(
        node.name, "unowned", MigrationDisposition.unsupported,
        "no authority accepts this Triad setting",
      )
  policySettings.insert("  view-count " & $viewCount, 1)
  result.outputProfile =
    "schema 1\npolicy {\n" & policySettings.join("\n") &
    "\n}\nshell { enabled #false; }\nshortcut {\n" & shortcutSettings.join("\n") &
    "\n}\nsession {\n" & sessionSettings.join("\n") & "\n}\ninput {\n" &
    inputSettings.join("\n") & "\n}\noutput {\n" & outputSettings.join("\n") &
    "\n}\nbroker { enabled #false; }\n"

proc writeMigration*(inputPath, outputDirectory: string): MigrationReport =
  if inputPath.len == 0 or outputDirectory.len == 0 or not outputDirectory.isAbsolute():
    raise newException(
      DesktopProfileError,
      "migration requires an input and explicit absolute output directory",
    )
  let configHome = getEnv("XDG_CONFIG_HOME")
  let activeUserDirectory =
    if configHome.len > 0:
      configHome / "hagia"
    else:
      getHomeDir() / ".config" / "hagia"
  let expandedOutput = outputDirectory.normalizedPath()
  if expandedOutput == activeUserDirectory.normalizedPath() or
      expandedOutput == "/etc/hagia":
    raise newException(
      DesktopProfileError,
      "migration output must not be an active configuration directory",
    )
  createDir(outputDirectory)
  let migratedProfilePath = outputDirectory / "config.kdl"
  let reportPath = outputDirectory / "migration-report.txt"
  if fileExists(migratedProfilePath) or fileExists(reportPath):
    raise
      newException(DesktopProfileError, "migration refuses to overwrite output files")
  result = readFile(inputPath).migrateTriadProfile()
  writeFile(migratedProfilePath, result.outputProfile)
  var reportText =
    "migration-report-v2\n" &
    "disposition\tkind\tsource\tsetting-authority\ttarget-authority\tcontext\t" &
    "trigger\tcommand\tresult\n"
  for item in result.items:
    reportText.add(
      $item.disposition & "\t" & $item.kind & "\t" & item.source.reportField() & "\t" &
        item.settingAuthority.reportField() & "\t" & item.authority.reportField() & "\t" &
        item.context.reportField() & "\t" & item.trigger.reportField() & "\t" &
        item.command.reportField() & "\t" & item.result.reportField() & "\n"
    )
  writeFile(reportPath, reportText)
