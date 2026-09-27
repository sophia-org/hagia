import ./desktop_sdk

## Rows stay owned until the SDK copies the complete candidate on submit.
type SdkCandidate* = object
  record*: WfRecord
  rows*: array[32, seq[byte]]
