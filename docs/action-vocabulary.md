# The Policy Action Vocabulary

Hagia's action catalog is the list of things a keybinding can ask the window
manager to do. It grows; the wire it travels on does not. This document is the
rulebook for growing it, written once so every later tranche follows the same
shape.

## Why the frozen wire never blocks a new action

`sophia_wm_v1` revision 3 is frozen, and adding spatial commands to Hagia needs
no revision. The protocol carries an *opaque* action catalog: Hagia sends up to
256 entries of `(ordinal, session slot, name)`, Sophia binds triggers to names
it never interprets, and a shortcut arrives back as the ordinal Hagia chose.
Meaning lives entirely on this side. The freeze locked the transport, not the
vocabulary, and the protocol's direction rule — client to server, additive
forever — is exactly the direction a new action travels.

So every command below is Hagia-internal work: an enum entry, a reducer arm,
sometimes new model operations, and a profile binding. None of it touches
`sophia-stack`.

## The rules

### 1. Ordinals are append-only

`src/types/actions.nim` holds the enum, and its ordinals are a stable wire
contract: recorded profiles, policy traces, and the conformance corpus all
name actions by number. Never renumber an action, never reuse a retired
ordinal, and never leave a gap — `installConfiguration` sends
`ord(high(PolicyAction))` as the catalog count, so the range must stay
contiguous from 1. New actions append at the end. The catalog registers them
automatically; no encoder change is needed.

The ceiling is 256 actions. Hagia uses 84.

### 2. Names are Hagia's, not Triad's

An action's `profileName` is the semantic string Sophia binds against. New
actions get names that describe Hagia's model — `focus-column-next`, not
Triad's `focus-right`. Triad's spelling belongs in one place only: the
migration classifier, which maps the old string to the new action and reports
it as *transformed*. A migrated profile is rewritten into Hagia's vocabulary;
Triad's strings never become Hagia's.

### 3. Actions carry no arguments

An action is a bare ordinal, so a parameterized Triad command becomes one of
three things:

- **A pair of step actions.** `resize-width <delta>` is already `growColumn` /
  `shrinkColumn`; `adjust-gaps <delta>` follows the same shape, with the step
  size read from config rather than the binding.
- **A bounded family of slots.** Where Triad takes a name or index, Hagia
  declares the set in config and gets one action per slot — the idiom the nine
  view slots already use. Named scratchpads work this way.
- **A preset cycle.** Absolute setters like `master-ratio <v>` become a
  `cycle-…` action stepping through a list declared in config.

Commands addressing a specific window by id (`focus-window <id>`) stay out of
the catalog entirely. That is an activation, and activations arrive through the
shell's switcher and the broker, which is where the authority for naming
another client's surface belongs.

### 4. Registered is not the same as bound

Every action in the enum is registered with Sophia on connect. The shipped
profile binds only the keys a new user expects; the rest appear as commented
lines in `examples/config/default.kdl`. Registering costs nothing and keeps a
user's own binding one uncomment away.

### 5. A command's authority decides whether it can be an action at all

Only spatial policy belongs here. Triad commands whose authority is elsewhere
stay elsewhere and are recorded as such by the classifier: overview and MRU
listings are shell state, screenshots need a capture portal grant, spawning
and locking are session capabilities, pointer warping and keyboard layout are
input authority. These are not gaps in Hagia; they are other components' work.

## Native tabbed layouts

`frame-tree`, `notion`, and `i3` (`split-tree`) now have persistent private
model state and project only the active leaf or subtree. Their bar geometry
and opaque membership use Sophia's revision-3 extension lane. Narthex receives
sanitized descriptors through shell revision 2, and Sophia renders them using
its GPU composition path. No metadata enters Hagia.

See [native tabbed layouts](tabbed-layouts.md) for the actions, checkpoint
migration, empty-cell behavior, and explicit exclusions. Shell unavailability
leaves inert numbered bars while keyboard layout control continues.

## Adding one

1. Append the enum entry in `src/types/actions.nim`.
2. Add its `profileName` arm and, if it is a reducer action, its `applyAction`
   arm in `src/policy/actions.nim`. Session capabilities instead get a slot in
   `sessionOperationSlot` and must stay out of the reducer.
3. Put the behavior where it belongs: index mutations in `src/entities`,
   decisions in `src/systems`, geometry in `src/policy/projection.nim`. The
   reducer arm should read as one call.
4. Flip the Triad command's row in `src/config/migration_command.nim` from
   `excluded` to `transformed` in the same commit, naming the new action.
5. Bind it in `examples/config/default.kdl`, or add it commented, and update
   the binding counts pinned in `tests/tfoundation.nim`.
6. Add a reducer test and a migration test.
