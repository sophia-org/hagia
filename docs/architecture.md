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
last-known-good profile. Every attempted generation advances a monotonic
counter even when rejected, so an old generation never re-enters admission and
delayed completions cannot alias a retry; counter exhaustion is terminal.
The generation/digest lifecycle, partial barriers, rollback, and stale
completions are exhaustively model checked by the repository's TLA+ gate.
Sophia now ports the same pure transition shape over its canonical authority,
generation, and digest types, with mirrored tests for the rejected-generation
reuse defect found during Hagia's formal-verification pass. Its startup-only
driver now completes both barriers or cancels the failing phase and attempts
generation-wide rollback, including every participant after a rollback
failure. Sophia also has one shared pure authority-participant transition model
instead of seven bespoke implementations. It consumes generations
monotonically, retains the last admitted full key, makes exact retries
idempotent, restores the exact previous active key, treats only strictly older
cleanup as stale, and rejects a same-generation digest mismatch. Because the
startup driver stops preparation after the first rejection but rolls all seven
authorities back, a skipped participant consumes the exact unseen rollback key
as a no-state tombstone. A test-only refinement executor drives the real
coordinator effects through seven independent participants and proves
convergence or exact single-authority recovery divergence at every failure
position. No production handler invokes that model yet. Startup may eventually
hide partial local activation behind the graphical launch gate; watched live
reload cannot use that assumption and remains disabled until a separate global
visibility and recovery protocol is proved and populated through dedicated
authorities.

Sophia's startup configuration now retains one canonical immutable typed
candidate bundle after verifying every raw authority candidate against the
profile's exact generation and digest. Input, output, session, and shortcut
consumers use that bundle; public policy setup no longer reparses the shortcut
section. Policy, shell, and broker payloads remain in the provenance-bearing
profile for their owning handlers. This narrows candidate ownership and removes
duplicate parsing without treating admission data as activated authority state.
A prepared-profile aggregate now returns the raw provenance-bearing generation,
its exact activation key, and the derived typed bundle from one load/prepare
pass. The validated raw-profile API delegates to that path and discards only the
derived bundle when a caller explicitly requests the raw view.

Sophia now has an authority-local staged-fragment admission function matching
this repository's independent policy-reader constraints. It reuses Sophia's
bounded owner-safe file checks, rejects symlinks and cross-authority sections,
requires the exact coordinator generation/digest, validates settings and
duplicates, and reconstructs the existing provenance-bearing raw candidate
DTO. Round-trip tests cover fragments for all seven authorities. The Nim reader
remains independent conformance evidence rather than a shared runtime
dependency.

Sophia now also centralizes one authority's participant identity and payload
ownership in a generic pure candidate slot. The slot holds only bounded active,
previous-active, and prepared payloads; it accepts either the canonical typed
candidate or an admitted raw fragment, delegates identity transitions to the
shared participant reducer, and mutates payload state only after that
transition succeeds. Exact retries compare semantic settings while ignoring
staging-path provenance, but authority, key, or payload conflicts fail without
changing either state. Exact rollback restores the previous payload. This is an
authority-local building block, not a coordinator-owned copy of all authority
state, and no production effect handler invokes it yet.

Sophia's offline coordinator refinement executor now uses seven of those slots
instead of identity-only participants. The existing failure-position matrix
therefore proves candidate payload promotion, complete last-known-good payload
restoration, exact rollback divergence, and deterministic recovery alongside
the coordinator and participant identities. A second integration case stages
the compiled profile, re-admits all seven owner-safe fragments through Sophia's
shared loader, and proves every semantic payload is promoted under the exact
shared key. This strengthens startup evidence without creating a production
slot collection or effect path.

Sophia's first production-owned preparation seam is now session-local and
pure. Explicit CLI application additions, arguments, startup order, and action
selectors are parsed once into a bounded immutable overlay. The session
authority applies that overlay and the canonical typed session candidate to a
clone of its trusted application registry, preserving CLI precedence and
discarding the clone on unknown, ambiguous, duplicate, or over-limit values.
This does not activate the participant or enable desktop-profile reload.
Trusted startup now retains the canonical typed session payload in a real
session-owned generic slot and derives the effective application configuration
from that slot's candidate. Tests require exact bundle/key parity and
`Prepared` phase; configuration assembly cannot promote the slot.
The generic slot now has one shared prepared-candidate constructor, avoiding
repeated initialization sequencing. Sophia's public shortcut owner uses it to
retain its own typed candidate and resolves registrations only from the slot
payload. Session and shortcut state remain with separate owners rather than a
coordinator-owned slot collection, and neither slot is promoted yet.
The startup typed bundle is now transient and partitioned exactly once. Session,
input, and output enter cohesive owner records backed by their separate
prepared slots; shortcut remains only as the transfer payload until its public
owner constructs the fourth slot. Keyboard/pointer overlay and output
reconciliation consume their owner payloads, leaving no long-lived centralized
bundle and changing no hardware state.

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
discovered VRR capability. Native startup now runs this projection and
reconciliation after creating the atomic owner but before launching graphical
clients. Failure aborts startup; success is recorded as reconciled but not
activated. Atomic testing, apply, and rollback remain deferred.

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
