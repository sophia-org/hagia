# WM SDK test migration

Hagia's production file client uses the vendored C SDK. Independent Nim record
encoders and decoders remain under `tests/support/wire`; production modules must
not import them. Their fixed-row, envelope, body, array and projection tests
remain in the contributor gate.

## Direct-client test disposition

The old `tfile_wire` scripted transcript fixed the implementation's fid numbers,
request sequence and adjustable assembly timeout. Those details are owned by the
SDK now. The corresponding properties have these owners:

| Former assertion | Current evidence |
| --- | --- |
| Exact offered and selected capabilities | `tfile_wire`: exact offer and selected value through the SDK |
| Required focus, activation and output assignments | `tfile_wire`: required/optional partition; `twm_file_client`: candidate settings reach the connected endpoint |
| Selection outside offer or ceiling | `tfile_wire` plus SDK `bad_limits_and_negotiation_refuse` |
| Insufficient ceiling or required profile | `tfile_wire`: no candidate submitted |
| Profile, configuration and one settled cycle | `wm_sdk_session_peer` startup/cycle against Sophia's production file export; supplied admission and scripted policy outcomes |
| Submission retry identity and pacing | SDK `retry_is_paced_and_keeps_identity`; definitive refusals continue only on a new caller submission (`refusal_continues_without_consuming_domain`) |
| Events retained during submission custody | SDK `held_event_and_ack_reply_block_next_transaction` and `full_retained_journal_still_observes_submitted` |
| Second held event fails | Retired single-slot implementation rule; the SDK instead bounds a retained journal at 64 records and fails malformed/over-capacity intake |
| Candidate deadline with withheld progress | SDK `deadline_never_sends_and_close_classifies` |
| Snapshot matches the Cycle | SDK `snapshot_is_complete_bound_and_pin_released` and `mismatched_snapshot_refuses` |
| Event epoch and sequence | SDK `event_lengths_and_sequences_fail_immediately` and `invalid_events_stop_custody_scan` |
| Partial-event timeout versus idle | SDK `idle_partial_and_clock_deadlines` |
| Complete held event has no assembly deadline | SDK `complete_held_event_outlives_assembly_deadline` advances the clock twenty seconds with the same retained event |
| Incomplete event remains bounded during other work | SDK `partial_event_deadline_runs_during_pending_ack` withholds an ack reply, supplies more partial bytes and checks closure at the unchanged deadline |
| Whole snapshot read deadline and truncation | SDK `snapshot_retry_is_paced_and_truncation_refuses` plus absolute session deadlines |

A definitive submit refusal now ends Hagia's attempted policy exchange. The SDK
alone retries EAGAIN with the same identity; Hagia does not reinterpret a
refusal as permission to replay. A server `Submitted` is custody, not policy
commit. `tpolicy_wire` and `tpolicy_model` keep candidate settlement assertions.

The SDK peer used by admission tests comes from the pinned SDK's test support.
It is scripted and shares that codec; it is not an independent encoder or a
production Session. `tdesktop_sdk` compares all projection families and a full
snapshot against the independent Nim oracle. `twm_presentation` retains the
capability refusal that found the SDK receipt defect fixed in `00897d8`.

## Retired IPC evidence

The old `hagia-policy-proof` executable and IPC host invocation are removed.
Their socket framing and IPC recovery verdict are not claimed by a file test.
Pure policy/reducer checks remain. The optional pairing overlay still contains
historical IPC cases and needs migration before it can qualify this candidate;
it is not evidence for the new binary merely because an older pair passed.

The supplied-stream SDK peer checks startup and a configuration/snapshot/
projection/session-operation cycle against the real file export. It does not
prove authenticated production launch, native presentation or physical input.
Those remain separate acceptance work before deployment.
