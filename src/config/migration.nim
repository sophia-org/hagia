import std/[os, sets, strutils]

import kdl

import ./profile

type
  MigrationDisposition* {.pure.} = enum
    retained
    transformed
    unsupported
    excluded

  MigrationItemKind* {.pure.} = enum
    setting
    physicalBinding

  MigrationBindingKind* {.pure.} = enum
    none
    key
    pointer
    axis
    gesture
    switch

  MigrationItem* = object
    kind*: MigrationItemKind
    source*: string
    settingAuthority*: string
    authority*: string
    disposition*: MigrationDisposition
    result*: string
    bindingKind*: MigrationBindingKind
    context*: string
    trigger*: string
    command*: string

  MigrationReport* = object
    items*: seq[MigrationItem]
    outputProfile*: string

  CommandMigration = object
    authority: string
    disposition: MigrationDisposition
    result: string
    outputCommand: string

proc add(
    report: var MigrationReport,
    source, authority: string,
    disposition: MigrationDisposition,
    result: string,
    settingAuthority = "",
) =
  report.items.add(
    MigrationItem(
      kind: MigrationItemKind.setting,
      source: source,
      settingAuthority: if settingAuthority.len > 0: settingAuthority else: authority,
      authority: authority,
      disposition: disposition,
      result: result,
    )
  )

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
      "session", MigrationDisposition.unsupported,
      "requires a dedicated security transition capability",
    )
  of "triad-reload":
    commandMigration(
      "session", MigrationDisposition.unsupported,
      "requires the cross-authority configuration coordinator",
    )
  of "toggle-hotkey-overlay", "toggle-overview", "select-window", "focus-shell-ui",
      "close-overview", "recent-window-next", "recent-window-prev",
      "recent-window-next --filter app-id", "recent-window-prev --filter app-id",
      "focus-window-or-workspace-down", "focus-window-or-workspace-up":
    commandMigration(
      "shell", MigrationDisposition.unsupported,
      "requires a bounded Hagia shell projection and opaque activation target",
    )
  of "screenshot", "screenshot-screen", "screenshot-window",
      "screenshot --clipboard-only", "screenshot --show-pointer",
      "screenshot --no-clipboard --hide-pointer",
      "screenshot --clipboard-only --hide-pointer":
    commandMigration(
      "portal", MigrationDisposition.unsupported,
      "requires an explicit capture portal grant",
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
        "session", MigrationDisposition.unsupported,
        "requires a declared opaque application capability",
      )
    let parts = command.splitWhitespace()
    if parts.len == 0:
      return commandMigration(
        "unowned", MigrationDisposition.unsupported, "command must not be empty"
      )
    let name = parts[0]
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
        "policy", MigrationDisposition.unsupported,
        "retained spatial command has no complete Hagia action parity",
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
      item.disposition = MigrationDisposition.unsupported
      item.result =
        migration.result & "; pointer binding cannot cross into this authority"
    elif unsupportedPointerAction:
      item.disposition = MigrationDisposition.unsupported
      item.result =
        migration.result & "; shortcut authority supports only move and resize gestures"
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
      item.disposition = MigrationDisposition.unsupported
      item.result =
        migration.result & "; contextual shortcut activation is not yet representable"
    elif migration.outputCommand.len > 0 and identity in emitted:
      item.disposition = MigrationDisposition.unsupported
      item.result = migration.result & "; duplicate shortcut identity is ambiguous"
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

proc migrateTriadProfile*(source: string): MigrationReport =
  var document: KdlDoc
  try:
    document = parseKdl(source)
  except CatchableError as error:
    raise newException(DesktopProfileError, "Triad profile syntax error: " & error.msg)
  var policySettings = @["  layout \"scroller\"", "  view-count 9"]
  var shortcutSettings = @["  profile \"triad-migration\""]
  var inputSettings = @["  inherit-sophia #true"]
  var outputSettings = @["  inherit-sophia #true"]
  var bindingOrdinal = 0
  var emittedBindings = initHashSet[string]()
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
          result.add(
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
      result.add(
        "input", "input", MigrationDisposition.transformed,
        "delegated to Sophia effective input configuration",
      )
    of "output":
      result.add(
        "output", "output", MigrationDisposition.transformed,
        "delegated to Sophia effective output configuration",
      )
    of "scratchpad":
      result.add(
        "scratchpad", "policy", MigrationDisposition.unsupported,
        "requires reduced scratchpad lifecycle and restoration",
      )
    of "workspaces":
      result.add(
        "workspaces", "policy", MigrationDisposition.unsupported,
        "requires dynamic workspace lifecycle and layout selection",
      )
    of "protocol-surfaces":
      result.add(
        "protocol-surfaces", "shell", MigrationDisposition.unsupported,
        "requires the bounded Sophia-native Hagia shell interface",
      )
    of "terminal", "spawn-at-startup", "screen-lock", "allow-exit-session":
      result.add(
        node.name, "session", MigrationDisposition.unsupported,
        "requires an opaque Sophia session capability",
      )
    of "shells", "hotkey-overlay", "layout-switch-toast", "recent-windows":
      result.add(
        node.name, "shell", MigrationDisposition.unsupported,
        "Hagia shell runtime is deferred",
      )
    of "window-rule", "workspace-rules":
      result.add(
        node.name, "broker", MigrationDisposition.excluded,
        "application metadata is outside Hagia policy authority",
      )
    of "janet":
      result.add(
        node.name, "policy", MigrationDisposition.excluded,
        "Janet runtime is deferred by the foundation milestone",
      )
    else:
      result.add(
        node.name, "unowned", MigrationDisposition.unsupported,
        "no authority accepts this Triad setting",
      )
  result.outputProfile =
    "schema 1\npolicy {\n" & policySettings.join("\n") &
    "\n}\nshell { enabled #false; }\nshortcut {\n" & shortcutSettings.join("\n") &
    "\n}\nsession {}\ninput {\n" & inputSettings.join("\n") & "\n}\noutput {\n" &
    outputSettings.join("\n") & "\n}\nbroker { enabled #false; }\n"

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
