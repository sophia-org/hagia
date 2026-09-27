## The only build and FFI boundary for the signed, vendored desktop SDK.
import std/os
import ../types/desktop_sdk
const sdkSource =
  currentSourcePath().parentDir.parentDir.parentDir /
  "vendor/sophia-desktop-sdk/source/src"
{.passC: "-I" & sdkSource.}
{.passC: "-I" & currentSourcePath().parentDir.}
{.compile: sdkSource / "nine_p/client.c".}
{.compile: sdkSource / "nine_p/replies.c".}
{.compile: sdkSource / "nine_p/requests.c".}
{.compile: sdkSource / "wm_files/bodies.c".}
{.compile: sdkSource / "wm_files/records.c".}
{.compile: sdkSource / "wm_files/rows.c".}
{.compile: sdkSource / "wm_files/sections.c".}
{.compile: sdkSource / "wm_session/bootstrap.c".}
{.compile: sdkSource / "wm_session/events.c".}
{.compile: sdkSource / "wm_session/session.c".}
{.compile: sdkSource / "wm_session/snapshot.c".}
{.compile: sdkSource / "wm_session/submission.c".}
{.push cdecl, gcsafe, raises: [].}
proc wfSnapshotOutputDecode*(
  src: pointer, bytes: csize_t, value: ptr WfSnapshotOutput
): cint {.importc: "sophia_wf_snapshot_output_decode", header: "sophia_wm_records.h".}

proc wfSnapshotOutputEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfSnapshotOutput
): cint {.importc: "sophia_wf_snapshot_output_encode", header: "sophia_wm_records.h".}

proc wfSnapshotSurfaceDecode*(
  src: pointer, bytes: csize_t, value: ptr WfSnapshotSurface
): cint {.importc: "sophia_wf_snapshot_surface_decode", header: "sophia_wm_records.h".}

proc wfSnapshotSurfaceEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfSnapshotSurface
): cint {.importc: "sophia_wf_snapshot_surface_encode", header: "sophia_wm_records.h".}

proc wfSnapshotActionDecode*(
  src: pointer, bytes: csize_t, value: ptr WfSnapshotAction
): cint {.importc: "sophia_wf_snapshot_action_decode", header: "sophia_wm_records.h".}

proc wfSnapshotActionEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfSnapshotAction
): cint {.importc: "sophia_wf_snapshot_action_encode", header: "sophia_wm_records.h".}

proc wfSnapshotSessionOperationDecode*(
  src: pointer, bytes: csize_t, value: ptr WfSnapshotSessionOperation
): cint {.
  importc: "sophia_wf_snapshot_session_operation_decode", header: "sophia_wm_records.h"
.}

proc wfSnapshotSessionOperationEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfSnapshotSessionOperation
): cint {.
  importc: "sophia_wf_snapshot_session_operation_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionOutputDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionOutput
): cint {.importc: "sophia_wf_projection_output_decode", header: "sophia_wm_records.h".}

proc wfProjectionOutputEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionOutput
): cint {.importc: "sophia_wf_projection_output_encode", header: "sophia_wm_records.h".}

proc wfProjectionPlacementDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionPlacement
): cint {.
  importc: "sophia_wf_projection_placement_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionPlacementEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionPlacement
): cint {.
  importc: "sophia_wf_projection_placement_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionIndicatorDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionIndicator
): cint {.
  importc: "sophia_wf_projection_indicator_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionIndicatorEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionIndicator
): cint {.
  importc: "sophia_wf_projection_indicator_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionOutputStatusDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionOutputStatus
): cint {.
  importc: "sophia_wf_projection_output_status_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionOutputStatusEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionOutputStatus
): cint {.
  importc: "sophia_wf_projection_output_status_encode", header: "sophia_wm_records.h"
.}

proc wfSnapshotSurfaceClassificationDecode*(
  src: pointer, bytes: csize_t, value: ptr WfSnapshotSurfaceClassification
): cint {.
  importc: "sophia_wf_snapshot_surface_classification_decode",
  header: "sophia_wm_records.h"
.}

proc wfSnapshotSurfaceClassificationEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfSnapshotSurfaceClassification
): cint {.
  importc: "sophia_wf_snapshot_surface_classification_encode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionLaunchContextDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionLaunchContext
): cint {.
  importc: "sophia_wf_projection_launch_context_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionLaunchContextEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionLaunchContext
): cint {.
  importc: "sophia_wf_projection_launch_context_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionOutputLaunchContextDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionOutputLaunchContext
): cint {.
  importc: "sophia_wf_projection_output_launch_context_decode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionOutputLaunchContextEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionOutputLaunchContext
): cint {.
  importc: "sophia_wf_projection_output_launch_context_encode",
  header: "sophia_wm_records.h"
.}

proc wfSnapshotLaunchOriginDecode*(
  src: pointer, bytes: csize_t, value: ptr WfSnapshotLaunchOrigin
): cint {.
  importc: "sophia_wf_snapshot_launch_origin_decode", header: "sophia_wm_records.h"
.}

proc wfSnapshotLaunchOriginEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfSnapshotLaunchOrigin
): cint {.
  importc: "sophia_wf_snapshot_launch_origin_encode", header: "sophia_wm_records.h"
.}

proc wfSnapshotOutputPolicyKeyDecode*(
  src: pointer, bytes: csize_t, value: ptr WfSnapshotOutputPolicyKey
): cint {.
  importc: "sophia_wf_snapshot_output_policy_key_decode", header: "sophia_wm_records.h"
.}

proc wfSnapshotOutputPolicyKeyEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfSnapshotOutputPolicyKey
): cint {.
  importc: "sophia_wf_snapshot_output_policy_key_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionTabGroupDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionTabGroup
): cint {.
  importc: "sophia_wf_projection_tab_group_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionTabGroupEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionTabGroup
): cint {.
  importc: "sophia_wf_projection_tab_group_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionTabMemberDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionTabMember
): cint {.
  importc: "sophia_wf_projection_tab_member_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionTabMemberEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionTabMember
): cint {.
  importc: "sophia_wf_projection_tab_member_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionTranslationGroupDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionTranslationGroup
): cint {.
  importc: "sophia_wf_projection_translation_group_decode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionTranslationGroupEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionTranslationGroup
): cint {.
  importc: "sophia_wf_projection_translation_group_encode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionTranslationMemberDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionTranslationMember
): cint {.
  importc: "sophia_wf_projection_translation_member_decode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionTranslationMemberEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionTranslationMember
): cint {.
  importc: "sophia_wf_projection_translation_member_encode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionPresentation
): cint {.
  importc: "sophia_wf_projection_presentation_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionPresentation
): cint {.
  importc: "sophia_wf_projection_presentation_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationOutputDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionPresentationOutput
): cint {.
  importc: "sophia_wf_projection_presentation_output_decode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationOutputEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionPresentationOutput
): cint {.
  importc: "sophia_wf_projection_presentation_output_encode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionSurfaceInstanceDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionSurfaceInstance
): cint {.
  importc: "sophia_wf_projection_surface_instance_decode", header: "sophia_wm_records.h"
.}

proc wfProjectionSurfaceInstanceEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionSurfaceInstance
): cint {.
  importc: "sophia_wf_projection_surface_instance_encode", header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationRegionDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionPresentationRegion
): cint {.
  importc: "sophia_wf_projection_presentation_region_decode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationRegionEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionPresentationRegion
): cint {.
  importc: "sophia_wf_projection_presentation_region_encode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationBindingDecode*(
  src: pointer, bytes: csize_t, value: ptr WfProjectionPresentationBinding
): cint {.
  importc: "sophia_wf_projection_presentation_binding_decode",
  header: "sophia_wm_records.h"
.}

proc wfProjectionPresentationBindingEncode*(
  dst: pointer, bytes: csize_t, value: ptr WfProjectionPresentationBinding
): cint {.
  importc: "sophia_wf_projection_presentation_binding_encode",
  header: "sophia_wm_records.h"
.}

proc wfDecode*(
  src: pointer, bytes: csize_t, selected: uint64, value: ptr WfRecord
): cint {.importc: "sophia_wf_decode", header: "sophia_wm_files.h".}

proc wfEncode*(
  dst: pointer,
  capacity: csize_t,
  selected: uint64,
  value: ptr WfRecord,
  bytes: ptr csize_t,
): cint {.importc: "sophia_wf_encode", header: "sophia_wm_files.h".}

proc wsStateBytes*(): csize_t {.
  importc: "sophia_ws_state_bytes", header: "sophia_wm_session.h"
.}

proc wsStorageBytes*(
  msize: uint32
): csize_t {.importc: "sophia_ws_storage_bytes", header: "sophia_wm_session.h".}

proc wsOpenFd*(
  s: ptr Ws,
  fd: cint,
  config: ptr WsConfig,
  storage: pointer,
  bytes: csize_t,
  now: uint64,
): cint {.importc: "sophia_ws_open_fd", header: "sophia_wm_session.h".}

proc wsState*(
  s: ptr Ws
): cint {.importc: "sophia_ws_state", header: "sophia_wm_session.h".}

proc wsEpoch*(
  s: ptr Ws
): uint64 {.importc: "sophia_ws_epoch", header: "sophia_wm_session.h".}

proc wsCapabilities*(
  s: ptr Ws
): uint64 {.importc: "sophia_ws_capabilities", header: "sophia_wm_session.h".}

proc wsLimits*(
  s: ptr Ws
): ptr WfLimits {.importc: "sophia_ws_limits", header: "sophia_wm_session.h".}

proc wsPollFd*(
  s: ptr Ws
): cint {.importc: "sophia_ws_poll_fd", header: "sophia_wm_session.h".}

proc wsPollEvents*(
  s: ptr Ws
): cshort {.importc: "sophia_ws_poll_events", header: "sophia_wm_session.h".}

proc wsTimeout*(
  s: ptr Ws, now: uint64
): cint {.importc: "sophia_ws_timeout", header: "sophia_wm_session.h".}

proc wsObligations*(
  s: ptr Ws, value: ptr WsObligations
): cint {.importc: "sophia_ws_obligations", header: "sophia_wm_session.h".}

proc wsRemoteError*(
  s: ptr Ws
): uint32 {.importc: "sophia_ws_remote_error", header: "sophia_wm_session.h".}

proc wsDispatch*(
  s: ptr Ws, revents: cshort, budget: csize_t, now: uint64
): cint {.importc: "sophia_ws_dispatch", header: "sophia_wm_session.h".}

proc wsEvent*(
  s: ptr Ws, value: ptr WfRecord
): cint {.importc: "hagia_ws_event", header: "desktop_sdk_ffi.h".}

proc wsConsume*(
  s: ptr Ws
): cint {.importc: "sophia_ws_consume", header: "sophia_wm_session.h".}

proc wsSubmit*(
  s: ptr Ws, value: ptr WfRecord, deadline: uint64, ticket: ptr uint64
): cint {.importc: "sophia_ws_submit", header: "sophia_wm_session.h".}

proc wsOutcome*(
  s: ptr Ws, ticket: uint64, custody: ptr WsCustody, error: ptr uint32
): cint {.importc: "sophia_ws_outcome", header: "sophia_wm_session.h".}

proc wsNextTransaction*(
  s: ptr Ws, value: ptr uint64
): cint {.importc: "sophia_ws_next_transaction", header: "sophia_wm_session.h".}

proc wsSnapshot*(
  s: ptr Ws, deadline: uint64
): cint {.importc: "sophia_ws_snapshot", header: "sophia_wm_session.h".}

proc wsSnapshotResult*(
  s: ptr Ws, value: ptr WfRecord
): cint {.importc: "hagia_ws_snapshot_result", header: "desktop_sdk_ffi.h".}

proc wsSnapshotRelease*(
  s: ptr Ws
): cint {.importc: "sophia_ws_snapshot_release", header: "sophia_wm_session.h".}

proc wsClose*(
  s: ptr Ws
): void {.importc: "sophia_ws_close", header: "sophia_wm_session.h".}

{.pop.}
