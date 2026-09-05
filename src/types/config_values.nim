import std/tables

## Passive desktop-profile records shared by the loader, the activation
## coordinator, and the policy candidate builder. Parsing, digesting, and the
## activation transition live in `src/config`; nothing here reads a file.

type
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

  EffectiveSetting* = object
    key*: string
    value*: string
    provenance*: ValueProvenance

  EffectiveAuthorityConfig* = object
    authority*: ProfileAuthority
    settings*: Table[string, EffectiveSetting]

  ProfileActivationPhase* {.pure.} = enum
    idle
    preparing
    prepared
    activating
    rollingBack

  ProfileActivationModel* = object
    phase*: ProfileActivationPhase
    activeGeneration*: uint64
    activeDigest*: string
    latestGeneration*: uint64
    candidateGeneration*: uint64
    candidateDigest*: string
    preparedAuthorities*: set[ProfileAuthority]
    activatedAuthorities*: set[ProfileAuthority]
    rollbackPending*: set[ProfileAuthority]

  ProfileActivationMsgKind* {.pure.} = enum
    beginCandidate
    authorityPrepared
    activationRequested
    authorityActivated
    rollbackCompleted

  ProfileActivationMsg* = object
    kind*: ProfileActivationMsgKind
    authority*: ProfileAuthority
    generation*: uint64
    digest*: string
    success*: bool

  ProfileActivationEffectKind* {.pure.} = enum
    prepareAuthority
    activateAuthority
    rollbackAuthority

  ProfileActivationEffect* = object
    kind*: ProfileActivationEffectKind
    authority*: ProfileAuthority
    generation*: uint64
    digest*: string

  ProfileActivationUpdate* = object
    model*: ProfileActivationModel
    effects*: seq[ProfileActivationEffect]

const
  maxProfileDepth* = 10
  maxProfileFiles* = 64
  maxProfileBytes* = 1_048_576'i64
  maxDesktopShortcutBindings* = 256
  allProfileAuthorities* = {ProfileAuthority.policy .. ProfileAuthority.broker}

const supportedLayoutNames* = [
  "scroller", "tile", "grid", "monocle", "vertical-scroller", "center-tile",
  "right-tile", "vertical-grid", "deck", "spiral", "tgmix", "frame-tree", "notion",
  "i3", "split-tree", "dwindle",
]

const bindableTriggerNames* = [
  ## Every trigger Sophia's shortcut authority can resolve to an evdev
  ## keycode. Hagia validates against this list because a chord it accepts
  ## but Sophia cannot bind fails the whole session at login, long after
  ## `hagia config check` said the profile was fine. Mirrors
  ## `desktop_shortcut_evdev_keycode` in Sophia's `shortcut_candidate.rs`;
  ## the cross-repository conformance gate keeps the two honest.
  ",", "-", ".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "=", "?", "[", "]",
  "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "a", "b",
  "backspace", "c", "d", "delete", "down", "e", "end", "enter", "escape", "f", "g",
  "grave", "h", "home", "i", "insert", "j", "k", "l", "left", "m", "n", "o", "p",
  "page_down", "page_up", "print", "q", "r", "return", "right", "s", "space", "t",
  "tab", "u", "up", "v", "w", "x", "y", "z",
]
