#define _POSIX_C_SOURCE 200809L
#include "sdk_admission_peer.h"
#include "../../vendor/sophia-desktop-sdk/source/src/tests/wm_session_peer.h"
#include <time.h>

/* Test-only protocol engine from the pinned SDK. This tests Hagia's offer
 * construction and path wrapper, not an independent encoder or real Session. */
static uint64_t milliseconds(void) {
  struct timespec value;
  assert(!clock_gettime(CLOCK_MONOTONIC, &value));
  return (uint64_t)value.tv_sec * 1000 + (uint64_t)value.tv_nsec / 1000000;
}
void hagia_sdk_admission_peer(int fd, uint64_t ceiling, uint64_t selected, unsigned profile_required,
                             struct hagia_sdk_peer_result *result) {
  struct wm_peer *peer = calloc(1, sizeof(*peer));
  struct sophia_wf_record limits = {0};
  uint64_t deadline = milliseconds() + 4000;
  size_t length;
  assert(peer);
  memset(result, 0, sizeof(*result));
  peer->fd = fd;
  peer->selected = selected;
  peer->submit_count = 24;
  peer->ack_count = 16;
  peer->submit_error = 13;
  limits.header.kind = SOPHIA_WF_LIMITS;
  limits.header.epoch = WP_EPOCH;
  limits.value.limits = (struct sophia_wf_limits){ceiling, 1048576, 1048576,
                                                64, 32, 12000, 4000, (uint16_t)profile_required};
  assert(!sophia_wf_encode(peer->limits, sizeof(peer->limits), 0, &limits, &length));
  result->status = -1;
  while (milliseconds() < deadline) {
    struct pollfd ready = {fd, POLLIN, 0};
    ssize_t count;
    int status = poll(&ready, 1, 20);
    if (status < 0 && errno == EINTR)
      continue;
    assert(status >= 0);
    if (!status)
      continue;
    count = recv(fd, peer->input + peer->used,
                 sizeof(peer->input) - peer->used, 0);
    if (!count) {
      result->status = 0;
      break;
    }
    assert(count > 0);
    peer->used += (size_t)count;
    while (peer->used >= 4 && wp_get(peer->input, 4) <= peer->used) {
      const uint8_t *request = peer->input;
      size_t bytes = (size_t)wp_get(request, 4);
      assert(bytes >= 7);
      if (request[4] == 118 && peer->files[wp_get(request + 7, 4)] == WP_SUBMIT) {
        struct sophia_wf_record value;
        assert(!sophia_wf_decode(peer->tx, peer->tx_size, WP_CAPS, &value));
        if (value.header.kind == SOPHIA_WF_NEGOTIATE) {
          result->required = value.value.negotiate.required;
          result->optional = value.value.negotiate.optional;
          ++result->offers;
        } else if (value.header.kind == SOPHIA_WF_CONFIGURATION)
          ++result->configurations;
      }
      wp_request(peer, request);
      peer->used -= bytes;
      memmove(peer->input, peer->input + bytes, peer->used);
    }
    wp_events(peer);
  }
  close(fd);
  free(peer);
}
