import ../types/[core, model]
import ./values

## Logical ID allocation. Generators increment before they issue, so zero is
## never an answer and a released identity is never reused.

proc nextRaw*(counter: var uint32, kind: string): uint32 =
  ## Ported from Triad's centralized nonzero logical-ID generator. Keeping the
  ## exhaustion check before increment makes wraparound terminal and testable.
  if counter == high(uint32):
    fail(kind & " identity space is exhausted")
  inc counter
  if counter == 0:
    fail(kind & " identity counter wrapped to zero")
  counter

proc allocateOutputId*(model: var PolicyModel): OutputId =
  OutputId(nextRaw(model.counters.outputs, "output"))

proc allocateViewId*(model: var PolicyModel): ViewId =
  ViewId(nextRaw(model.counters.views, "view"))

proc allocateWindowId*(model: var PolicyModel): WindowId =
  WindowId(nextRaw(model.counters.windows, "window"))

proc allocateColumnId*(model: var PolicyModel): ColumnId =
  ColumnId(nextRaw(model.counters.columns, "column"))

proc allocateGroupId*(model: var PolicyModel): GroupId =
  GroupId(nextRaw(model.counters.groups, "group"))
