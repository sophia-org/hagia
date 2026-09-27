import std/net
import std/os
import std/posix
import std/strutils
import std/tempfiles
import std/unittest
import config/profile
import types/config_values
import types/wm_v1
import sophia/[policy_transport, wm_file_client]
import support/sdk_admission_peer

## Path selection and candidate-derived capabilities through the real SDK.
## The scripted peer refuses configuration; no policy settlement is claimed.

proc candidate(focus, assignments: bool): AuthorityCandidate =
  result = AuthorityCandidate(
    authority: ProfileAuthority.policy,
    generation: 3,
    digest: repeat("07", 32),
    values: @[
      ProfileValue(
        key: "policy.focus-follows-mouse", encoded: "focus-follows-mouse #" & $focus
      )
    ],
  )
  if assignments:
    result.values.add(
      ProfileValue(key: "policy.workspace.1", encoded: "workspace 1 output-key=7")
    )

suite "file endpoint path wrapper":
  test "candidate settings become required capabilities on the connected endpoint":
    for focus in [false, true]:
      for assignments in [false, true]:
        let directory = createTempDir("hagia-file-client-", "")
        let path = directory / "wm.sock"
        let listener =
          newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP)
        listener.bindUnix(path)
        listener.listen()
        var log: PeerResult
        var thread: Thread[PeerTask]
        createThread(
          thread,
          servePeer,
          PeerTask(
            fd: cint(listener.getFd()),
            listener: true,
            ceiling: (1'u64 shl 20) - 1,
            selected:
              ((1'u64 shl 20) - 1) and not capabilityProfileActivation and
              (if focus: high(uint64) else: not capabilityPointerFocus),
            result: addr log,
          ),
        )
        try:
          expect PolicyClientError:
            path.runFilePolicySession(candidate(focus, assignments), false)
        finally:
          joinThread(thread)
          listener.close()
          removeDir(directory)
        check log.status == 0
        check log.offers == 1
        check log.configurations == 1
        check ((log.required and capabilityPointerFocus) != 0) == focus
        let outputBits = capabilityOutputActions or capabilityOutputPolicyKeys
        check ((log.required and outputBits) == outputBits) == assignments
        check (log.required and log.optional) == 0

  test "invalid settings refuse before connecting":
    let directory = createTempDir("hagia-file-client-invalid-", "")
    let path = directory / "wm.sock"
    let listener = newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP)
    listener.bindUnix(path)
    listener.listen()
    try:
      var invalid = candidate(false, false)
      invalid.values =
        @[ProfileValue(key: "policy.view-count", encoded: "view-count 0")]
      expect DesktopProfileError:
        path.runFilePolicySession(invalid, false)
      var descriptor = TPollfd(fd: cint(listener.getFd()), events: POLLIN)
      check posix.poll(addr descriptor, Tnfds(1), 0) == 0
    finally:
      listener.close()
      removeDir(directory)
