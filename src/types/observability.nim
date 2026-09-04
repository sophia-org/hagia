## Passive operational evidence records. Emission, level selection, and log
## rotation live in `src/observability.nim`. Evidence is a record of what
## happened and never carries authority to change policy.

const
  evidenceSchema* = 2
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
    ## `kind` classifies; `event` names. Schema 1 carried only the class, so a
    ## reader of the structured stream could not tell a checkpoint save from a
    ## checkpoint discard without the unstructured Chronicles line beside it,
    ## which in a supervised session belongs to Sophia's capture rather than to
    ## Hagia. `sequence` orders records within a second, which the one-second
    ## timestamp cannot.
    kind*: EvidenceKind
    event*: string
    epoch*, generation*, requestId*, transaction*: uint64
    status*: string
    digest*: string
