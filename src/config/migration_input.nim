import std/[sets, strutils]

import kdl

import ../types/migration
import ./migration_common

## Input device translation: keyboard layout, repeat, pointer, and cursor
## settings.

const CursorThemeNameChars = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.'}
  ## The alphabet a cursor theme name may use, matching what the Sophia input
  ## candidate accepts. It is narrow because the name becomes a directory.

proc reportField*(value: string): string =
  value.multiReplace(("\\", "\\\\"), ("\t", "\\t"), ("\r", "\\r"), ("\n", "\\n"))

proc migrateXkb*(
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

proc migrateKeyboard*(
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

proc migrateMouse*(
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

proc migrateCursor*(
    node: KdlNode, settings: var seq[string], report: var MigrationReport
) =
  ## Triad states the cursor at the top level; Sophia carries it inside the
  ## input candidate, because the cursor is the pointer's appearance and the
  ## input authority already owns the pointer. The block moves, the keys do
  ## not.
  report.add(
    "cursor", "input", MigrationDisposition.transformed,
    "cursor block inside the Sophia input candidate",
  )
  var emitted = initHashSet[string]()
  var children: seq[string]
  for child in node.children:
    let source = "cursor." & child.name
    case child.name
    of "theme":
      let value = child.oneString(1, 64)
      if value.valid and value.value.allCharsInSet(CursorThemeNameChars):
        report.emitSetting(
          children, emitted, source, "input", "theme", value.encoded,
          "input cursor theme", MigrationDisposition.transformed,
        )
      else:
        # A theme name becomes a directory under an icon path, so a name that
        # could leave it is refused rather than carried across and refused
        # later by a session the operator is no longer watching.
        report.unsupportedSetting(
          source, "input", "cursor theme must be a plain icon-theme name"
        )
    of "size":
      # Triad allows 512; Sophia rasters to 128. Clamping silently would put a
      # cursor on screen at a size nobody chose, so an oversized value is
      # reported instead.
      let value = child.oneInteger(1, 128)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "input", "size", value.encoded,
          "input cursor size", MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(source, "input", "cursor size must be in 1..128")
    of "shake-to-find":
      let value = child.oneBoolean(true)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "input", "shake-to-find", value.encoded,
          "input cursor shake-to-find, which the session accepts but does not yet act on",
          MigrationDisposition.deferred,
        )
      else:
        report.unsupportedSetting(
          source, "input", "shake-to-find requires a flag or bool"
        )
    of "hide-when-typing", "hide-after-inactive-ms":
      report.unsupportedSetting(
        source, "input", "cursor hiding is not yet part of the input candidate"
      )
    else:
      report.unsupportedSetting(
        source, "input", "input candidate does not support this cursor setting"
      )
  if children.len > 0:
    settings.add("    cursor {\n" & children.join("\n") & "\n    }")

proc migrateInput*(
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
