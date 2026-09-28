#define _POSIX_C_SOURCE 200809L
#include "sdk_stop_peer.h"
#include "../../vendor/sophia-desktop-sdk/source/src/tests/wm_session_peer.h"
#include <time.h>

/* Scripted endpoint for the stop tests, driven by the pinned SDK's test-only
 * protocol engine. It holds Hagia at a chosen wait and records whether Hagia
 * closes the connection and how many candidates it submitted. It is not a
 * Session, an admission check or an Engine. */
static uint64_t milliseconds(void) {
  struct timespec value;
  assert(!clock_gettime(CLOCK_MONOTONIC, &value));
  return (uint64_t)value.tv_sec * 1000 + (uint64_t)value.tv_nsec / 1000000;
}
static void stage(struct hagia_sdk_stop_peer *state, unsigned value) {
  __atomic_store_n(&state->stage, value, __ATOMIC_SEQ_CST);
}
/* One output, no surfaces: the smallest complete scene Hagia projects. */
static void cycle(struct wm_peer *peer, uint64_t id) {
  struct sophia_wf_record value = {0};
  struct sophia_wf_snapshot_output row = {0};
  uint8_t bytes[56];
  size_t n;
  row.output = 10;
  row.generation = 1;
  row.width = row.work_width = 640;
  row.height = row.work_height = 480;
  assert(!sophia_wf_snapshot_output_encode(bytes, sizeof(bytes), &row));
  value.header.kind = SOPHIA_WF_SNAPSHOT;
  value.header.epoch = WP_EPOCH;
  value.value.snapshot = (struct sophia_wf_snapshot){70 + id, 8 + id, 10};
  value.section_count = 1;
  value.sections[0] = (struct sophia_wf_section){1, 1, bytes, sizeof(bytes)};
  assert(!sophia_wf_encode(peer->snapshot, sizeof(peer->snapshot), WP_CAPS,
                           &value, &n) &&
         n == sizeof(peer->snapshot));
  memset(&value, 0, sizeof(value));
  value.header.kind = SOPHIA_WF_CYCLE;
  value.value.cycle.snapshot_transaction = 70 + id;
  value.value.cycle.request_transaction = 80 + id;
  value.value.cycle.request_id = id;
  value.value.cycle.scene_generation = 8 + id;
  value.value.cycle.policy_generation = 1;
  value.value.cycle.output_count = 1;
  value.value.cycle.outputs[0] = 10;
  wp_record(peer, &value);
}
static void settle(struct hagia_sdk_stop_peer *state, struct wm_peer *peer,
                   const struct sophia_wf_record *candidate) {
  struct sophia_wf_record event = {0};
  if (candidate->header.kind == SOPHIA_WF_CONFIGURATION) {
    ++state->configurations;
    event.header.kind = SOPHIA_WF_CONFIGURATION_OUTCOME;
    event.value.configuration_outcome.transaction =
        candidate->value.configuration.transaction;
    event.value.configuration_outcome.generation =
        candidate->value.configuration.generation;
    event.value.configuration_outcome.outcome = 1;
    wp_record(peer, &event);
    if (state->script >= HAGIA_STOP_AMBIGUOUS)
      cycle(peer, 1);
  } else if (candidate->header.kind == SOPHIA_WF_PROJECTION) {
    ++state->projections;
    if (state->script != HAGIA_STOP_COMMIT_THEN || state->projections > 1)
      return; /* Custody is taken; the outcome never comes. */
    event.header.kind = SOPHIA_WF_PROJECTION_OUTCOME;
    event.value.projection_outcome.transaction =
        candidate->value.projection.transaction;
    event.value.projection_outcome.request_id =
        candidate->value.projection.request_id;
    event.value.projection_outcome.scene_generation = 9;
    event.value.projection_outcome.outcome = 1;
    wp_record(peer, &event);
    cycle(peer, 2);
  }
}
void hagia_sdk_stop_peer(int listener, struct hagia_sdk_stop_peer *state) {
  struct wm_peer *peer = calloc(1, sizeof(*peer));
  struct sophia_wf_record limits = {0};
  struct pollfd pending = {listener, POLLIN, 0};
  unsigned held = state->script == HAGIA_STOP_COMMIT_THEN ? 2 : 1;
  uint64_t deadline = milliseconds() + 20000;
  size_t length;
  int fd;
  assert(peer);
  state->status = -1;
  if (poll(&pending, 1, 10000) != 1 || (fd = accept(listener, NULL, NULL)) < 0) {
    state->status = -2;
    free(peer);
    return;
  }
  peer->fd = fd;
  peer->submit_count = 24;
  peer->ack_count = 16;
  limits.header.kind = SOPHIA_WF_LIMITS;
  limits.header.epoch = WP_EPOCH;
  limits.value.limits =
      (struct sophia_wf_limits){WP_CAPS, 1048576, 1048576, 64, 32, 12000, 4000, 0};
  assert(!sophia_wf_encode(peer->limits, sizeof(peer->limits), 0, &limits, &length));
  while (milliseconds() < deadline) {
    struct pollfd ready = {fd, POLLIN, 0};
    ssize_t count;
    int status = poll(&ready, 1, 20);
    if (status < 0 && errno == EINTR)
      continue;
    assert(status >= 0);
    if (status) {
      count = recv(fd, peer->input + peer->used, sizeof(peer->input) - peer->used, 0);
      if (count <= 0) {
        state->closed = 1;
        state->status = count == 0 ? 0 : -3;
        break;
      }
      if (!state->stage)
        stage(state, HAGIA_STOP_CONNECTED);
      if (state->script == HAGIA_STOP_MUTE)
        continue;
      peer->used += (size_t)count;
      while (peer->used >= 4 && wp_get(peer->input, 4) <= peer->used) {
        const uint8_t *request = peer->input;
        size_t bytes = (size_t)wp_get(request, 4);
        int submitted = request[4] == 118 && peer->files[wp_get(request + 7, 4)] == WP_SUBMIT;
        struct sophia_wf_record candidate;
        assert(bytes >= 7);
        if (submitted)
          assert(!sophia_wf_decode(peer->tx, peer->tx_size, WP_CAPS, &candidate));
        /* Select exactly Hagia's offer; admission policy is tested elsewhere. */
        if (submitted && candidate.header.kind == SOPHIA_WF_NEGOTIATE)
          peer->selected =
              candidate.value.negotiate.required | candidate.value.negotiate.optional;
        wp_request(peer, request);
        if (submitted && candidate.header.kind != SOPHIA_WF_NEGOTIATE)
          settle(state, peer, &candidate);
        peer->used -= bytes;
        memmove(peer->input, peer->input + bytes, peer->used);
      }
      wp_events(peer);
    }
    /* A posted read at the journal's end, with every event acknowledged, is
     * Hagia blocked in its wait rather than still working. */
    if (peer->events_pending && peer->event_offset == peer->journal_size &&
        peer->acked == peer->sequence && state->configurations) {
      if (state->script == HAGIA_STOP_IDLE)
        stage(state, HAGIA_STOP_IDLE_READ);
      else if (state->projections == held)
        stage(state, HAGIA_STOP_UNSETTLED);
    }
  }
  close(fd);
  free(peer);
}
