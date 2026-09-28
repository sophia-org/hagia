#ifndef HAGIA_SDK_STOP_PEER_H
#define HAGIA_SDK_STOP_PEER_H
#include <stdint.h>
enum hagia_stop_script {
  HAGIA_STOP_MUTE = 0,        /* accept, never answer: Hagia waits in bootstrap */
  HAGIA_STOP_IDLE = 1,        /* commit the configuration, then send nothing */
  HAGIA_STOP_AMBIGUOUS = 2,   /* take custody of the first projection, no outcome */
  HAGIA_STOP_COMMIT_THEN = 3  /* commit one projection, then as AMBIGUOUS */
};
enum hagia_stop_stage {
  HAGIA_STOP_WAITING = 0,
  HAGIA_STOP_CONNECTED = 1,
  HAGIA_STOP_IDLE_READ = 2,   /* configuration committed, blocking read posted */
  HAGIA_STOP_UNSETTLED = 3    /* last projection held, blocking read posted */
};
struct hagia_sdk_stop_peer {
  unsigned script;
  /* Written by the peer thread; `stage` is read concurrently. */
  unsigned stage, configurations, projections, closed;
  int status;
};
void hagia_sdk_stop_peer(int listener, struct hagia_sdk_stop_peer *state);
#endif
