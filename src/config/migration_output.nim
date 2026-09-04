import std/[math, sets, strutils]

import kdl

import ../types/migration

import ./migration_common

proc validConnector*(value: string): bool =
  value.len in 1 .. 64 and value.allCharsInSet(Letters + Digits + {'-', '_', '.'})

proc validExactMode(value: string): bool =
  if value == "preferred":
    return true
  let at = value.find('@')
  let x = value.find('x')
  if x <= 0 or at <= x + 1 or at == value.high:
    return false
  try:
    let width = parseInt(value[0 ..< x])
    let height = parseInt(value[x + 1 ..< at])
    let refresh = value[at + 1 .. ^1]
    let dot = refresh.find('.')
    if dot >= 0 and (dot == 0 or refresh.len - dot - 1 > 3):
      return false
    for value in refresh:
      if value != '.' and value notin Digits:
        return false
    let hz = parseFloat(refresh)
    width in 1 .. 16_384 and height in 1 .. 16_384 and hz >= 1.0 and hz <= 1_000.0
  except ValueError:
    false

proc outputPosition(node: KdlNode): tuple[valid: bool, encoded: string] =
  if not node.plainShape():
    return
  if node.args.len == 2:
    var x, y: int64
    if node.args[0].integer(x) and node.args[1].integer(y) and
        x in -1_000_000'i64 .. 1_000_000'i64 and y in -1_000_000'i64 .. 1_000_000'i64:
      return (true, $x & " " & $y)
  elif node.args.len == 1 and node.args[0].kind == KString:
    let value = node.args[0].kString()
    let separator = value.find('x', 1)
    if separator > 0:
      try:
        let x = parseBiggestInt(value[0 ..< separator])
        let y = parseBiggestInt(value[separator + 1 .. ^1])
        if x in -1_000_000'i64 .. 1_000_000'i64 and y in -1_000_000'i64 .. 1_000_000'i64:
          return (true, $x & " " & $y)
      except ValueError:
        discard

proc outputTransform(node: KdlNode): tuple[valid: bool, encoded: string] =
  if not node.plainShape() or node.args.len != 1:
    return
  var value: string
  if node.args[0].kind == KString:
    value = node.args[0].kString().toLowerAscii()
  else:
    var integer: int64
    if not node.args[0].integer(integer):
      return
    value = $integer
  let transformed =
    case value
    of "normal", "0":
      "normal"
    of "90", "1":
      "90"
    of "180", "2":
      "180"
    of "270", "3":
      "270"
    of "flipped", "4":
      "flipped"
    of "flipped-90", "5":
      "flipped-90"
    of "flipped-180", "6":
      "flipped-180"
    of "flipped-270", "7":
      "flipped-270"
    else:
      return
  (true, "\"" & transformed & "\"")

proc migrateNamedOutput(
    node: KdlNode,
    settings: var seq[string],
    connectors: var HashSet[string],
    focused: var bool,
    report: var MigrationReport,
) =
  let validIdentity =
    node.props.len == 0 and node.args.len == 1 and node.args[0].kind == KString and
    node.args[0].kString().validConnector()
  if not validIdentity:
    report.unsupportedSetting(
      "output.monitor", "output", "monitor requires a valid connector identity"
    )
    return
  let identity = (value: node.args[0].kString(), encoded: node.args[0].pretty())
  let sourceRoot = "output.monitor[" & identity.value & "]"
  if identity.value in connectors:
    report.unsupportedSetting(
      sourceRoot, "output",
      "duplicate connector is ambiguous; no last-writer-wins migration",
    )
    return
  connectors.incl(identity.value)
  var children: seq[string]
  var emitted = initHashSet[string]()
  for child in node.children:
    let source = sourceRoot & "." & child.name
    case child.name
    of "mode":
      let value = child.oneString(1, 64)
      if value.valid and value.value.validExactMode():
        report.emitSetting(
          children, emitted, source, "output", "mode", value.encoded,
          "exact output mode candidate",
        )
      else:
        report.unsupportedSetting(
          source, "output", "mode must be preferred or WIDTHxHEIGHT@REFRESH"
        )
    of "scale":
      let stringValue = child.oneString(1, 16)
      let numberValue = child.oneNumber(0.25, 8.0)
      if stringValue.valid and stringValue.value.cmpIgnoreCase("auto") == 0:
        report.emitSetting(
          children, emitted, source, "output", "scale", "\"auto\"",
          "automatic output scale candidate", MigrationDisposition.transformed,
        )
      elif numberValue.valid:
        var parsed: float64
        discard child.args[0].number(parsed)
        let milli = round(parsed * 1_000.0)
        if abs(milli / 1_000.0 - parsed) <= 1.0e-12:
          report.emitSetting(
            children, emitted, source, "output", "scale", numberValue.encoded,
            "fixed output scale candidate",
          )
        else:
          report.unsupportedSetting(
            source, "output", "scale supports at most three decimals"
          )
      else:
        report.unsupportedSetting(source, "output", "scale is outside 0.25..8")
    of "position":
      let value = child.outputPosition()
      if value.valid:
        report.emitSetting(
          children, emitted, source, "output", "position", value.encoded,
          "explicit output position candidate", MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(
          source, "output",
          "automatic or malformed position needs topology-backed resolution",
        )
    of "transform":
      let value = child.outputTransform()
      if value.valid:
        report.emitSetting(
          children, emitted, source, "output", "transform", value.encoded,
          "output transform candidate", MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(source, "output", "unsupported output transform")
    of "enabled", "disabled":
      let value = child.oneBoolean(false)
      if not value.valid:
        report.unsupportedSetting(source, "output", "enablement requires one bool")
      else:
        let encoded =
          if child.name == "disabled":
            if value.encoded == "#true": "#false" else: "#true"
          else:
            value.encoded
        report.emitSetting(
          children, emitted, source, "output", "enabled", encoded,
          "canonical output enablement", MigrationDisposition.transformed,
        )
    of "focus-at-startup":
      let value = child.oneBoolean(true)
      if not value.valid:
        report.unsupportedSetting(
          source, "output", "startup focus requires a flag or bool"
        )
      elif value.encoded == "#true" and focused:
        report.unsupportedSetting(
          source, "output", "only one output may request startup focus"
        )
      else:
        if value.encoded == "#true":
          focused = true
        report.emitSetting(
          children, emitted, source, "output", child.name, value.encoded,
          "explicit output startup focus", MigrationDisposition.transformed,
        )
    of "vrr":
      let value = child.oneInteger(0, 2)
      if value.valid:
        report.emitSetting(
          children, emitted, source, "output", "vrr", value.encoded,
          "typed output VRR policy",
        )
      else:
        report.unsupportedSetting(
          source, "output", "Hagia output VRR mode must be 0..2"
        )
    of "adaptive-sync":
      let value = child.oneBoolean(false)
      if value.valid:
        report.emitSetting(
          children,
          emitted,
          source,
          "output",
          "vrr",
          if value.encoded == "#true": "1" else: "0",
          "adaptive-sync converted to typed VRR policy",
          MigrationDisposition.transformed,
        )
      else:
        report.unsupportedSetting(source, "output", "adaptive-sync requires one bool")
    else:
      report.unsupportedSetting(
        source, "output", "output candidate does not support this monitor setting"
      )
  if children.len == 0:
    report.unsupportedSetting(
      sourceRoot, "output", "monitor has no settings accepted by the output candidate"
    )
  else:
    settings.add(
      "    named " & identity.encoded & " {\n" & children.join("\n") & "\n    }"
    )
    report.add(
      sourceRoot,
      "output",
      MigrationDisposition.transformed,
      "named output candidate " & identity.value,
    )

proc migrateOutput*(
    node: KdlNode, settings: var seq[string], report: var MigrationReport
) =
  report.add(
    "output", "output", MigrationDisposition.transformed,
    "partitioned into the immutable Sophia output candidate",
  )
  var connectors = initHashSet[string]()
  var focused = false
  for child in node.children:
    case child.name
    of "monitor":
      child.migrateNamedOutput(settings, connectors, focused, report)
    of "layout":
      report.unsupportedSetting(
        "output.layout", "output",
        "physical layout requires topology-backed scale and transform resolution",
      )
    of "default":
      report.unsupportedSetting(
        "output.default", "output", "fallback output rules are not yet representable"
      )
      for setting in child.children:
        report.unsupportedSetting(
          "output.default." & setting.name,
          "output",
          "fallback output setting is not yet representable",
        )
    else:
      report.unsupportedSetting(
        "output." & child.name, "output", "unsupported output setting"
      )
