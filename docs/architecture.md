# Hagia Architecture

Hagia is the standalone Sophia-native successor to Triad's spatial-policy
ideas. It is not a compositor, a River compatibility layer, or a privileged
Sophia component.

## Ownership

Sophia Engine owns physical input, output state, scene validation, atomic
commit, rendering, and scanout. The Sophia session owns process supervision,
application launch, logout, and endpoint admission. Hagia owns only its private
spatial-policy model and bounded proposals.

Hagia never receives client titles, classes, application IDs, PIDs, paths,
namespaces, XIDs, pixels, renderer handles, raw input, or portal payloads. The
policy model stores stable Hagia IDs; opaque Sophia surface and output IDs stay
inside `src/sophia`.

The detailed allocation of retained Triad features is recorded in
[`capability-map.md`](capability-map.md). That ledger also records the River and
Niri lessons used by the port without treating either Wayland compositor as a
Sophia dependency or authority model.

Port completion is defined by the
[`triad-port-ledger.md`](triad-port-ledger.md). The initial fixed profile is an
experimental boundary proof, not the revision-2 feature ceiling. Retained
Triad behavior may expose missing WM facts or operations while it is ported, so
`sophia_wm_v1` must remain revisable until that ledger closes.

The engineering form of this port is normative in the
[style guide](style-guide.md), [data-oriented design](data-oriented-design.md),
and [DRY principles](dry-principles.md).

## Layers

- `src/policy/types.nim` contains passive logical IDs and policy records.
- `src/policy/state.nim` owns indexed mutations and invariants.
- `src/policy/reducer.nim` maps typed messages to pure candidate updates and intents.
- `src/policy/projection.nim` computes output projections without mutation.
- `src/runtime/reducer.nim` owns connection, candidate, settlement, and effect state.
- `src/runtime/effect_executor.nim` executes injected outer I/O and returns typed
  completion messages.
- `src/config` discovers, expands, partitions, stages, and migrates desktop profiles.
- `src/observability.nim` separates redacted Chronicles operations from the
  opt-in, schema-versioned evidence stream.
- `src/sophia/wm_v1.nim` implements the independent fixed wire.
- `src/sophia/policy_adapter.nim` reconciles complete Sophia snapshots and
  lowers logical projections back to current opaque identities.
- `src/sophia/policy_session.nim` stages private candidates and promotes only
  projections that Sophia explicitly commits.
- `src/sophia/policy_checkpoint.nim` validates and atomically replaces the
  optional private session checkpoint.
- `src/sophia/policy_client.nim` owns bounded transport sequencing only.

The adapter exposes a snapshot to policy only after the complete begin/chunk/end
transfer settles. A projection completely replaces every affected output.
Rejected or interrupted work is discarded before it can mutate Hagia's last
committed model or the Engine-owned scene.

## Triad Port Boundary

The port starts with Triad's useful architecture: typed logical identities,
tag-first membership, stable views, explicit state transitions, and pure layout
projection. It does not start by copying Triad's runtime tree. River handles,
Wayland protocols, shell surfaces, output management, process launching,
metadata rules, screenshots, input configuration, and compositor-shaped state
remain outside Hagia policy.

Tags and views are private Hagia data. Each window has a nonempty `TagId` set and
one home output. The checked-in profile defines nine shared tag slots; every
output owns nine distinct stable views that select those slots. Sharing the
bounded slots preserves conventional cross-output view semantics and supports
all sixteen protocol outputs without conflating identity with a tag mask. A window
is eligible when its home output matches and its tags intersect the active
view. Sophia sees only the resulting ordered output projection.

Columns are stable logical entities. Each view retains its native layout
selection independently of dense storage order. The compiled cycle contains
scroller, tile, grid, monocle, and vertical scroller. Automatic scroller widths
divide the viewport deterministically; explicit widths use bounded Q16.16
scales and 64-bit intermediate arithmetic. All layout families emit final
integer target geometry. Hagia does not animate, render, or retain client
pixels.

## Recovery Direction

A complete Sophia snapshot is the restart boundary. Hagia reconciles it into a
candidate cloned from the last committed private model. A committed outcome
promotes that candidate; stale, invalid, timed-out, disconnected, malformed, or
interrupted attempts discard it. Connection loss terminates the client so the
Sophia supervisor owns restart and a fresh connection epoch.

The live recovery harness may arm one named, marker-bounded crash hook after
negotiation, complete snapshot assembly, projection phases, checkpoint writes,
or session-operation boundaries. These hooks are inert without the explicit
proof environment and never alter normal settlement semantics.

The adapter retains at most sixteen dormant exact `(output, generation)`
handles. The policy model stores only the corresponding logical affinity. Loss
migrates views, columns, and windows to a surviving output; an exact return
restores still-live preferred state. Reused opaque IDs with a new generation
receive new logical identities. An optional session-local checkpoint retains
the private adapter/model candidate across a new Hagia process. It is
size-bounded, written owner-only through a same-directory fsynced atomic
replacement, and validated before complete snapshot reconciliation. It is not
a portable configuration format. Sophia allocates the path inside its private
policy endpoint directory, so the file survives supervised child replacement
but is deleted when the owning session ends. A checkpoint write failure disables
further writes for that client epoch and reports a diagnostic; it does not turn
an optional recovery optimization into a policy-session failure.

After a restored checkpoint reconciles and its first projection commits, Hagia
advances its private generation and emits exactly one `PolicyDirty` request for
the complete live output set. The request contains no placement or private
identity. Sophia answers with an ordinary fresh snapshot/request cycle; normal
action cycles do not create redundant refreshes.

The revision-2 black-box proof keeps one authenticated connection and private
adapter across eleven Sophia-owned cycles: constrained single output,
two-output partition, output loss with migration, the same raw output returning
at a new generation, an ordered focus action, timeout discard, and successful
post-timeout recovery. Committed proposals must pass Sophia's canonical
reducer. Stale-scene and deliberately invalid candidates are also rejected and
discarded before later successful cycles. This is offline lifecycle evidence;
it does not claim live KMS hotplug or installed-session promotion.

## Management Lifecycle

Engine starts a policy cycle from a complete snapshot and one reduced cause.
Hagia stages the cause against a clone of its last committed model, returns a
complete projection for every affected output, and promotes the candidate only
after Engine reports a committed outcome. Non-idempotent actions remain
ordered; only replaceable scene refreshes and continuous interaction geometry
may coalesce.

Hagia may request a fresh cycle after a private configuration or policy change.
The request carries no geometry and grants no scene authority. Engine responds
with a new complete snapshot, validates the ordinary projection, and preserves
the last coherent scene while client sizes or presentation state settle.

Animation remains Engine state derived from committed and target geometry.
Hagia stores stable logical policy and emits integer targets; it neither drives
a frame clock nor retains animation snapshots.

Engine may reduce one captured pointer move or resize to a completed
interaction carrying an exact target handle and final output-local geometry.
Hagia validates that target against the complete snapshot, checks its movement
or resize capability and output bounds, and stores only committed floating
geometry. It receives no raw motion stream, button, device, or global pointer
history. Continuous interaction phases remain unnegotiated.

## Desktop Profile

The user-facing profile is `${XDG_CONFIG_HOME:-$HOME/.config}/hagia/config.kdl`.
Discovery prefers an explicit absolute path, the XDG file,
`/etc/hagia/config.kdl`, then compiled defaults. Top-level includes are
depth-first and bounded to depth 10, 64 owner-safe regular files, and one MiB
in aggregate. Cycles, duplicate settings, unknown ownership, and hard-control
overrides fail closed.

Expansion produces one SHA-256-identified `DesktopProfileGeneration` and seven
provenance-bearing authority candidates. Hagia consumes only the policy
candidate. Hagia prepares that candidate on a clone, reconciles configured
view count and admitted native layouts against stable live identities, validates
all relationships, and promotes only the complete candidate; preparation
failure leaves the prior model byte-for-byte checkpoint-equivalent. The trusted
Sophia session coordinator validates the complete
profile, stages exact owner-only fragments with the same generation and digest,
and passes Hagia only the immutable policy-fragment path. The executable
coordinator reducer requires
all seven authorities to prepare and activate that identity before promotion;
any failure emits generation-wide idempotent rollback while preserving the
last-known-good profile. Watched live reload remains disabled until Sophia wires
that barrier through dedicated authority protocols.

At startup, Sophia prepares the session fragment into bounded terminal,
browser, startup, and logout selectors and resolves them only against its
trusted application registry. Explicit CLI/session mappings remain superior.
For a normal native-policy session, any shortcut that names an unavailable
session capability rejects the profile before graphical startup; no executable
path or argument crosses into Hagia.

Sophia likewise prepares the input fragment into a typed startup candidate.
Keyboard RMLVO, repeat timing, and initial lock state overlay Sophia's effective
configuration with explicit CLI RMLVO values superior. Pointer configuration
lowers to a backend-owned libinput policy; unsupported requested settings fail
startup, and hot-plug configuration failure stops input acquisition instead of
silently degrading. Hagia receives no input candidate or device identity.
Device-scoped live activation and rollback remain part of the deferred shared
authority protocol.

The output fragment is also prepared into a typed, topology-independent
candidate before staging. It bounds exact connector identities, modes,
fixed-point scale, position, transform, enablement, a unique startup-focus
request, and VRR policy. This step performs no DRM/KMS operation; topology
reconciliation is a pure Sophia function over an immutable capability snapshot.
It preserves stable connector order and rejects unknown or disconnected
connectors, ambiguous/unavailable modes, unsupported scale/transform/VRR,
overlap, and all-dark results. Trusted snapshot construction, atomic KMS test,
activation, and rollback remain Sophia-owned and deferred.

Sophia's existing atomic scanout owner now provides the read-only side of that
trusted snapshot: Engine output identity, exact kernel connector identity,
bounded advertised and selected timings, and VRR property status. This reuses
the owned libdrm selection rather than creating a parallel discovery path.
A pure coordinator adapter joins those facts to Engine outputs by stable
identity and constructs the immutable configuration topology. It preserves
Engine semantic order, derives checked current positions, and rejects missing
or duplicate identities and selected-mode/pixel-size disagreement. It exposes
only the current backend's integer scale, normal transform, and completely
discovered VRR capability. Live owner wiring and activation remain deferred.

The semantic Triad migrator now lowers supported keyboard, XKB, mouse,
workspace-count/default-layout, terminal/logout, and named-output values into
those typed profile sections. Valueless flags become explicit booleans,
`mouse` becomes the global pointer candidate, `disabled` becomes canonical
enablement, and legacy adaptive-sync becomes typed VRR policy. Duplicate or
out-of-range values are reported as unsupported instead of inheriting Triad's
last-writer behavior. Physical output `layout` remains explicit in the report
but is not guessed: automatic scale and transform require the trusted topology
adapter before positions can be derived safely.
Sophia exposes the same complete typed preparation path through
`sophia config check --desktop-profile=/absolute/path`, allowing generated
profiles to fail before graphical startup without device discovery or
activation.

The shortcut fragment owns physical matching but not the invoked behavior.
Bindings therefore carry explicit `policy:` or `session:` targets. Both
independent profile implementations normalize chord identity, reject duplicate
or reserved emergency chords, cap the candidate at 256 bindings, and prohibit
pointer-to-session authority crossings before staging. The recorded Triad
baseline currently reduces to 41 safely representable startup bindings; all
137 source bindings remain present in the migration report. A separate
recorded daily-driver authority fixture proves the typed
input/output/session/workspace transformations.

## Observability

Chronicles emits redacted operational events at the level selected by
`HAGIA_LOG_LEVEL`. The separate `HAGIA_EVIDENCE_NDJSON` sink is disabled unless
an absolute path is supplied. Its schema contains only reducer, configuration,
settlement, checkpoint, and connection correlation fields; it excludes raw
Sophia handles and application metadata and rotates at bounded size.
