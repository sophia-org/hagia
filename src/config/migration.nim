import std/[os, strutils]

import kdl

import ./profile

type
  MigrationDisposition* {.pure.} = enum
    retained
    transformed
    unsupported
    excluded

  MigrationItem* = object
    source*: string
    authority*: string
    disposition*: MigrationDisposition
    result*: string

  MigrationReport* = object
    items*: seq[MigrationItem]
    outputProfile*: string

proc add(
    report: var MigrationReport,
    source, authority: string,
    disposition: MigrationDisposition,
    result: string,
) =
  report.items.add(
    MigrationItem(
      source: source, authority: authority, disposition: disposition, result: result
    )
  )

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
  for node in document:
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
        else:
          result.add(
            "layout." & child.name,
            "policy",
            MigrationDisposition.unsupported,
            "not available in foundation milestone",
          )
    of "bindings":
      for child in node.children:
        let identity = "bindings." & child.name & "." & $result.items.len
        if child.name == "bind" and child.args.len >= 2 and child.args[0].kind == KString and
            child.args[1].kind == KString:
          let command = child.args[1].kString()
          if command in [
            "close-window", "toggle-fullscreen", "toggle-maximized", "minimize",
            "focus-next", "spawn-terminal",
          ] or command.startsWith("focus-workspace "):
            shortcutSettings.add(
              "  bind " & child.args[0].pretty() & " " & child.args[1].pretty()
            )
            result.add(identity, "shortcut", MigrationDisposition.transformed, command)
          else:
            result.add(
              identity, "shortcut", MigrationDisposition.unsupported,
              "command has no Hagia foundation action",
            )
        else:
          result.add(
            identity, "shortcut", MigrationDisposition.unsupported,
            "binding form has no reduced action",
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
        node.name, "", MigrationDisposition.unsupported,
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
  var reportText: string
  for item in result.items:
    reportText.add(
      $item.disposition & "\t" & item.source & "\t" & item.authority & "\t" & item.result &
        "\n"
    )
  writeFile(reportPath, reportText)
