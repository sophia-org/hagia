import std/[os, sets, strutils]

import kdl

import ../types/migration

import
  ./[
    migration_binding, migration_command, migration_common, migration_input,
    migration_output, profile,
  ]

export migration_binding, migration_command, migration_common, migration_input

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
