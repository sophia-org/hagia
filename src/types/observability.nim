## Passive operational evidence records. Emission, level selection, and log
## rotation live in `src/observability.nim`. Evidence is a record of what
## happened and never carries authority to change policy.

const
  evidenceSchema* = 1
  maxEvidenceBytes* = 1_048_576'i64
  maxEvidenceFiles* = 4

type
  OperationalLevel* {.pure.} = enum
    debug
    info
    warning
    failure

  EvidenceKind* {.pure.} = enum
    reducer
    configuration
    settlement
    checkpoint
    connection

  EvidenceEvent* = object
    kind*: EvidenceKind
    epoch*, generation*, requestId*, transaction*: uint64
    status*: string
    digest*: string
