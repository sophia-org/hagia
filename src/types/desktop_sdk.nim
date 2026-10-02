## Thin declarations for the pinned C SDK public headers. No private layouts.
type
  WsCustody* {.
    importc: "enum sophia_ws_custody",
    header: "sophia_wm_session.h",
    size: sizeof(cint),
    pure
  .} = enum
    unavailable
    admittedLocal
    issued
    submitted
    refused
    droppedUnsent
    unknownDisconnected

  WfCycleValue* {.union, bycopy.} = object
    action* {.importc: "action".}: WfAction
    focus* {.importc: "focus".}: WfSurface
    pointerFocus* {.importc: "pointer_focus".}: WfPointerFocus
    interaction* {.importc: "interaction".}: WfInteraction
    outputAction* {.importc: "output_action".}: WfOutputAction
    presentationAction* {.importc: "presentation_action".}: WfPresentationAction
    actionLifecycle* {.importc: "action_lifecycle".}: WfActionLifecycle
    chordAction* {.importc: "chord_action".}: WfChordAction

  WfRecordValue* {.union, bycopy.} = object
    limits* {.importc: "limits".}: WfLimits
    negotiate* {.importc: "negotiate".}: WfNegotiate
    selectedCapabilities* {.importc: "selected_capabilities".}: uint64
    profile* {.importc: "profile".}: WfProfile
    snapshot* {.importc: "snapshot".}: WfSnapshot
    projection* {.importc: "projection".}: WfProjection
    configuration* {.importc: "configuration".}: WfConfiguration
    cycle* {.importc: "cycle".}: WfCycle
    dirty* {.importc: "dirty".}: WfDirty
    sessionOperation* {.importc: "session_operation".}: WfSessionOperation
    configurationOutcome* {.importc: "configuration_outcome".}: WfConfigurationOutcome
    projectionOutcome* {.importc: "projection_outcome".}: WfProjectionOutcome
    sessionOperationOutcome* {.importc: "session_operation_outcome".}:
      WfSessionOperationOutcome
    presentationReceipt* {.importc: "presentation_receipt".}: WfPresentationReceipt
    submitted* {.importc: "submitted".}: WfSubmitted

  WfHeader* {.importc: "struct sophia_wf_header", header: "sophia_wm_files.h", bycopy.} = object
    kind* {.importc: "kind".}: uint16
    epoch* {.importc: "epoch".}: uint64
    submission* {.importc: "submission".}: uint64
    sequence* {.importc: "sequence".}: uint64

  WfSurface* {.
    importc: "struct sophia_wf_surface", header: "sophia_wm_files.h", bycopy
  .} = object
    index* {.importc: "index".}: uint32
    generation* {.importc: "generation".}: uint32

  WfLimits* {.importc: "struct sophia_wf_limits", header: "sophia_wm_files.h", bycopy.} = object
    capabilityCeiling* {.importc: "capability_ceiling".}: uint64
    maxObjectBytes* {.importc: "max_object_bytes".}: uint32
    maxJournalBytes* {.importc: "max_journal_bytes".}: uint32
    maxJournalRecords* {.importc: "max_journal_records".}: uint16
    maxSections* {.importc: "max_sections".}: uint16
    assemblyTimeoutMs* {.importc: "assembly_timeout_ms".}: uint32
    sendTimeoutMs* {.importc: "send_timeout_ms".}: uint32
    profileRequired* {.importc: "profile_required".}: uint16

  WfNegotiate* {.
    importc: "struct sophia_wf_negotiate", header: "sophia_wm_files.h", bycopy
  .} = object
    required* {.importc: "required".}: uint64
    optional* {.importc: "optional".}: uint64

  WfProfile* {.
    importc: "struct sophia_wf_profile", header: "sophia_wm_files.h", bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    generation* {.importc: "generation".}: uint64
    digest* {.importc: "digest".}: array[32, uint8]
    outcome* {.importc: "outcome".}: uint16

  WfSnapshot* {.
    importc: "struct sophia_wf_snapshot", header: "sophia_wm_files.h", bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    sceneGeneration* {.importc: "scene_generation".}: uint64
    activeOutput* {.importc: "active_output".}: uint64

  WfProjection* {.
    importc: "struct sophia_wf_projection", header: "sophia_wm_files.h", bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    requestId* {.importc: "request_id".}: uint64
    baseGeneration* {.importc: "base_generation".}: uint64
    activeOutput* {.importc: "active_output".}: uint64

  WfConfiguration* {.
    importc: "struct sophia_wf_configuration", header: "sophia_wm_files.h", bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    generation* {.importc: "generation".}: uint64
    styleBits* {.importc: "style_bits".}: uint16
    focusWidth* {.importc: "focus_width".}: uint32
    focusRgb* {.importc: "focus_rgb".}: uint32
    frameWidth* {.importc: "frame_width".}: uint32
    frameFocusedRgb* {.importc: "frame_focused_rgb".}: uint32
    frameUnfocusedRgb* {.importc: "frame_unfocused_rgb".}: uint32

  WfAction* {.importc: "struct sophia_wf_action", header: "sophia_wm_files.h", bycopy.} = object
    serial* {.importc: "serial".}: uint64
    action* {.importc: "action".}: uint64

  WfPointerFocus* {.
    importc: "struct sophia_wf_pointer_focus", header: "sophia_wm_files.h", bycopy
  .} = object
    output* {.importc: "output".}: uint64
    target* {.importc: "target".}: WfSurface

  WfInteraction* {.
    importc: "struct sophia_wf_interaction", header: "sophia_wm_files.h", bycopy
  .} = object
    phase* {.importc: "phase".}: uint16
    kind* {.importc: "kind".}: uint16
    axis* {.importc: "axis".}: uint16
    target* {.importc: "target".}: WfSurface
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32

  WfOutputAction* {.
    importc: "struct sophia_wf_output_action", header: "sophia_wm_files.h", bycopy
  .} = object
    serial* {.importc: "serial".}: uint64
    action* {.importc: "action".}: uint64
    output* {.importc: "output".}: uint64
    outputGeneration* {.importc: "output_generation".}: uint64

  WfPresentationAction* {.
    importc: "struct sophia_wf_presentation_action", header: "sophia_wm_files.h", bycopy
  .} = object
    serial* {.importc: "serial".}: uint64
    action* {.importc: "action".}: uint64
    publicationGeneration* {.importc: "publication_generation".}: uint64
    output* {.importc: "output".}: uint64
    outputGeneration* {.importc: "output_generation".}: uint64
    presentationEpoch* {.importc: "presentation_epoch".}: uint64
    targetId* {.importc: "target_id".}: uint64
    targetGeneration* {.importc: "target_generation".}: uint64

  WfActionLifecycle* {.
    importc: "struct sophia_wf_action_lifecycle", header: "sophia_wm_files.h", bycopy
  .} = object
    serial* {.importc: "serial".}: uint64
    action* {.importc: "action".}: uint64
    phase* {.importc: "phase".}: uint16
    reason* {.importc: "reason".}: uint16
    count* {.importc: "count".}: uint32

  WfChordAction* {.
    importc: "struct sophia_wf_chord_action", header: "sophia_wm_files.h", bycopy
  .} = object
    serial* {.importc: "serial".}: uint64
    chordSerial* {.importc: "chord_serial".}: uint64
    action* {.importc: "action".}: uint64

  WfConfigurationActionLifecycle* {.
    importc: "struct sophia_wf_configuration_action_lifecycle",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    action* {.importc: "action".}: uint64
    heldMs* {.importc: "held_ms".}: uint32

  WfCycle* {.importc: "struct sophia_wf_cycle", header: "sophia_wm_files.h", bycopy.} = object
    snapshotTransaction* {.importc: "snapshot_transaction".}: uint64
    requestTransaction* {.importc: "request_transaction".}: uint64
    requestId* {.importc: "request_id".}: uint64
    sceneGeneration* {.importc: "scene_generation".}: uint64
    policyGeneration* {.importc: "policy_generation".}: uint64
    cause* {.importc: "cause".}: uint16
    outputCount* {.importc: "output_count".}: uint16
    outputs* {.importc: "outputs".}: array[16, uint64]
    value* {.importc: "value".}: WfCycleValue

  WfDirty* {.importc: "struct sophia_wf_dirty", header: "sophia_wm_files.h", bycopy.} = object
    generation* {.importc: "generation".}: uint64
    outputCount* {.importc: "output_count".}: uint16
    outputs* {.importc: "outputs".}: array[16, uint64]

  WfSessionOperation* {.
    importc: "struct sophia_wf_session_operation", header: "sophia_wm_files.h", bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    requestId* {.importc: "request_id".}: uint64
    operation* {.importc: "operation".}: uint64
    target* {.importc: "target".}: WfSurface

  WfConfigurationOutcome* {.
    importc: "struct sophia_wf_configuration_outcome",
    header: "sophia_wm_files.h",
    bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    generation* {.importc: "generation".}: uint64
    outcome* {.importc: "outcome".}: uint16

  WfProjectionOutcome* {.
    importc: "struct sophia_wf_projection_outcome", header: "sophia_wm_files.h", bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    requestId* {.importc: "request_id".}: uint64
    sceneGeneration* {.importc: "scene_generation".}: uint64
    outcome* {.importc: "outcome".}: uint16
    expectSessionOperation* {.importc: "expect_session_operation".}: uint16

  WfSessionOperationOutcome* {.
    importc: "struct sophia_wf_session_operation_outcome",
    header: "sophia_wm_files.h",
    bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    requestId* {.importc: "request_id".}: uint64
    outcome* {.importc: "outcome".}: uint16

  WfPresentationReceipt* {.
    importc: "struct sophia_wf_presentation_receipt",
    header: "sophia_wm_files.h",
    bycopy
  .} = object
    transaction* {.importc: "transaction".}: uint64
    publicationGeneration* {.importc: "publication_generation".}: uint64
    output* {.importc: "output".}: uint64
    outputGeneration* {.importc: "output_generation".}: uint64
    presentationEpoch* {.importc: "presentation_epoch".}: uint64
    outcome* {.importc: "outcome".}: uint16

  WfSubmitted* {.
    importc: "struct sophia_wf_submitted", header: "sophia_wm_files.h", bycopy
  .} = object
    submission* {.importc: "submission".}: uint64
    kind* {.importc: "kind".}: uint16

  WfSection* {.
    importc: "struct sophia_wf_section", header: "sophia_wm_files.h", bycopy
  .} = object
    kind* {.importc: "kind".}: uint16
    count* {.importc: "count".}: uint32
    rows* {.importc: "rows".}: ptr UncheckedArray[uint8]
    bytes* {.importc: "bytes".}: csize_t

  WfRecord* {.importc: "struct sophia_wf_record", header: "sophia_wm_files.h", bycopy.} = object
    header* {.importc: "header".}: WfHeader
    sectionCount* {.importc: "section_count".}: uint16
    sections* {.importc: "sections".}: array[32, WfSection]
    value* {.importc: "value".}: WfRecordValue

  WfSnapshotOutput* {.
    importc: "struct sophia_wf_snapshot_output", header: "sophia_wm_records.h", bycopy
  .} = object
    output* {.importc: "output".}: uint64
    generation* {.importc: "generation".}: uint64
    focusIndex* {.importc: "focus_index".}: uint32
    focusGeneration* {.importc: "focus_generation".}: uint32
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32
    workX* {.importc: "work_x".}: int32
    workY* {.importc: "work_y".}: int32
    workWidth* {.importc: "work_width".}: int32
    workHeight* {.importc: "work_height".}: int32

  WfSnapshotSurface* {.
    importc: "struct sophia_wf_snapshot_surface", header: "sophia_wm_records.h", bycopy
  .} = object
    surfaceIndex* {.importc: "surface_index".}: uint32
    surfaceGeneration* {.importc: "surface_generation".}: uint32
    stateGeneration* {.importc: "state_generation".}: uint64
    currentOutput* {.importc: "current_output".}: uint64
    capabilityBits* {.importc: "capability_bits".}: uint16
    kind* {.importc: "kind".}: uint16
    requestStateBits* {.importc: "request_state_bits".}: uint16
    currentStateBits* {.importc: "current_state_bits".}: uint16
    transientIndex* {.importc: "transient_index".}: uint32
    transientGeneration* {.importc: "transient_generation".}: uint32
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32
    minWidth* {.importc: "min_width".}: int32
    minHeight* {.importc: "min_height".}: int32
    maxWidth* {.importc: "max_width".}: int32
    maxHeight* {.importc: "max_height".}: int32
    exactWidth* {.importc: "exact_width".}: int32
    exactHeight* {.importc: "exact_height".}: int32

  WfSnapshotAction* {.
    importc: "struct sophia_wf_snapshot_action", header: "sophia_wm_records.h", bycopy
  .} = object
    action* {.importc: "action".}: uint64
    sessionOperationSlot* {.importc: "session_operation_slot".}: uint16
    nameLen* {.importc: "name_len".}: uint16
    name* {.importc: "name".}: array[128, uint8]

  WfSnapshotSessionOperation* {.
    importc: "struct sophia_wf_snapshot_session_operation",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    operation* {.importc: "operation".}: uint64
    slot* {.importc: "slot".}: uint16
    targetBits* {.importc: "target_bits".}: uint16

  WfProjectionOutput* {.
    importc: "struct sophia_wf_projection_output", header: "sophia_wm_records.h", bycopy
  .} = object
    output* {.importc: "output".}: uint64
    placementCount* {.importc: "placement_count".}: uint32
    focusIndex* {.importc: "focus_index".}: uint32
    focusGeneration* {.importc: "focus_generation".}: uint32

  WfProjectionPlacement* {.
    importc: "struct sophia_wf_projection_placement",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    surfaceIndex* {.importc: "surface_index".}: uint32
    surfaceGeneration* {.importc: "surface_generation".}: uint32
    stateGeneration* {.importc: "state_generation".}: uint64
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32
    requestedWidth* {.importc: "requested_width".}: int32
    requestedHeight* {.importc: "requested_height".}: int32
    cropX* {.importc: "crop_x".}: int32
    cropY* {.importc: "crop_y".}: int32
    cropWidth* {.importc: "crop_width".}: int32
    cropHeight* {.importc: "crop_height".}: int32
    transform* {.importc: "transform".}: uint16
    presentationBits* {.importc: "presentation_bits".}: uint16

  WfProjectionIndicator* {.
    importc: "struct sophia_wf_projection_indicator",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    slot* {.importc: "slot".}: uint32
    indicator* {.importc: "indicator".}: uint64
    action* {.importc: "action".}: uint64
    stateBits* {.importc: "state_bits".}: uint16
    labelLen* {.importc: "label_len".}: uint16
    label* {.importc: "label".}: array[32, uint8]

  WfProjectionOutputStatus* {.
    importc: "struct sophia_wf_projection_output_status",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    focusBits* {.importc: "focus_bits".}: uint16
    layoutLen* {.importc: "layout_len".}: uint16
    layout* {.importc: "layout".}: array[32, uint8]

  WfSnapshotSurfaceClassification* {.
    importc: "struct sophia_wf_snapshot_surface_classification",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    surfaceIndex* {.importc: "surface_index".}: uint32
    surfaceGeneration* {.importc: "surface_generation".}: uint32
    classification* {.importc: "classification".}: uint64

  WfProjectionLaunchContext* {.
    importc: "struct sophia_wf_projection_launch_context",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    surfaceIndex* {.importc: "surface_index".}: uint32
    surfaceGeneration* {.importc: "surface_generation".}: uint32
    epoch* {.importc: "epoch".}: uint64
    token* {.importc: "token".}: uint64

  WfProjectionOutputLaunchContext* {.
    importc: "struct sophia_wf_projection_output_launch_context",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    generation* {.importc: "generation".}: uint64
    epoch* {.importc: "epoch".}: uint64
    token* {.importc: "token".}: uint64

  WfSnapshotLaunchOrigin* {.
    importc: "struct sophia_wf_snapshot_launch_origin",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    surfaceIndex* {.importc: "surface_index".}: uint32
    surfaceGeneration* {.importc: "surface_generation".}: uint32
    epoch* {.importc: "epoch".}: uint64
    token* {.importc: "token".}: uint64

  WfSnapshotOutputPolicyKey* {.
    importc: "struct sophia_wf_snapshot_output_policy_key",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    generation* {.importc: "generation".}: uint64
    policyKey* {.importc: "policy_key".}: uint64

  WfProjectionTabGroup* {.
    importc: "struct sophia_wf_projection_tab_group",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    group* {.importc: "group".}: uint64
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32
    selectedIndex* {.importc: "selected_index".}: uint32
    selectedGeneration* {.importc: "selected_generation".}: uint32
    memberCount* {.importc: "member_count".}: uint32
    focused* {.importc: "focused".}: uint32

  WfProjectionTabMember* {.
    importc: "struct sophia_wf_projection_tab_member",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    group* {.importc: "group".}: uint64
    surfaceIndex* {.importc: "surface_index".}: uint32
    surfaceGeneration* {.importc: "surface_generation".}: uint32

  WfProjectionTranslationGroup* {.
    importc: "struct sophia_wf_projection_translation_group",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    group* {.importc: "group".}: uint64
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    memberCount* {.importc: "member_count".}: uint32

  WfProjectionTranslationMember* {.
    importc: "struct sophia_wf_projection_translation_member",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    group* {.importc: "group".}: uint64
    surfaceIndex* {.importc: "surface_index".}: uint32
    surfaceGeneration* {.importc: "surface_generation".}: uint32

  WfProjectionPresentation* {.
    importc: "struct sophia_wf_projection_presentation",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    generation* {.importc: "generation".}: uint64
    keyboardOutput* {.importc: "keyboard_output".}: uint64
    outputCount* {.importc: "output_count".}: uint16
    bindingCount* {.importc: "binding_count".}: uint16
    instanceCount* {.importc: "instance_count".}: uint32
    regionCount* {.importc: "region_count".}: uint32

  WfProjectionPresentationOutput* {.
    importc: "struct sophia_wf_projection_presentation_output",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    output* {.importc: "output".}: uint64
    generation* {.importc: "generation".}: uint64
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32
    mode* {.importc: "mode".}: uint16

  WfProjectionSurfaceInstance* {.
    importc: "struct sophia_wf_projection_surface_instance",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    id* {.importc: "id".}: uint64
    generation* {.importc: "generation".}: uint64
    output* {.importc: "output".}: uint64
    sourceIndex* {.importc: "source_index".}: uint32
    sourceGeneration* {.importc: "source_generation".}: uint32
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32
    clipX* {.importc: "clip_x".}: int32
    clipY* {.importc: "clip_y".}: int32
    clipWidth* {.importc: "clip_width".}: int32
    clipHeight* {.importc: "clip_height".}: int32
    opacityMillis* {.importc: "opacity_millis".}: uint16
    zIndex* {.importc: "z_index".}: uint16
    action* {.importc: "action".}: uint64

  WfProjectionPresentationRegion* {.
    importc: "struct sophia_wf_projection_presentation_region",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    id* {.importc: "id".}: uint64
    generation* {.importc: "generation".}: uint64
    output* {.importc: "output".}: uint64
    x* {.importc: "x".}: int32
    y* {.importc: "y".}: int32
    width* {.importc: "width".}: int32
    height* {.importc: "height".}: int32
    clipX* {.importc: "clip_x".}: int32
    clipY* {.importc: "clip_y".}: int32
    clipWidth* {.importc: "clip_width".}: int32
    clipHeight* {.importc: "clip_height".}: int32
    zIndex* {.importc: "z_index".}: uint16
    role* {.importc: "role".}: uint16
    action* {.importc: "action".}: uint64

  WfProjectionPresentationBinding* {.
    importc: "struct sophia_wf_projection_presentation_binding",
    header: "sophia_wm_records.h",
    bycopy
  .} = object
    action* {.importc: "action".}: uint64
    keycode* {.importc: "keycode".}: uint32
    modifiers* {.importc: "modifiers".}: uint32

  Ws* {.importc: "struct sophia_ws", header: "sophia_wm_session.h", incompleteStruct.} = object

  WsConfig* {.
    importc: "struct sophia_ws_config", header: "sophia_wm_session.h", bycopy
  .} = object
    msize*: uint32
    offer*: WfNegotiate
    bootstrapDeadlineMs* {.importc: "bootstrap_deadline_ms".}: uint64

  WsObligations* {.
    importc: "struct sophia_ws_obligations", header: "sophia_wm_session.h", bycopy
  .} = object
    consumed*, acked*: uint64
    submittedSequence* {.importc: "submitted_sequence".}: uint64
    deadlineMs* {.importc: "deadline_ms".}: uint64
    retryAtMs* {.importc: "retry_at_ms".}: uint64
    eventPending* {.importc: "event_pending".}: uint8
    snapshotPending* {.importc: "snapshot_pending".}: uint8
    snapshotReady* {.importc: "snapshot_ready".}: uint8
    waitingForAck* {.importc: "waiting_for_ack".}: uint8
