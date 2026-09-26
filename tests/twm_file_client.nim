import std/[net, os, posix, strutils, tempfiles, unittest]
import config/profile
import types/[config_values, wm_file_bodies, wm_files, wm_v1]
import sophia/[wm_file_bodies, wm_file_client]
import ninep/client
import support/wm_file_transcript

## Exercise the path wrapper and its candidate-derived offer. The prescribed
## peer refuses submit; this is neither admission nor Session settlement proof.

peerResults.open()

proc serveListener(script: PeerScript) {.thread.} =
  var descriptor = TPollfd(fd: script.fd, events: POLLIN)
  if posix.poll(addr descriptor, Tnfds(1), 2_000) <= 0:
    peerResults.send(PeerLog(failure: "wrapper did not connect"))
    return
  let accepted = posix.accept(SocketHandle(script.fd), nil, nil)
  if cint(accepted) < 0:
    peerResults.send(PeerLog(failure: "wrapper accept failed"))
    return
  serve(PeerScript(fd: cint(accepted), steps: script.steps))

proc offerSteps(): seq[PeerStep] =
  var api: seq[byte]
  for character in "sophia-wm-files version=1 output_transport=current_ipc\n":
    api.add(byte(character))
  let limits = WmFileHeader(kind: WmFileKind.limits, connectionEpoch: 9).encodeLimits(
    WmFileLimits(capabilityCeiling: (1'u64 shl 20) - 1)
  )
  @[versionStep(), attachStep()] & objectSteps(api, 10) & objectSteps(limits, 11) &
    @[
      walkStep(20),
      openStep(3, 20),
      walkStep(21),
      openStep(4, 21),
      walkStep(22),
      openStep(5, 22),
      walkStep(30),
      openStep(6, 30),
      writeStep(6),
      writeStep(4, refusal = 13),
    ]

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
        let steps = offerSteps()
        var thread: Thread[PeerScript]
        createThread(
          thread, serveListener, PeerScript(fd: cint(listener.getFd()), steps: steps)
        )
        try:
          expect NinepRemoteError:
            path.runFilePolicySession(candidate(focus, assignments), false)
        finally:
          joinThread(thread)
          listener.close()
          removeDir(directory)
        let log = peerResults.recv()
        check log.failure == ""
        check log.stepsDone == steps.len
        var offers = 0
        for request in log.seen:
          if request.kind == twrite and request.fid == 6:
            let offer = request.data.decodeNegotiate(9)
            check ((offer.required and capabilityPointerFocus) != 0) == focus
            let outputBits = capabilityOutputActions or capabilityOutputPolicyKeys
            check ((offer.required and outputBits) == outputBits) == assignments
            check (offer.required and offer.optional) == 0
            inc offers
        check offers == 1

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
