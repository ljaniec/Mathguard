# Enforcement engine — current runnable specification

The engine is a local, serialized, volatile AI control layer executing the actual compiled Lean ledger/budget/flow functions. Its public contract is [07-TEAM-INTEGRATION-CONTRACT.md](07-TEAM-INTEGRATION-CONTRACT.md); team tasks are in [09-ENFORCEMENT-HANDOFF.md](09-ENFORCEMENT-HANDOFF.md). The [original extended proposal](design/ENFORCEMENT-EXTENDED-PROPOSAL.md) is retained as history/backlog, not as a second supported API.

## Current policy schema

The accepted schema is **`mathguard-policy-2`**, implemented in `gateway/control.py`. The older `mathguard-policy-1` nested catalog is unsupported. Policy JSON uses bounded integers for configuration values; the public financial envelope separately uses canonical decimal strings. Unknown keys, duplicate keys, wrong types and unsafe budget reductions fail validation. Reload retains the last good configuration.

This is the exact shipped example; replace both model ID fields with the actually installed model before live use. The artifact hash is for the inert fixture, not for that installed model's weights.

```json
{
  "schema_version": "mathguard-policy-2",
  "epoch": 7,
  "profile": "balanced",
  "pii_action": "redact",
  "semantic_threshold": 60,
  "allowed_models": [
    "local-model"
  ],
  "semantic_model": "local-model",
  "budget_limit": [
    1000000,
    1000000,
    600000,
    200
  ],
  "call_bound": [
    0,
    16384,
    16000,
    1
  ],
  "deadline_seconds": 15,
  "max_output_tokens": 512,
  "max_input_bytes": 4096,
  "max_session_steps": 20,
  "repeat_limit": 3,
  "max_transfer": 50000,
  "approval_threshold": 10000,
  "model_clearance": 2,
  "artifact_repositories": [
    "mathguard/demo-safe"
  ],
  "artifact_sha256": [
    "a9311856600eeba2a2c803baf41eec2eb10d885fefe9f2dffbe5c0a77a317e28"
  ]
}
```

`profile` is a display label. Actual strictness comes from `pii_action` and `semantic_threshold`; example strict/permissive files supply explicit values. New activation requires a higher epoch and preserves all counters. The account map, ownership, beneficiaries and cumulative debit caps are fixed in this runtime's three-account fixture. The mathematical theorems are parameterized; that runtime choice is not a limitation of Lean to three accounts.

## Current ingress routes

| Method/path | Authority | Behavior |
|---|---|---|
| POST `/v1/sessions` | Agent/owner | Create principal-bound bounded session |
| POST `/v1/models/chat` | Agent/owner | Guarded model request and output filtering |
| POST `/v1/actions` | Agent/owner | Canonical ledger transfer through Lean |
| POST `/v1/approvals` | Owner | Issue exact bound approval, no execution |
| GET `/v1/ledger/summary` | Agent/owner | Own balance, epoch/revision |
| POST `/v1/policy/validate` | Operator | Validate only |
| POST `/v1/policy/reload` | Operator | Reload configured local policy/feed files |
| POST `/v1/provider/recover` | Operator | Confirm current quarantine's upstream job stopped; preserve ledger/charges |
| POST `/v1/artifacts/check` | Operator | Bounded byte/hash/header admission |
| GET `/v1/status`, `/v1/events`, `/v1/report` | Operator | State, audit window and management summary |
| GET `/v1/audit/export` | Operator | Sanitized JSONL |
| GET `/v1/assurance` | Authenticated | Exact proof/runtime evidence boundary |

`/v1/policy/activate`, `/v1/agent/run`, and `/v1/tests/run` are not implemented. Use policy reload, the `agent/run.py` client, and `scripts/test-integration.sh` respectively. Events are fetched as bounded JSON; no SSE endpoint is implemented. This custom middleware interface is not a complete MCP transport or drop-in OpenAI proxy.

## Enforcement sequence and acceptance

1. Bound HTTP/JSON size, reject ambiguous/unknown fields, authenticate and derive role/principal.
2. Activate validated higher-version configuration at a request boundary, retaining old valid controls on invalid edits.
3. Resolve a principal-bound session; enforce step/repeat limits; scan input and accumulated context; retain detected confidentiality through redaction.
4. Apply cheap deterministic action checks before invoking the classifier. For each model/guard call, check model/sink/input envelope and reserve the configured resource ceiling using Lean.
5. Obtain a bounded structured semantic verdict. Deny/review/unavailability cannot authorize an invalid hard action. Charge the full call ceiling; timeout/inconsistent usage quarantines further dispatch.
6. Recheck trusted time after semantic work, then use the worker's pure joint financial admission plus tool-slot reservation/charge. Publish a next state only on success. Earlier model charges remain on financial denial.
7. Return the authoritative masked receipt; emit sanitized metadata/stage timings. Exact replay has no second debit or model/tool charge. Expired approval on a committed exact retry does not create a new effect.

Approvals are full-request-bound protected records. Only the owner role can issue one. Owners may also submit actions; role separation means the agent cannot self-approve, not that owner/agent capabilities are mutually exclusive. Current semantic review verdicts block; there is no human override of the classifier.

## Provider recovery

On timeout/failure/usage anomaly, retain charges and quarantine. Stop or verify completion of the upstream model job, investigate the cause, then use the operator-only recovery route with the current `quarantine_id` and `upstream_stopped: true`. This is an explicit trusted operator attestation, not a machine proof of cancellation. It does not change the ledger, revisions, approvals, resource limits, or spent amounts. Agent credentials, missing confirmation and stale quarantine IDs cannot recover calls. No timed automatic recovery exists.

If a judge exhausts the global budget, an operator can explicitly raise limits under a higher policy epoch. This preserves spent/reserved counters and invalidates stale fresh proposals; it is not a reset/refund. A stopped worker still requires a new explicitly labeled volatile instance. Restart seeds `[100000,20000,0]`, rather than restoring prior balances or initializing zero funds. Instance identity/start time are visible in the dashboard.

## Scope and follow-up

`Mathguard/Spec.lean` and baseline theorem statements are unchanged. The worker adapter, JSON parsing, authority construction, label assignment, policy mapping, IO and provider behavior are tested deployment code. No durable store/outbox, multi-replica budget, per-session resource vector, complete secret detector, whole-stack theorem, or actual provider weight verification is claimed. The checked-in classifier suite is a fixture suite; run the separate live evaluator before presenting accuracy figures.

Use the requirement matrix for priority. Complete live validation and submission evidence before implementing the broader archived SQLite/catalog/MCP design. Never introduce an alternative privileged money-moving path in a frontend or model adapter.
