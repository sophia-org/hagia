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

The engineering form of this port is normative in the
[style guide](style-guide.md), [data-oriented design](data-oriented-design.md),
and [DRY principles](dry-principles.md).

## Layers

- `src/policy/types.nim` contains passive logical IDs and policy records.
- `src/policy/state.nim` owns indexed mutations and invariants.
- `src/policy/projection.nim` computes output projections without mutation.
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

Tags and views are private Hagia data. Each window has a nonempty tag set and
one home output. The checked-in profile defines nine shared tag slots; every
output owns nine distinct stable views that select those slots. Sharing the
bounded slots preserves conventional cross-output view semantics and supports
all sixteen protocol outputs without exhausting the 64-bit tag mask. A window
is eligible when its home output matches and its tags intersect the active
view. Sophia sees only the resulting ordered output projection.

Columns are stable logical entities. The retained profile has one scrolling
layout only. Automatic widths divide the viewport deterministically; explicit
widths use bounded Q16.16 scales and 64-bit intermediate arithmetic. Hagia
emits final integer target geometry. It does not animate, render, or retain
client pixels.

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

The revision-1 black-box proof keeps one authenticated connection and private
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
