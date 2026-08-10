import std/[math, sets]

import kdl

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

proc add*(
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

proc unsupportedSetting*(
    report: var MigrationReport, source, authority, reason: string
) =
  report.add(source, authority, MigrationDisposition.unsupported, reason)

proc plainShape*(node: KdlNode): bool =
  node.props.len == 0 and node.children.len == 0

proc integer*(value: KdlVal, parsed: var int64): bool =
  if value.kind notin {KInt, KInt8, KInt16, KInt32, KInt64}:
    return false
  try:
    parsed = value.kInt()
    true
  except CatchableError:
    false

proc number*(value: KdlVal, parsed: var float64): bool =
  try:
    case value.kind
    of KInt, KInt8, KInt16, KInt32, KInt64:
      parsed = float64(value.kInt())
    of KFloat, KFloat32, KFloat64:
      parsed = value.kFloat()
    else:
      return false
    parsed.classify() notin {fcNan, fcInf, fcNegInf}
  except CatchableError:
    false

proc oneBoolean*(node: KdlNode, allowFlag: bool): tuple[valid: bool, encoded: string] =
  if not node.plainShape():
    return
  if allowFlag and node.args.len == 0:
    return (true, "#true")
  if node.args.len == 1 and node.args[0].kind == KBool:
    return (true, if node.args[0].kBool(): "#true" else: "#false")

proc oneInteger*(
    node: KdlNode, minimum, maximum: int64
): tuple[valid: bool, value: int64, encoded: string] =
  if not node.plainShape() or node.args.len != 1:
    return
  var value: int64
  if not node.args[0].integer(value) or value < minimum or value > maximum:
    return
  (true, value, $value)

proc oneNumber*(
    node: KdlNode, minimum, maximum: float64
): tuple[valid: bool, encoded: string] =
  if not node.plainShape() or node.args.len != 1:
    return
  var value: float64
  if not node.args[0].number(value) or value < minimum or value > maximum:
    return
  (true, node.args[0].pretty())

proc oneString*(
    node: KdlNode, minimum, maximum: int
): tuple[valid: bool, value, encoded: string] =
  if not node.plainShape() or node.args.len != 1 or node.args[0].kind != KString:
    return
  let value = node.args[0].kString()
  if value.len < minimum or value.len > maximum:
    return
  (true, value, node.args[0].pretty())

proc emitSetting*(
    report: var MigrationReport,
    settings: var seq[string],
    emitted: var HashSet[string],
    source, authority, outputKey, encoded, outcome: string,
    disposition = MigrationDisposition.retained,
) =
  if outputKey in emitted:
    report.add(
      source, authority, MigrationDisposition.unsupported,
      "duplicate setting is ambiguous; no last-writer-wins migration",
    )
    return
  settings.add("        " & outputKey & " " & encoded)
  emitted.incl(outputKey)
  report.add(source, authority, disposition, outcome)
