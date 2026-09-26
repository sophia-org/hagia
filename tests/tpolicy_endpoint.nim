import std/unittest
import config/policy_endpoint
import types/policy_endpoint

suite "explicit WM endpoint selection":
  test "absence keeps current IPC and the legacy missing-path refusal":
    let endpoint = selectPolicyEndpoint([], "", "")
    check endpoint.kind == PolicyEndpointKind.currentIpc
    check endpoint.path == ""
    try:
      endpoint.requirePolicyEndpoint()
      check false
    except ValueError as error:
      check error.msg == "hagia: SOPHIA_WM_SOCKET or --socket is required"

  test "each environment selects only its own wire":
    let current = selectPolicyEndpoint([], "/session/current", "")
    check current.kind == PolicyEndpointKind.currentIpc
    check current.path == "/session/current"
    current.requirePolicyEndpoint()
    let files = selectPolicyEndpoint([], "", "/session/files")
    check files.kind == PolicyEndpointKind.wmFiles
    check files.path == "/session/files"
    files.requirePolicyEndpoint()

  test "explicit paths override only their corresponding environment":
    let current = selectPolicyEndpoint(
      ["--config=/profile", "--socket=/first", "--socket=/last"], "/session/current", ""
    )
    check current.kind == PolicyEndpointKind.currentIpc
    check current.path == "/last"
    let files = selectPolicyEndpoint(["--9p-socket=/files"], "", "/session/files")
    check files.kind == PolicyEndpointKind.wmFiles
    check files.path == "/files"

  test "dual environments and mixed explicit selections refuse":
    expect ValueError:
      discard selectPolicyEndpoint([], "/current", "/files")
    expect ValueError:
      discard selectPolicyEndpoint(["--socket=/current"], "", "/files")
    expect ValueError:
      discard selectPolicyEndpoint(["--9p-socket=/files"], "/current", "")
    expect ValueError:
      discard selectPolicyEndpoint(["--socket=/current", "--9p-socket=/files"], "", "")
    expect ValueError:
      discard selectPolicyEndpoint(["--socket=", "--9p-socket=/files"], "", "")
    expect ValueError:
      discard selectPolicyEndpoint(["--9p-socket="], "/current", "/files")

  test "an empty override cannot fall back to another path":
    let current = selectPolicyEndpoint(["--socket="], "/session/current", "")
    check current.path == ""
    expect ValueError:
      current.requirePolicyEndpoint()
    let files = selectPolicyEndpoint(["--9p-socket="], "", "/session/files")
    check files.kind == PolicyEndpointKind.wmFiles
    check files.path == ""
    try:
      files.requirePolicyEndpoint()
      check false
    except ValueError as error:
      check error.msg == "hagia: SOPHIA_WM_9P_SOCKET or --9p-socket is required"

  test "unknown or valueless options retain strict argument handling":
    for argument in ["--socket", "--9p-socket", "--transport=auto", "--other"]:
      try:
        discard selectPolicyEndpoint([argument], "/session/current", "")
        check false
      except ValueError as error:
        check error.msg == "unknown option " & argument & "; try hagia --help"
