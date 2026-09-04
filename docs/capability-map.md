# Hagia Capability Map

This ledger records which parts of Triad belong in Hagia and which require a
different Sophia authority. It is an ownership map, not a promise to reproduce
Triad's River-facing runtime or to combine a desktop into one privileged
process.

## Reference Lessons

Triad is the product baseline for retained spatial-policy behavior. River shows
how a compositor can keep one replaceable window-management peer, preserve the
last rendered state while that peer is absent, let policy request another
management cycle, and separate client-size negotiation from final placement.
Sophia retains those lifecycle lessons while keeping physical input, client
protocols, rendering, and shell authority outside the WM.

Niri is a Rust implementation reference for stable logical layout state,
original-output affinity, transactional configuration, typed state streams,
property testing, and the separation of layout targets from animation and
rendering. Its monolithic compositor and metadata-rich IPC are not interfaces
for Hagia to copy.

None of these repositories is a Hagia runtime or build dependency.

## Capability Ownership

| Triad capability | Sophia owner | Hagia status | Required interface or evidence |
| --- | --- | --- | --- |
| Stable tags, views, columns, and logical IDs | Hagia | Implemented | Pure model and reconciliation tests |
| Scrolling and additional retained layouts | Hagia policy; visible tabs and feedback in Narthex | Native scroller, tile, grid, monocle, and vertical-scroller cycle implemented; structural and Janet layouts remain open | Deterministic geometry, constraint, transition, and shell correspondence tests |
| Focus, movement, grouping, and layout actions | Hagia, triggered by Engine-owned opaque actions | Focus, view, output focus/move, consume/expel, size, and layout-cycle actions implemented | `sophia_wm_v1` action causes and ordered action tests |
| Output-local views and reconnect affinity | Hagia over Engine output facts | Nine-view actions and affinity implemented | Work rectangles, multi-output proposals, loss/return tests |
| Floating, fullscreen, maximize, minimize, and scratchpads | Hagia policy; Engine validates and presents | Floating, presentation, and bounded standard/named scratchpad reducers implemented; frontend X state signaling remains open | Reduced kinds/state, presentation decisions, restore tests, frontend state evidence |
| Pointer move and resize | Engine grab and hit testing; Hagia geometry policy | One bounded completed interaction implemented | Reduced final interaction cause; continuous updates deferred |
| Policy reload or private policy command | Hagia may request a new cycle; Engine remains scene authority | Restored-checkpoint adoption emits one bounded generational refresh; general reload is deferred | Complete fresh snapshot after `PolicyDirty`; future candidate-validated reload |
| Policy checkpoint and restart | Hagia checkpoint; Sophia session supervision | Bounded owner-only atomic session checkpoint plus in-process state | Installed physical restore proof |
| Keyboard matching and physical gestures | Engine | Outside Hagia | Registered opaque actions; no raw input crosses the wire |
| Client state, pixels, configure delivery, and presentation | Engine and frontend authority | Outside Hagia | Settled snapshot generations and last-good preservation |
| Application placement rules | Trusted classification and launch-provenance broker | Deferred | Opaque placement grants; no title, class, PID, or path |
| Overview, switcher, panels, tabs, toast, and visible chrome | Narthex, a separately admitted shell client, with Engine rendering | Switcher and work-area reservation implemented in Narthex; overview, panels, tabs, and toast deferred | `sophia_shell_v1`; not WM IPC |
| Launch, logout, lock, output power, and configuration | Sophia session or dedicated authority | Terminal, browser, close, and logout slot requests implemented; other services deferred | Advertised opaque operations or role-specific interfaces |
| Screenshot, capture, clipboard, drag-and-drop, files, and notifications | Sophia portals | Deferred | Explicit grants and bounded payload handoff |
| Status and diagnostics | Redacted shell/status and diagnostic interfaces | Deferred | Full initial state plus typed bounded updates |
| KDL configuration and Janet policy/layouts | Hagia, within bounded policy authority | Retained declarative KDL path complete; Janet excluded from the revision-3 freeze profile | Keep candidate validation and atomic activation stable; model bounded evaluation and deterministic fallback before any post-freeze Janet addition |

The complete retained-behavior inventory and closed revision-3 gate are in
[`triad-port-ledger.md`](triad-port-ledger.md). A feature assigned to a shell,
session service, broker, or portal still counts toward the Hagia desktop port;
it does not acquire WM authority merely to keep the old Triad process shape.

## Interface Rules

`sophia_wm_v1` is a spatial-policy interface. It carries complete opaque scene
facts, reduced causes, and complete affected-output projections. It does not
become Triad's general JSON command socket.

Non-idempotent action activations retain order. Scene refreshes and continuous
pointer geometry may coalesce, but focus, movement, view, and layout actions do
not. Hagia can ask Engine for a fresh management cycle after private state or
configuration changes; it cannot submit an unsolicited scene mutation.

A projection is committed only after frontend state and renderable content have
settled. Until then, Engine preserves the previous coherent scene. If a client
settles to different authoritative facts, Engine sends a fresh complete
snapshot rather than silently changing Hagia's proposal.

Shell, session, broker, and portal clients receive separate endpoints and
capabilities. A combined desktop may contain several such clients, but no one
connection inherits another role's authority.
