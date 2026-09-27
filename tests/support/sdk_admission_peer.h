#ifndef HAGIA_SDK_ADMISSION_PEER_H
#define HAGIA_SDK_ADMISSION_PEER_H
#include <stdint.h>
struct hagia_sdk_peer_result {
  uint64_t required, optional;
  unsigned offers, configurations;
  int status;
};
void hagia_sdk_admission_peer(int fd, uint64_t ceiling, uint64_t selected, unsigned profile_required,
                             struct hagia_sdk_peer_result *result);
#endif
