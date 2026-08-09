import std/[algorithm, options, os, posix, sets, strutils, tables]

import kdl
import nimcrypto/[hash, sha2]

type
  DesktopProfileError* = object of CatchableError

  ProfileAuthority* {.pure.} = enum
    policy
    shell
    shortcut
    session
    input
    output
    broker

  ValueProvenance* = object
    path*: string
    ordinal*: int

  ProfileValue* = object
    key*: string
    encoded*: string
    provenance*: ValueProvenance

  AuthorityCandidate* = object
    authority*: ProfileAuthority
    generation*: uint64
    digest*: string
    values*: seq[ProfileValue]

  DesktopProfileGeneration* = object
    generation*: uint64
    digest*: string
    sources*: seq[string]
    candidates*: array[ProfileAuthority, AuthorityCandidate]

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

const
  maxProfileDepth* = 10
  maxProfileFiles* = 64
  maxProfileBytes* = 1_048_576'i64
  compiledDesktopProfile* = """
schema 1
policy {
  layout "scroller"
  view-count 9
  outer-gap 0
  inner-gap 0
}
shell { enabled #false; }
shortcut { profile "compiled"; }
session { terminal "terminal"; browser "browser"; }
input { inherit-sophia #true; }
output { inherit-sophia #true; }
broker { enabled #false; }
"""

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

proc validateSetting(authority: ProfileAuthority, node: KdlNode) =
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
      node.name in ["layout", "view-count", "outer-gap", "inner-gap", "viewport-offset"]
    of ProfileAuthority.shell:
      node.name in ["enabled", "panel"]
    of ProfileAuthority.shortcut:
      node.name in ["profile", "bind", "pointer-bind"]
    of ProfileAuthority.session:
      node.name in ["terminal", "browser", "logout", "startup"]
    of ProfileAuthority.input:
      node.name in ["inherit-sophia", "keyboard", "pointer"]
    of ProfileAuthority.output:
      node.name in ["inherit-sophia", "named"]
    of ProfileAuthority.broker:
      node.name in ["enabled", "capability"]
  if not supported:
    fail("unsupported " & $authority & " setting " & node.name)
  if node.args.len > 32 or node.props.len > 32 or node.children.len > 64:
    fail("desktop profile setting exceeds structural bounds")
  if authority == ProfileAuthority.policy and node.name == "layout":
    if node.stringArg("policy layout") != "scroller":
      fail("unsupported Hagia policy layout")
  if authority in {ProfileAuthority.shell, ProfileAuthority.broker} and
      node.name == "enabled":
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
      let key = owner.settingKey(child)
      if key in settings:
        fail("duplicate desktop profile setting " & key)
      settings.incl(key)
      result[owner].values.add(
        ProfileValue(key: key, encoded: child.inline(), provenance: expanded.provenance)
      )
  if not schemaSeen:
    fail("desktop profile has no schema declaration")

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
        owner.validateSetting(child)
        let key = owner.settingKey(child)
        if key in settings:
          fail("duplicate authority candidate setting " & key)
        settings.incl(key)
        result.values.add(
          ProfileValue(
            key: key,
            encoded: child.inline(),
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
