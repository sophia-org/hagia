## Explicit WM wire selection. Paths name Session-owned endpoints; neither
## their contents nor a failed connection can select another transport.
type
  PolicyEndpointKind* {.pure.} = enum
    currentIpc
    wmFiles

  PolicyEndpoint* = object
    kind*: PolicyEndpointKind
    path*: string
