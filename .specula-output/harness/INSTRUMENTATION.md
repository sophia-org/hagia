# Instrumentation Status

The opt-in NDJSON sink in `src/observability.nim` supplies the bounded event
envelope. The startup lifecycle trace is checked in at
`traces/startup.ndjson`. Per-authority prepare events remain a coordinator-side
integration point because live cross-authority reload is deliberately deferred.
