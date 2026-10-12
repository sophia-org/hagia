#ifndef HAGIA_DESKTOP_SDK_FFI_H
#define HAGIA_DESKTOP_SDK_FFI_H
#include "sophia_wm_session.h"
#include "sophia_launch_auth.h"

static inline size_t hagia_9p_state_bytes(void) { return sizeof(struct sophia_9p_client); }
static inline size_t hagia_la_state_bytes(void) { return sizeof(struct sophia_la_client); }

/* Nim has no const-qualified pointer type. Copy the public value rather than
 * cast away const. Snapshot section rows still borrow the SDK's pinned bytes
 * until snapshot_release; neither helper changes the session's event head. */
static inline int hagia_ws_event(struct sophia_ws *session,
                                struct sophia_wf_record *out) {
  const struct sophia_wf_record *record;
  int status = sophia_ws_event(session, &record);
  if (!status)
    *out = *record;
  return status;
}
static inline int hagia_ws_snapshot_result(struct sophia_ws *session,
                                          struct sophia_wf_record *out) {
  const struct sophia_wf_record *record;
  int status = sophia_ws_snapshot_result(session, &record);
  if (!status)
    *out = *record;
  return status;
}
#endif
