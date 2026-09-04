import std/sets

import kdl

import ../types/migration

import ./migration_command
import ./profile

## Physical binding collection: which Triad bindings carry over as physical
## input and which context each one belongs to.

proc bindingKind*(name: string): MigrationBindingKind =
  case name
  of "bind": MigrationBindingKind.key
  of "pointer-bind": MigrationBindingKind.pointer
  of "axis-bind": MigrationBindingKind.axis
  of "gesture-bind": MigrationBindingKind.gesture
  of "switch-bind": MigrationBindingKind.switch
  else: MigrationBindingKind.none

proc bindingContext*(node: KdlNode, inherited: string): string =
  result = inherited
  for key, value in node.props.pairs:
    if key == "mode" and value.kind == KString:
      result = "mode:" & value.kString()

proc collectPhysicalBindings*(
    node: KdlNode,
    path, inheritedContext: string,
    ordinal: var int,
    emitted: var HashSet[string],
    scratchpadNames: var seq[string],
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
    let migration = item.command.classifyTriadCommand(scratchpadNames)
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
      childPath, childContext, ordinal, emitted, scratchpadNames, shortcutSettings,
      report,
    )

proc physicalBindingCount*(report: MigrationReport): int =
  for item in report.items:
    if item.kind == MigrationItemKind.physicalBinding:
      inc result
