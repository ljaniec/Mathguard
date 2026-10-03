# Mathguard runnable integration contract — challenge recovery

This describes the implemented single-process slice. The broader design in `03`/`04` remains a backlog where it exceeds this contract. Coordinate through PRs; do not independently replace the schema, owner mappings, or Lean functions.

## Start and credentials

`bash scripts/demo.sh` builds `mathguard-worker` and serves `http://127.0.0.1:8787`. Python 3.10+ and the pinned Lean environment are required. Configure `MATHGUARD_MODEL_URL` to an OpenAI-compatible endpoint, e.g. a local `/v1` URL. Edit **both** `allowed_models` and `semantic_model` to the exact installed model ID. Set no public provider URL supplied by an HTTP caller.

The launcher prints separate random `OPERATOR`, `OWNER`, and `AGENT` tokens to the local console. Optional `MATHGUARD_<ROLE>_TOKEN` environment variables must be distinct and at least 24 characters. Never commit them, store them in the browser, put them in audit exports, or pass the owner token to the reference agent. Authentication uses `Authorization: Bearer <token>`. Identity is server-derived. The local service binds only to loopback; shared-host process isolation and a secured remote ingress are separate deployment work.

## Implemented routes

| Method/path | Authority | Behavior |
|---|---|---|
| GET `/`, `/app.js`, `/style.css`, `/health` | Public | Static dashboard and non-sensitive liveness |
| POST `/v1/sessions` | Agent/owner | Empty object; bounded principal-bound session |
| POST `/v1/models/chat` | Agent/owner | `session_id`, allowlisted `model`, `prompt`, `source` (`user`, `tool`, `document`) |
| POST `/v1/actions` | Agent/owner | Exact transfer envelope below; returns authoritative receipt |
| POST `/v1/approvals` | Owner | Same envelope with null approval; issues approval only, never executes |
| GET `/v1/ledger/summary` | Agent/owner | Own account balance, revision and epoch |
| POST `/v1/policy/validate` | Operator | Full candidate policy object, validation without activation |
| POST `/v1/policy/reload` | Operator | Empty object; reload configured local files |
| POST `/v1/artifacts/check` | Operator | Bounded byte/hash/header admission; example `contracts/artifact-fixture.json` |
| GET `/v1/status`, `/v1/events`, `/v1/report` | Operator | Current state, audit window, management summary |
| GET `/v1/audit/export` | Operator | Sanitized JSONL, latest 2,000 events |
| GET `/v1/assurance` | Authenticated | Proof/runtime scope, binary hash, model mode and live-call count |

The current routes are custom middleware APIs. They are not a complete OpenAI chat proxy or an MCP protocol server. The reference client calls only the gateway. A full MCP adapter is an extension using the same action route, not a new privileged executor. `/v1/agent/run` and SSE from the older proposed design are not implemented; use `python3 agent/run.py` and dashboard refresh/polling.

## Transfer envelope

```json
{
  "schema_version": "mathguard-action-1",
  "request_id": "req-00017",
  "session_id": "replace-with-server-session",
  "expected_revision": "0",
  "policy_epoch": "7",
  "tool": "ledger.transfer",
  "arguments": {
    "source": "alice-main",
    "destination": "bob-main",
    "amount_minor": "2500",
    "currency": "PLN"
  },
  "approval_ref": null
}
```

Reject duplicate/unknown JSON keys, NaN, noncanonical decimal strings, unsupported currency/accounts/tools and overlarge bodies. IDs are bounded ASCII strings; the worker ID is an injective length-tagged byte encoding, not a digest used as equality. Amounts/revisions/epochs are bounded canonical decimal strings. Account mapping is Alice=0, Bob=1, Merchant=2; principals are 1,2,3. The fixed reference ownership/beneficiary/debit-cap configuration agrees with `demoPolicy`. Default genesis is `[100000,20000,0]`, epoch 7. Policy files can change epoch, maximum transfer and approval threshold; ownership/beneficiary/debit caps remain fixed for this slice.

Financial outcomes: `COMMITTED`, `REPLAYED`, `PENDING_APPROVAL`, `BLOCKED`, `ERROR_CLOSED`. Model requests use `ALLOWED` plus separate input/output redaction dispositions. A pending approval requires the non-approval ledger predicates, financial call-slot capacity, flow and semantic gates to pass. A semantic review verdict is blocked in this slice; it is not converted into a human override. Supplied invalid approval stays blocked. Approved replay has no new effect even after the approval expires. Exact retries do not re-dispatch a model or charge a second financial call slot. Replays return the original masked receipt; current revisions are separate response fields.

## Configuration and accounting

Policies are strict JSON. Unknown fields or unsupported controls fail validation. `profile` is a human-readable label; the actual behavior is set by `pii_action` and `semantic_threshold`. `strict.json` and `permissive.json` are concrete examples, not magic mode toggles. Copying either onto `demo.json` works once at epoch 8; later activations need a higher epoch. Invalid reload preserves the last good policy/feed and raises a visible error. Missing valid startup configuration closes execution.

Reload occurs on the next authenticated POST, with explicit operator reload available; there is no background watcher. Config snapshots stay fixed during a request. Budget reductions below spent+reserved fail. Feed changes require a higher version; an empty optional signature list is valid. Hard ledger checks cannot be disabled by removing text signatures.

Resource order: `[cost_micros,tokens,compute_ms,tool_calls]`. Every semantic/proposer dispatch reserves a trusted configured bound using Lean and charges the full bound on completion/error. This conservative mode does not refund unused capacity; displayed totals are **accounted bounds**, not measured cloud bills. Cost=0 for local calls still consumes tokens, time and slots. Bounds must be calibrated to the actual provider/model and price. Reported tokens above a bound, timeout, or provider failure quarantines further model calls. Killing the adapter does not establish remote GPU cancellation. Operator must investigate upstream work before restarting; restart resets this explicitly volatile demo.

The only vector quota is global. Session steps/repeats add isolation limits but are not session vector quotas. The gateway serializes operations; ingress is limited to eight simultaneous server handlers and bounded request/response sizes. Do not launch multiple workers behind a load balancer with independent budget copies.

## State, audit and proof boundary

The private Lean worker owns financial/resource state. Its `execute` operation computes the reviewed ledger transition and financial call reservation/charge before returning the combined next state. The gateway owns sessions/approval receipts and the sanitized audit window. All are volatile. A worker failure closes execution; no automatic restart or Python money-moving fallback exists. Host/Python failure between worker commit and receipt storage is a deployment failure, not proved crash recovery.

Current proof evidence is the 55 baseline targets and five previously checked equality targets. The new worker is compiled and integration-tested; its JSON parser, composed operation, IO loop, authentication, provider behavior and label assignment are not new proofs. Regex redaction does not lower labels. Automatic labels detect only supported patterns; arbitrary natural-language secrets are not covered by a complete information-flow theorem. Artifact admission verifies bounded uploaded bytes against an allowlisted digest and header; it does not load weights, scan arbitrary model repositories, or certify model behavior.

Audit stores metadata/reasons/timing and conservative charges, never prompts, outputs, credentials, approvals, or full transfer arguments. It retains 2,000 events; management export reports dropped-event count. This is not durable forensic retention. No UI animation or model response may invent a commit; use the receipt from the actual worker result.

## Checks and evidence

- `bash scripts/check-local.sh`: static/proof/native/gateway integration checks. Classifier fixtures are explicitly marked and do not prove detection accuracy.
- `python3 scripts/evaluate-live.py ...`: separately records real local-model outcomes and latency. A local HTTP protocol fixture validates transport only.
- `docs/10-REQUIREMENTS-RECOVERY.md`: source-grounded coverage and current open acceptance items.
- `STATUS.md`: actual checkpoint; update after meaningful changes.
