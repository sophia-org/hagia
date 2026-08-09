# Instrumentation Status

The opt-in NDJSON sink in `src/observability.nim` supplies the bounded event
envelope. The seven-authority prepare/activate startup trace is checked in at
`traces/startup.ndjson`. Production authority hooks remain a trusted
coordinator-side integration point; watched live reload is deliberately deferred.
