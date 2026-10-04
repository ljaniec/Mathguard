# Mathguard runnable integration contract

Updated 4 October 2026 for the release merged in PR #6. This describes the implemented single-owner gateway and optional durable command journal. The broader design in `03`/`04` remains a backlog where it exceeds this contract. Coordinate through PRs; do not independently replace the schema, owner mappings, or Lean functions. Current evidence and remaining acceptance are in [STATUS.md](../STATUS.md) and [RELEASE-ASSURANCE.md](verification/RELEASE-ASSURANCE.md).

## Start and credentials

Use `make setup MODEL=qwen2.5:1.5b-instruct`, then `make run`, after installing/starting the local model as described in [the quickstart](17-JUDGE-QUICKSTART.md). Setup builds `mathguard-worker`, checks real Ollama weight metadata and the shared strict-schema readiness request, and prepares private configuration/state. The gateway serves `http://127.0.0.1:8787`. Python 3.10+, GNU Make and the pinned Lean environment are required; Node.js is needed for the dashboard test harness. Model URLs must be numeric loopback (or canonicalized localhost), with redirects and ambient proxies disabled. Model IDs are exact allowlisted local names, not caller-controlled URLs or cloud aliases.

Setup retains distinct agent, owner and operator tokens in owner-private files; the server does not print them at startup. `make credentials` explicitly displays them in a private terminal for entry into separate dashboard fields. Never commit/export/record them or pass the owner token to the reference agent. The dashboard retains them only in the current tab's DOM/request memory, not browser storage. Authentication uses `Authorization: Bearer <token>`; identity is server-derived. Runtime directories use mode 700 and files mode 600 with ownership and symlink checks. Shared-host process isolation and secured remote ingress are separate deployment work.

## Implemented routes

| Method/path | Authority | Behavior |
|---|---|---|
| GET `/`, `/app.js`, `/style.css`, `/logo.png`, `/health` | Public | Allowlisted dashboard assets and non-sensitive liveness |
| POST `/v1/sessions` | Agent/owner | Empty object; bounded principal-bound session |
| POST `/v1/models/chat` | Agent/owner | `session_id`, allowlisted `model`, `prompt`, `source` (`user`, `tool`, `document`) |
| POST `/v1/interactions` | Agent/owner | Generic prompt, tool call/result, agent message and model output interception |
| POST `/v1/interactions/approve` | Owner | Bound, single-use generic irreversible-tool approval |
| POST `/v1/actions` | Agent/owner | Exact transfer envelope below; returns authoritative receipt |
| POST `/v1/approvals` | Owner | Same envelope with null approval; issues approval only, never executes |
| GET `/v1/ledger/summary` | Agent/owner | Own account balance, revision and epoch |
| POST `/v1/policy/validate` | Operator | Full candidate policy object, validation without activation |
| POST `/v1/policy/reload` | Operator | Empty object; reload configured local files |
| POST `/v1/provider/recover` | Operator | Current `quarantine_id` plus `upstream_stopped: true`; preserves state and charges |
| POST `/v1/artifacts/check` | Operator | Bounded byte/hash/header admission; example `contracts/artifact-fixture.json` |
| GET `/v1/status`, `/v1/events`, `/v1/report` | Operator | Current state, audit window, management summary |
| GET `/v1/audit/export` | Operator | Sanitized JSONL, latest 2,000 events |
| GET `/v1/assurance` | Authenticated | Proof/runtime scope, binary hash, model mode and live-call count |

The current routes are custom middleware APIs. They are not a complete OpenAI chat proxy or an MCP protocol server. The reference client calls only the gateway. `gateway/sdk.py` wraps MCP client/tool callbacks and gates results using the shared interaction route. It is an SDK wrapper, not an MCP transport server or OAuth implementation. Ledger execution stays on the action route. See [the generic contract](13-GENERAL-CONTROL-LAYER.md). `/v1/agent/run` and SSE from the older proposed design are not implemented; use `python3 agent/run.py` and dashboard refresh/polling.

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

Financial outcomes: `COMMITTED`, `REPLAYED`, `PENDING_APPROVAL`, `BLOCKED`, `ERROR_CLOSED`. Model requests use `ALLOWED` plus separate input/output redaction dispositions. A pending approval requires the non-approval ledger predicates, financial call-slot capacity, flow and semantic gates to pass. A semantic review verdict returns `PENDING_APPROVAL`; the owner cannot override classifier review/denial. Fix the cause and re-evaluate it. Generic tool approval grants only the exact irreversible action, not a semantic exemption. Supplied invalid approval stays blocked. Approved replay has no new effect even after the approval expires. Exact retries do not re-dispatch a model or charge a second financial call slot. Replays return the original masked receipt; current revisions are separate response fields.

## Configuration and accounting

Policies are strict JSON. Unknown fields or unsupported controls fail validation. Schema `mathguard-policy-3` adds tool allowlists, irreversible tools, PII redact/block thresholds and semantic review/block thresholds. `profile` now controls the compiled semantic fallback: strict denies, balanced asks, permissive passes with an alert. `pii_action: block` clamps the effective block threshold to the redact threshold. `semantic_threshold` is the block threshold; lowering it also clamps review to preserve validity. All profiles are actual configurations. Copying either onto `demo.json` works once at epoch 8; later activations need a higher epoch. Invalid reload preserves the last good policy/feed and raises a visible error. Missing valid startup configuration closes execution.

Reload occurs at an authenticated request boundary, with explicit operator reload available; there is no background watcher. Config snapshots stay fixed during a request. Budget reductions below spent+reserved fail. Feed changes require a higher version; an empty optional signature list is valid. Hard ledger checks cannot be disabled by removing text signatures. Retained history is rechecked and sanitized under the current policy before new provider dispatch.

Resource order: `[cost_micros,tokens,compute_ms,calls]`. In the normal SQLite-backed launch, every semantic/proposer dispatch durably reserves a trusted configured bound using Lean before provider dispatch, then charges the full bound on completion/error. Direct volatile launches reserve without durable storage. This conservative mode does not refund unused capacity; displayed totals are **accounted bounds**, separately from observed provider tokens and elapsed adapter time. Cost=0 for local calls still consumes tokens, time and slots. Reported over-bound usage, timeout or provider failure quarantines further calls. Killing the adapter does not establish upstream GPU cancellation. After verifying the upstream job stopped, the operator can recover the current quarantine without resetting ledger/charges. Recovered pending reservations are charged once, never refunded for uncertainty.

Allowed chat runs input classification, generation and output classification. The sample shares a 128-token output cap and a 15-second deadline per stage. Three completed stages charge `[0,49152,48000,3]`; the fresh sample budget permits 12 complete chats before other usage. See [the budget calculation](../policies/README.md#budget-example). Later-stage exhaustion withholds output while preserving prior charges.

The only vector quota is global. Session steps/repeats add isolation limits but are not session vector quotas. The gateway serializes operations; ingress is limited to eight simultaneous server handlers and bounded request/response sizes. Do not launch multiple workers behind a load balancer with independent budget copies.

## State, audit and proof boundary

The private Lean worker owns financial/resource state. Its `execute` operation computes the reviewed ledger transition and financial call reservation/charge before returning the combined next state. The normal launcher configures an owner-private SQLite journal: write durable intent before a mutating worker command; retain completion, exact result and operation audit in one transaction; replay completed private commands through the same worker and compare results on recovery. An unresolved intent, corruption, wrong worker/schema, response mismatch, unsafe ownership or competing owner closes recovery rather than resetting to genesis. This is a runtime-tested transaction contract, not a proved SQLite implementation.

Same-directory restart restores acknowledged ledger state, charges, receipts, consumed nonces, last-good policy/feed and audit. Sessions/history and outstanding host approvals are invalidated. A successful dashboard refresh detects the changed instance, clears stale session/approval/retry state and requires explicit reconnect without resubmitting actions. `make run` is enough; setup need not be repeated. Direct server launches without a state path remain explicitly labeled volatile. A worker failure closes execution; no automatic worker restart or Python money-moving fallback exists.

The proof catalog contains 55 baseline + 5 refinement + 43 Next + 53 Control axiom records. The generic request path executes `hardDecision`/`storeDecision`, and typed ledger decoding executes W1 `fromWire`. C1/P1 state-machine proofs remain model evidence; they are not a claim about durable runtime storage. The abstract G1 step/audit/memory proofs do not identify Python sessions or the bounded audit window with those models. The new worker is compiled and integration-tested; its JSON parser, composed operation, IO loop, authentication, provider behavior and label assignment are not new proofs. Regex redaction does not lower labels. Automatic labels detect only supported patterns; arbitrary natural-language secrets are not covered by a complete information-flow theorem. Artifact admission verifies bounded uploaded bytes against an allowlisted digest and header; it does not load weights, scan arbitrary model repositories, or certify model behavior.

Public audit/export stores sanitized metadata/reasons/timing and conservative charges, never raw prompts, model outputs, credentials, approval references or full transfer arguments. The private command journal contains the exact worker commands/results needed for replay and is not a public export. The dashboard shows the latest 30 events; each export is bounded to 2,000 events and the audit API supports pagination. Durable retention and volatile windows are distinct. Store capacity/integrity failures close execution. A trusted host administrator can rewrite or roll back a valid journal; a hash chain alone is not a malicious-admin rollback anchor. No UI/model response may invent a commit; use the actual worker receipt.

## Checks and evidence

- `bash scripts/check-local.sh`: static/proof/native/gateway integration checks. Classifier fixtures are explicitly marked and do not prove detection accuracy.
- `python3 scripts/evaluate-live.py ...`: separately records real local-model outcomes and latency. A local HTTP protocol fixture validates transport only.
- `docs/10-REQUIREMENTS-RECOVERY.md`: source-grounded coverage; [release assurance](verification/RELEASE-ASSURANCE.md) maps current proof/runtime assumptions.
- `STATUS.md`: actual checkpoint; update after meaningful changes.
