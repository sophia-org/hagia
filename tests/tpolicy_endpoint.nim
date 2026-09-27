import std/unittest
import config/policy_endpoint

suite "9P WM endpoint selection":
  test "missing and explicitly empty endpoints refuse":
    for endpoint in [
      selectPolicyEndpoint([], ""),
      selectPolicyEndpoint(["--9p-socket="], "/session/files"),
    ]:
      expect ValueError:
        endpoint.requirePolicyEndpoint()

  test "an explicit endpoint overrides the environment":
    let inherited = selectPolicyEndpoint([], "/session/files")
    check inherited.path == "/session/files"
    inherited.requirePolicyEndpoint()
    let explicit = selectPolicyEndpoint(
      ["--config=/profile", "--9p-socket=/files"], "/session/files"
    )
    check explicit.path == "/files"
    explicit.requirePolicyEndpoint()

  test "retired, unknown, valueless and repeated options refuse":
    for argument in [
      "--socket=/retired", "--socket=", "--socket", "--9p-socket", "--transport=auto",
      "--other",
    ]:
      expect ValueError:
        discard selectPolicyEndpoint([argument], "/session/files")
    expect ValueError:
      discard selectPolicyEndpoint(["--9p-socket=/first", "--9p-socket=/second"], "")
