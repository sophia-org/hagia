import std/[algorithm, options, os, posix, sets, strutils, tables, tempfiles]

import kdl
from std/unicode import runes
import nimcrypto/[hash, sha2]

import ../types/[config_values, core, model]
import ./migration_common

type
  DesktopProfileError* = object of CatchableError

  ExpansionState = object
    files: int
    bytes: int64
    stack: seq[string]
    seen: HashSet[string]
    sources: seq[string]
    digestInput: string

  ExpandedNode = object
    node: KdlNode
    provenance: ValueProvenance

const compiledDesktopProfile* = staticRead("../../examples/config/default.kdl")

proc fail(message: string) {.noreturn.} =
  raise newException(DesktopProfileError, message)

proc profilePath*(explicitPath = ""): Option[string] =
  if explicitPath.len > 0:
    if not explicitPath.isAbsolute():
      fail("explicit desktop profile path must be absolute")
    return some(explicitPath)
  let configHome = getEnv("XDG_CONFIG_HOME")
  let userPath =
    if configHome.len > 0:
      configHome / "hagia" / "config.kdl"
    else:
      getHomeDir() / ".config" / "hagia" / "config.kdl"
  if fileExists(userPath):
    return some(userPath)
  let systemPath = "/etc/hagia/config.kdl"
  if fileExists(systemPath):
    return some(systemPath)
  none(string)

proc initTargetPath(explicitPath: string): string =
  ## Where `config init` writes: the explicit path, or the user discovery
  ## location. Never the system path — seeding /etc is an operator act, not a
  ## first-run convenience.
  if explicitPath.len > 0:
    if not explicitPath.isAbsolute():
      fail("explicit desktop profile path must be absolute")
    return explicitPath
  let configHome = getEnv("XDG_CONFIG_HOME")
  if configHome.len > 0:
    configHome / "hagia" / "config.kdl"
  else:
    getHomeDir() / ".config" / "hagia" / "config.kdl"

proc initDesktopProfile*(explicitPath = ""): tuple[path: string, installed: bool] =
  ## Seed-if-absent, Triad's installer discipline: write the compiled default
  ## only when nothing — file, symlink, or anything else — already occupies the
  ## path, and never overwrite. An existing entry is left alone and reported,
  ## not treated as an error, so repeated runs are safe.
  let target = initTargetPath(explicitPath)
  if fileExists(target) or symlinkExists(target) or dirExists(target):
    return (target, false)
  let parent = target.parentDir()
  if parent.len > 0:
    createDir(parent)
  let directory = if parent.len > 0: parent else: "."
  var temporary = ""
  var candidate: File
  try:
    (candidate, temporary) =
      createTempFile(target.extractFilename() & ".init-", "", directory)
    setFilePermissions(temporary, {fpUserRead, fpUserWrite, fpGroupRead, fpOthersRead})
    candidate.write(compiledDesktopProfile)
    candidate.flushFile()
    if posix.fsync(candidate.getFileHandle()) != 0:
      raiseOSError(osLastError())
    candidate.close()
    candidate = nil
    moveFile(temporary, target)
    temporary = ""
  finally:
    if candidate != nil:
      candidate.close()
    if temporary.len > 0:
      removeFile(temporary)
  (target, true)

proc checkedPath(path: string): string =
  result = path.expandFilename()
  var details: Stat
  if lstat(result.cstring, details) != 0:
    raiseOSError(osLastError())
  if S_ISLNK(details.st_mode) or not S_ISREG(details.st_mode):
    fail("desktop profile source must be a regular non-symlink file")
  let owner = Uid(geteuid())
  if details.st_uid != owner and details.st_uid != Uid(0):
    fail("desktop profile source has an unsafe owner")
  if (details.st_mode and Mode(S_IWGRP or S_IWOTH)) != Mode(0):
    fail("desktop profile source is group- or world-writable")

proc stringArg(node: KdlNode, context: string): string =
  if node.args.len != 1 or node.args[0].kind != KString or node.props.len != 0 or
      node.children.len != 0 or node.tag.isSome:
    fail(context & " must contain exactly one untyped string argument")
  node.args[0].kString()

proc expandFile(
    path: string, depth: int, state: var ExpansionState
): seq[ExpandedNode] =
  if depth > maxProfileDepth:
    fail("desktop profile include depth exceeds 10")
  let canonical = path.checkedPath()
  if canonical in state.stack:
    fail("desktop profile include cycle reaches " & canonical)
  if canonical in state.seen:
    fail("desktop profile includes the same source more than once")
  inc state.files
  if state.files > maxProfileFiles:
    fail("desktop profile includes more than 64 files")
  let size = getFileSize(canonical)
  if size < 1:
    fail("desktop profile source is empty")
  state.bytes += size
  if state.bytes > maxProfileBytes:
    fail("desktop profile aggregate exceeds one MiB")
  let source = readFile(canonical)
  state.stack.add(canonical)
  state.seen.incl(canonical)
  state.sources.add(canonical)
  state.digestInput.add(canonical & "\x00" & source & "\x00")
  var document: KdlDoc
  try:
    document = parseKdl(source)
  except CatchableError as error:
    fail("desktop profile syntax error in " & canonical & ": " & error.msg)
  for ordinal, node in document:
    if node.name == "include":
      let includePath = node.stringArg("include")
      let resolved =
        if includePath.isAbsolute():
          includePath
        else:
          canonical.parentDir() / includePath
      result.add(resolved.expandFile(depth + 1, state))
    else:
      result.add(
        ExpandedNode(
          node: node, provenance: ValueProvenance(path: canonical, ordinal: ordinal + 1)
        )
      )
  discard state.stack.pop()

proc authority(name: string): ProfileAuthority =
  case name
  of "policy":
    ProfileAuthority.policy
  of "shell":
    ProfileAuthority.shell
  of "shortcut":
    ProfileAuthority.shortcut
  of "session":
    ProfileAuthority.session
  of "input":
    ProfileAuthority.input
  of "output":
    ProfileAuthority.output
  of "broker":
    ProfileAuthority.broker
  else:
    fail("unsupported desktop profile section " & name)

proc settingKey(authority: ProfileAuthority, node: KdlNode): string =
  result = $authority & "." & node.name
  if node.name in ["bind", "pointer-bind", "application", "device", "named"]:
    if node.args.len == 0 or node.args[0].kind != KString:
      fail(node.name & " requires a string identity")
    result.add("." & node.args[0].kString())
  if node.name in ["view-name", "view-layout"]:
    if node.args.len == 0 or
        node.args[0].kind notin {KInt, KInt8, KInt16, KInt32, KInt64}:
      fail(node.name & " requires an integer view slot")
    result.add("." & $node.args[0].kInt())

proc hasControlCharacter(value: string): bool =
  ## C0, DEL and C1. C1 is two bytes in UTF-8, so a byte-wise test misses it.
  for rune in value.runes():
    let point = int(rune)
    if point < 0x20 or point == 0x7f or point in 0x80 .. 0x9f:
      return true
  false

proc encodedSetting(node: KdlNode): string =
  ## A setting's single-line source form. `inline` renders children through
  ## Nim's object stringifier, not KDL, so a node with any is assembled here.
  if node.children.len == 0:
    return node.inline()
  var head = node
  head.children = @[]
  result = head.inline()
  result.add(" { ")
  for index, child in node.children:
    if index > 0:
      result.add("; ")
    result.add(child.encodedSetting())
  result.add(" }")

proc validateApplicationName(name: string, generated: bool) =
  ## One identity rule for every spelling; only the reserved prefix differs.
  if name.len == 0 or name.len > maxApplicationNameBytes:
    fail("application identity length is invalid")
  for value in name:
    if value notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.'}:
      fail("application identity contains unsupported characters")
  if not generated and name.startsWith(generatedApplicationPrefix):
    fail("application identity uses the reserved lowering prefix")

proc validateExecCommand(node: KdlNode) =
  ## An executable followed by literal argv. Nothing is split and no shell is
  ## interposed, so a word reaches `execve` unchanged.
  if node.tag.isSome:
    fail("exec cannot carry a type annotation")
  if node.args.len == 0 or node.props.len != 0 or node.children.len != 0:
    fail("exec requires an executable and literal arguments")
  if node.args.len > maxApplicationArguments + 1:
    fail("exec exceeds the bounded argument vector")
  for index, argument in node.args:
    if argument.kind != KString or argument.tag.isSome:
      fail("exec arguments must be untyped strings")
    let value = argument.kString()
    if value.len > maxApplicationArgumentBytes:
      fail("exec argument exceeds the bounded argument bytes")
    if value.hasControlCharacter():
      fail("exec argument contains a control character")
    if index != 0:
      continue
    # A relative path would resolve against the session's working directory,
    # which the profile does not state.
    if value.len == 0 or value in [".", ".."] or
        (not value.isAbsolute() and value.contains('/')):
      fail("exec executable must be a PATH name or an absolute path")

proc validateApplicationSetting(node: KdlNode, staged: bool) =
  ## Exactly one body per named application; a merge is what an operator cannot
  ## see. Only a staged candidate may declare a generated name: Sophia mints
  ## those, so accepting one from source would let a profile claim it first.
  if node.args.len != 1 or node.args[0].kind != KString or node.args[0].tag.isSome or
      node.props.len != 0:
    fail("session application requires a single untyped identity string")
  node.args[0].kString().validateApplicationName(generated = staged)
  if node.children.len != 1:
    fail("session application requires exactly one exec or use-core body")
  let body = node.children[0]
  case body.name
  of "exec":
    body.validateExecCommand()
  of "use-core":
    if body.tag.isSome or body.args.len != 1 or body.args[0].kind != KString or
        body.args[0].tag.isSome or body.props.len != 0 or body.children.len != 0:
      fail("use-core requires a single untyped core application identity")
    # A core reference is never a generated name, in either context.
    body.args[0].kString().validateApplicationName(generated = false)
  else:
    fail("session application body must be exec or use-core")

proc isReservedDesktopShortcut*(source: string): bool =
  let parts = source.split('+')
  if parts.len == 0 or parts[^1].toLowerAscii() != "backspace":
    return false
  var control = false
  var alt = false
  for index in 0 ..< parts.high:
    case parts[index].toLowerAscii()
    of "ctrl", "control":
      control = true
    of "alt":
      alt = true
    else:
      discard
  result = control and alt

proc shortcutTrigger(node: KdlNode): string =
  let source = node.args[0].kString()
  if source.len == 0 or source.len > 64:
    fail("shortcut trigger length is invalid")
  let parts = source.split('+')
  if parts.len == 0 or parts[^1].len == 0:
    fail("shortcut trigger is empty")
  var trigger = parts[^1].toLowerAscii()
  for value in trigger:
    if value notin {'a' .. 'z', '0' .. '9', '_', '-', '=', '?', '/', ',', '.', '[', ']'}:
      fail("shortcut trigger contains unsupported characters")
  # A trigger Sophia cannot resolve to a keycode is refused here rather than
  # at login, where it fails the whole session after the profile has already
  # been called valid. Pointer triggers name buttons and are checked below.
  if node.name == "bind" and trigger notin bindableTriggerNames:
    fail("shortcut trigger names no bindable key: " & trigger)
  var modifiers = 0'u8
  for index in 0 ..< parts.high:
    let bit =
      case parts[index].toLowerAscii()
      of "shift":
        1'u8 shl 0
      of "ctrl", "control":
        1'u8 shl 1
      of "alt":
        1'u8 shl 2
      of "super":
        1'u8 shl 3
      else:
        fail("shortcut contains an unsupported modifier")
    if (modifiers and bit) != 0:
      fail("shortcut contains a duplicate modifier")
    modifiers = modifiers or bit
  if node.name == "pointer-bind" and trigger notin ["left", "middle", "right"]:
    fail("pointer shortcut must name left, middle, or right")
  if node.name == "bind" and source.isReservedDesktopShortcut():
    fail("reserved emergency chord cannot be overridden")
  if trigger in ["?", "question"]:
    modifiers = modifiers or 1'u8
    trigger = "slash"
  elif trigger == "/":
    trigger = "slash"
  $modifiers & ":" & trigger

proc validateShortcutSetting(node: KdlNode) =
  if node.name == "profile":
    let profile = node.stringArg("shortcut profile")
    if profile.len > 64 or profile.len == 0:
      fail("shortcut profile identity is invalid")
    for value in profile:
      if value notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_'}:
        fail("shortcut profile identity contains unsupported characters")
    return
  # A command block is the source spelling; `authority:command` is what a
  # staged candidate carries. Both are checked, so neither passes alone.
  let commandBlock = node.children.len > 0
  if commandBlock:
    if node.args.len != 1 or node.args[0].kind != KString:
      fail("shortcut command block requires a single trigger string")
  elif node.args.len != 2 or node.args[0].kind != KString or node.args[1].kind != KString:
    fail("shortcut binding requires trigger and target strings")
  for key, value in node.props:
    if key notin ["label", "group"] or value.kind != KString:
      fail("shortcut property must be label or group string")
    let text = value.kString()
    let bound = if key == "label": 128 else: 64
    if text.len == 0 or text.len > bound or text.contains({'\0' .. '\x1f', '\x7f'}):
      fail("shortcut display metadata is invalid")
    for rune in text.runes():
      if int(rune) in 0x202a .. 0x202e or int(rune) in 0x2066 .. 0x2069 or
          int(rune) in 127 .. 159:
        fail("shortcut display metadata contains a control")
  discard node.shortcutTrigger()
  if commandBlock:
    if node.name == "pointer-bind":
      fail("pointer shortcut cannot invoke a session capability")
    if node.children.len != 1:
      fail("shortcut command block requires exactly one launch or exec body")
    let body = node.children[0]
    case body.name
    of "launch":
      if body.tag.isSome or body.args.len != 1 or body.args[0].kind != KString or
          body.args[0].tag.isSome or body.props.len != 0 or body.children.len != 0:
        fail("launch requires a single untyped application identity")
      body.args[0].kString().validateApplicationName(generated = false)
    of "exec":
      body.validateExecCommand()
    else:
      fail("shortcut command block body must be launch or exec")
    return
  let target = node.args[1].kString()
  if target.len == 0 or target.len > 128 or target.strip() != target:
    fail("shortcut target length is invalid")
  let separator = target.find(':')
  if separator <= 0 or separator == target.high:
    fail("shortcut target requires an explicit authority")
  let authority = target[0 ..< separator]
  let command = target[separator + 1 .. ^1]
  case authority
  of "policy":
    for value in command:
      if value notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', ' ', '.'}:
        fail("policy shortcut target contains unsupported characters")
  of "session":
    if node.name == "pointer-bind":
      fail("pointer shortcut cannot invoke a session capability")
    if command notin [
      "close-window", "logout", "spawn-terminal", "spawn-browser", "window-switcher",
      "reload-profile", "restart-wm", "shortcut-help", "application-launcher",
    ]:
      fail("shortcut names an unknown session capability")
  of "application":
    # The lowered spelling. Generated names are admissible only here.
    if node.name == "pointer-bind":
      fail("pointer shortcut cannot invoke a session capability")
    command.validateApplicationName(generated = true)
  else:
    fail("shortcut target authority is unsupported")

proc candidateSettingKey(authority: ProfileAuthority, node: KdlNode): string =
  if authority == ProfileAuthority.shortcut and node.name in ["bind", "pointer-bind"]:
    $authority & "." & node.name & "." & node.shortcutTrigger()
  else:
    authority.settingKey(node)

proc validateGapSetting*(node: KdlNode, allowNegative = false) =
  ## `allowNegative` is set only for a strut edge. A gap is spacing and cannot
  ## be less than none, but a strut is a reservation, and a negative one is
  ## how a layout asks for gaps between tiles without one at each screen edge
  ## -- `gaps 16; struts { left -16; right -16 }`.
  if node.tag.isSome or node.props.len != 0:
    fail("policy " & node.name & " does not accept annotations or properties")
  if node.name == "struts":
    if node.args.len != 0 or node.children.len > 4:
      fail("policy struts requires up to four named edges")
    var seen = initHashSet[string]()
    for edge in node.children:
      if edge.name notin ["left", "right", "top", "bottom"] or edge.name in seen:
        fail("policy struts has an unknown or duplicate edge")
      seen.incl(edge.name)
      edge.validateGapSetting(allowNegative = true)
  else:
    if node.args.len != 1 or node.children.len != 0 or
        node.args[0].kind notin {KInt, KInt8, KInt16, KInt32, KInt64}:
      fail("policy " & node.name & " requires one integer")
    let lowest =
      if allowNegative:
        -maxGap
      else:
        0
    if node.args[0].tag.isSome or node.args[0].get(int) < lowest or
        node.args[0].get(int) > maxGap:
      fail("policy " & node.name & " is outside " & $lowest & ".." & $maxGap)

proc validateExtentSetting*(node: KdlNode, maxChildren: int) =
  ## One configured size, or a list of them, stated as `{ proportion 0.5 }`
  ## or `{ fixed 1280 }`: a proportion is a share of the room a column can
  ## occupy and rescales with the output, where a fixed extent is logical
  ## pixels and does not.
  if node.tag.isSome or node.props.len != 0:
    fail("policy " & node.name & " does not accept annotations or properties")
  if node.args.len != 0:
    fail(
      "policy " & node.name &
        " now takes a { proportion N } or { fixed N } child, not a percentage"
    )
  if node.children.len < 1 or node.children.len > maxChildren:
    fail("policy " & node.name & " requires one to " & $maxChildren & " sizes")
  for child in node.children:
    if child.name notin ["proportion", "fixed"]:
      fail("policy " & node.name & " sizes must be proportion or fixed")
    if child.tag.isSome or child.props.len != 0 or child.children.len != 0 or
        child.args.len != 1 or child.args[0].tag.isSome:
      fail("policy " & node.name & " " & child.name & " requires one plain value")
    if child.name == "fixed":
      if child.args[0].kind notin {KInt, KInt8, KInt16, KInt32, KInt64}:
        fail("policy " & node.name & " fixed requires whole pixels")
      let pixels = child.args[0].kInt()
      if pixels < 1 or pixels > maxFixedExtent:
        fail("policy " & node.name & " fixed is outside 1.." & $maxFixedExtent)
    else:
      # Bounded on the value as written rather than on the scale it converts
      # to, because the conversion saturates and would accept a request far
      # outside the range by silently clamping it.
      var value: float64
      if not child.args[0].number(value):
        fail("policy " & node.name & " proportion requires a finite number")
      # Compared after scaling, and allowing the one quantum the conversion
      # truncates: the smallest bound is 3277/65536, so `proportion 0.05` is a
      # hair under it and refusing what the documented minimum spells would be
      # a bound nobody could write.
      let requested = value * float64(uint32(scaleOne))
      if requested < float64(uint32(minimumScale)) - 1.0 or
          requested > float64(uint32(maximumScale)):
        fail("policy " & node.name & " proportion is outside 0.05..10")

proc validateSetting(authority: ProfileAuthority, node: KdlNode, staged = false) =
  if node.tag.isSome:
    fail("type annotations are unsupported in desktop profiles")
  if node.name in [
    "emergency-chord", "policy-timeout", "max-surfaces", "max-outputs", "renderer",
    "scanout", "namespace-profile",
  ]:
    fail("desktop profile attempts to override a reserved control")
  let supported =
    case authority
    of ProfileAuthority.policy:
      node.name in [
        "layout", "layout-cycle", "view-count", "outer-gap", "inner-gap", "gaps",
        "struts", "viewport-offset", "master-count", "master-ratio", "gap-step",
        "view-name", "view-layout", "preset-column-widths", "scratchpad-size",
        "floating-size", "default-column-width", "center-focused-column",
        "always-center-single-column", "focus-follows-mouse", "default-row-height",
        "preset-row-heights",
      ]
    of ProfileAuthority.shell:
      node.name in ["enabled", "panel"]
    of ProfileAuthority.shortcut:
      node.name in ["profile", "bind", "pointer-bind"]
    of ProfileAuthority.session:
      node.name in [
        "terminal", "browser", "logout", "startup", "application-catalog", "application"
      ]
    of ProfileAuthority.input:
      node.name in ["inherit-sophia", "keyboard", "pointer", "cursor"]
    of ProfileAuthority.output:
      node.name in ["inherit-sophia", "named"]
    of ProfileAuthority.broker:
      node.name in ["enabled", "capability"]
  if not supported and authority == ProfileAuthority.policy:
    for retired in retiredPolicySettings:
      if node.name == retired[0]:
        fail(
          "policy " & retired[0] & " is now " & retired[1] &
            ", taking proportion or fixed children"
        )
  if not supported:
    fail("unsupported " & $authority & " setting " & node.name)
  if node.args.len > 32 or node.props.len > 32 or node.children.len > 64:
    fail("desktop profile setting exceeds structural bounds")
  if authority == ProfileAuthority.session and node.name == "application":
    node.validateApplicationSetting(staged)
  if authority == ProfileAuthority.policy and node.name in ["gaps", "struts"]:
    node.validateGapSetting()
  if authority == ProfileAuthority.policy and
      node.name in ["default-column-width", "default-row-height"]:
    node.validateExtentSetting(1)
  if authority == ProfileAuthority.policy and
      node.name in ["preset-column-widths", "preset-row-heights"]:
    node.validateExtentSetting(maxSizePresets)
  if authority == ProfileAuthority.policy and node.name == "layout":
    if node.stringArg("policy layout") notin supportedLayoutNames:
      fail("unsupported Hagia policy layout")
  if authority == ProfileAuthority.policy and node.name == "view-name":
    if node.args.len != 2 or
        node.args[0].kind notin {KInt, KInt8, KInt16, KInt32, KInt64} or
        node.args[1].kind != KString or node.props.len != 0 or node.children.len != 0:
      fail("policy view-name requires a slot and a name")
    if node.args[0].kInt() < 1 or node.args[0].kInt() > 9:
      fail("policy view-name slot is outside 1..9")
    let name = node.args[1].kString()
    if name.len == 0 or name.len > maxViewNameBytes or name.strip() != name:
      fail("policy view-name length is invalid")
    for value in name:
      if value in {'\0' .. '\31', '\127'}:
        fail("policy view-name contains control characters")
  if authority == ProfileAuthority.policy and node.name == "view-layout":
    if node.args.len != 2 or
        node.args[0].kind notin {KInt, KInt8, KInt16, KInt32, KInt64} or
        node.args[1].kind != KString or node.props.len != 0 or node.children.len != 0:
      fail("policy view-layout requires a slot and a layout name")
    if node.args[0].kInt() < 1 or node.args[0].kInt() > 9:
      fail("policy view-layout slot is outside 1..9")
    if node.args[1].kString() notin supportedLayoutNames:
      fail("policy view-layout names an unsupported layout")
  if authority == ProfileAuthority.policy and
      node.name in ["scratchpad-size", "floating-size"]:
    if node.args.len != 2 or node.props.len != 0 or node.children.len != 0:
      fail("policy " & node.name & " requires width and height percentages")
    for argument in node.args:
      if argument.kind notin {KInt, KInt8, KInt16, KInt32, KInt64}:
        fail("policy " & node.name & " requires width and height percentages")
    for argument in node.args:
      let value = argument.kInt()
      let zeroAllowed = node.name == "floating-size"
      if (value == 0 and not zeroAllowed) or value < 0 or
          (value != 0 and (value < 10 or value > 100)):
        fail("policy " & node.name & " percentages must be 10..100")
  if authority == ProfileAuthority.policy and node.name == "layout-cycle":
    if node.args.len == 0 or node.args.len > supportedLayoutNames.len or
        node.props.len != 0 or node.children.len != 0:
      fail(
        "policy layout-cycle requires one to " & $supportedLayoutNames.len &
          " layout names"
      )
    var layouts = initHashSet[string]()
    for argument in node.args:
      if argument.kind != KString or argument.kString() notin supportedLayoutNames or
          argument.kString() in layouts:
        fail("policy layout-cycle contains an invalid or duplicate layout")
      layouts.incl(argument.kString())
  if authority == ProfileAuthority.shortcut:
    node.validateShortcutSetting()
  if authority == ProfileAuthority.shell and node.name == "enabled":
    if node.args.len != 1 or node.args[0].kind != KBool:
      fail("shell enabled requires one boolean argument")
  if authority == ProfileAuthority.broker and node.name == "enabled":
    if node.args.len != 1 or node.args[0].kind != KBool or node.args[0].kBool():
      fail("unavailable authority capability cannot be enabled")

proc partition(
    nodes: openArray[ExpandedNode], generation: uint64, digest: string
): array[ProfileAuthority, AuthorityCandidate] =
  for authority in ProfileAuthority:
    result[authority] =
      AuthorityCandidate(authority: authority, generation: generation, digest: digest)
  var schemaSeen = false
  var settings = initHashSet[string]()
  var shortcutBindings = 0
  # Declared applications and inline commands share one namespace and bound.
  var declaredApplications = initHashSet[string]()
  var inlineCommands = 0
  var applicationReferences: seq[string]
  for expanded in nodes:
    let node = expanded.node
    if node.name == "schema":
      var schema = 0
      try:
        if node.args.len == 1:
          schema = node.args[0].get(int)
      except CatchableError:
        discard
      if schemaSeen or node.args.len != 1 or schema != 1 or node.children.len != 0 or
          node.props.len != 0:
        fail("desktop profile requires exactly one schema 1 declaration")
      schemaSeen = true
      continue
    let owner = node.name.authority()
    if node.args.len != 0 or node.props.len != 0 or node.tag.isSome:
      fail("authority section " & node.name & " has an ambiguous shape")
    for child in node.children:
      owner.validateSetting(child)
      if owner == ProfileAuthority.shortcut and child.name in ["bind", "pointer-bind"]:
        inc shortcutBindings
        if shortcutBindings > maxDesktopShortcutBindings:
          fail("desktop profile contains more than 256 shortcut bindings")
      if owner == ProfileAuthority.session and child.name == "application":
        declaredApplications.incl(child.args[0].kString())
      if owner == ProfileAuthority.shortcut and child.name == "bind":
        if child.children.len == 1:
          case child.children[0].name
          of "exec":
            inc inlineCommands
          of "launch":
            applicationReferences.add(child.children[0].args[0].kString())
          else:
            discard
        elif child.args.len == 2 and child.args[1].kind == KString:
          # The same reference as a target string; both spellings resolve.
          let target = child.args[1].kString()
          if target.startsWith("application:"):
            applicationReferences.add(target["application:".len .. ^1])
      let key = owner.candidateSettingKey(child)
      if key in settings:
        fail("duplicate desktop profile setting " & key)
      settings.incl(key)
      result[owner].values.add(
        ProfileValue(
          key: key, encoded: child.encodedSetting(), provenance: expanded.provenance
        )
      )
  if not schemaSeen:
    fail("desktop profile has no schema declaration")
  if declaredApplications.len + inlineCommands > maxSessionApplications:
    fail("desktop profile declares more than 32 session applications")
  # A reference names this profile's own application. Falling back to Sophia's
  # core registry would be the merge this grammar refuses. The generated prefix
  # is refused outright: source cannot declare one, so such a reference could
  # only alias another binding's inline block.
  for reference in applicationReferences:
    if reference.startsWith(generatedApplicationPrefix):
      fail("shortcut references the reserved lowering prefix " & reference)
    if reference notin declaredApplications:
      fail("shortcut references an undeclared session application " & reference)

proc loadDesktopProfile*(
    explicitPath = "", generation = 1'u64
): DesktopProfileGeneration =
  if generation == 0:
    fail("desktop profile generation must be nonzero")
  var state = ExpansionState(seen: initHashSet[string]())
  let discovered = profilePath(explicitPath)
  var nodes: seq[ExpandedNode]
  if discovered.isSome:
    nodes = discovered.get().expandFile(0, state)
  else:
    state.sources.add("<compiled>")
    state.digestInput = "<compiled>\x00" & compiledDesktopProfile
    try:
      for ordinal, node in parseKdl(compiledDesktopProfile):
        nodes.add(
          ExpandedNode(
            node: node,
            provenance: ValueProvenance(path: "<compiled>", ordinal: ordinal + 1),
          )
        )
    except CatchableError as error:
      fail("compiled desktop profile is invalid: " & error.msg)
  result.generation = generation
  result.sources = state.sources
  result.digest = $sha256.digest(state.digestInput)
  result.candidates = nodes.partition(generation, result.digest)

proc loadAuthorityCandidate*(
    path: string, expectedAuthority: ProfileAuthority
): AuthorityCandidate =
  if path.len == 0 or not path.isAbsolute():
    fail("authority candidate path must be absolute")
  let canonical = path.checkedPath()
  let size = getFileSize(canonical)
  if size < 1 or size > maxProfileBytes:
    fail("authority candidate size is outside the bounded profile limit")
  var document: KdlDoc
  try:
    document = parseKdl(readFile(canonical))
  except CatchableError as error:
    fail("authority candidate syntax error: " & error.msg)
  var schemaSeen = false
  var generationSeen = false
  var digestSeen = false
  var authoritySeen = false
  var settings = initHashSet[string]()
  var shortcutBindings = 0
  var sessionApplications = 0
  for ordinal, node in document:
    case node.name
    of "schema":
      var schema = 0
      try:
        if node.args.len == 1:
          schema = node.args[0].get(int)
      except CatchableError:
        discard
      if schemaSeen or node.args.len != 1 or schema != 1 or node.props.len != 0 or
          node.children.len != 0 or node.tag.isSome:
        fail("authority candidate requires exactly one schema 1 declaration")
      schemaSeen = true
    of "profile-generation":
      var generation = 0'u64
      try:
        if node.args.len == 1:
          generation = node.args[0].get(uint64)
      except CatchableError:
        discard
      if generationSeen or generation == 0 or node.props.len != 0 or
          node.children.len != 0 or node.tag.isSome:
        fail("authority candidate generation is invalid")
      generationSeen = true
      result.generation = generation
    of "profile-digest":
      let digest = node.stringArg("authority candidate digest")
      if digestSeen or digest.len != 64 or
          not digest.allCharsInSet({'0' .. '9', 'a' .. 'f', 'A' .. 'F'}):
        fail("authority candidate digest must be 64 hexadecimal characters")
      digestSeen = true
      result.digest = digest.toLowerAscii()
    else:
      let owner = node.name.authority()
      if authoritySeen or owner != expectedAuthority:
        fail("authority candidate crossed its assigned authority boundary")
      if node.args.len != 0 or node.props.len != 0 or node.tag.isSome:
        fail("authority candidate section has an ambiguous shape")
      authoritySeen = true
      result.authority = owner
      for child in node.children:
        owner.validateSetting(child, staged = true)
        if owner == ProfileAuthority.shortcut and child.name in ["bind", "pointer-bind"]:
          inc shortcutBindings
          if shortcutBindings > maxDesktopShortcutBindings:
            fail("authority candidate contains more than 256 shortcut bindings")
        if owner == ProfileAuthority.session and child.name == "application":
          inc sessionApplications
          if sessionApplications > maxSessionApplications:
            fail("authority candidate contains more than 32 session applications")
        let key = owner.candidateSettingKey(child)
        if key in settings:
          fail("duplicate authority candidate setting " & key)
        settings.incl(key)
        result.values.add(
          ProfileValue(
            key: key,
            encoded: child.encodedSetting(),
            provenance: ValueProvenance(path: canonical, ordinal: ordinal + 1),
          )
        )
  if not schemaSeen or not generationSeen or not digestSeen or not authoritySeen:
    fail("authority candidate is incomplete")

proc effectiveProfile*(profile: DesktopProfileGeneration): string =
  result.add("generation " & $profile.generation & "\n")
  result.add("digest \"" & profile.digest & "\"\n")
  for authority in ProfileAuthority:
    result.add($authority & " {\n")
    var values = profile.candidates[authority].values
    values.sort(
      proc(left, right: ProfileValue): int =
        cmp(left.key, right.key)
    )
    for value in values:
      result.add("  " & value.encoded & " // " & value.provenance.path & "\n")
    result.add("}\n")
