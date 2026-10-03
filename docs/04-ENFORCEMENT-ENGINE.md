> **Implementation status:** this is the broader design specification. The implemented volatile slice, supported routes and explicit deferred guarantees are in [the current contract](07-TEAM-INTEGRATION-CONTRACT.md). Priorities and official-versus-design requirements are in [the recovery matrix](10-REQUIREMENTS-RECOVERY.md). Do not treat every proposed feature below as already implemented.

# Enforcement engine specification

## Required behavior

Every financial mutation, model invocation, tool call, and protected export in the reference workflow passes through Mathguard. The LLM may be malicious or simply wrong. The engine must remain safe for any typed proposal, subject to the explicitly stated deployment assumptions. String filtering is supplemental; the ledger gate acts on canonical actions.

The minimum viable executor is a single host, one currency, one private ledger store, and serialized commits. Use SQLite transactions or an equivalent established atomic store. Multi-replica operation needs a shared authoritative transaction boundary and is outside the first release.

## Components and ownership

1. **Ingress/auth adapter:** validate request size/schema, authenticate on every request, derive principal and session, canonicalize IDs/accounts/amounts. Unknown identities fail closed.
2. **Policy catalog:** validated data-only configuration, immutable snapshots, monotonically increasing activation epoch, trusted account ownership/permissions, model/destination allowlists, budgets, semantic settings, signature feed ref.
3. **Model/tool gateway:** the only code holding downstream credentials; checks both requests and responses.
4. **Deterministic control pipeline:** specific predicates/reason codes; hard gates independent of semantic output.
5. **Semantic guard:** bounded model call with a typed result; advisory explanation plus restrict-only decision.
6. **Lean transition worker:** reviewed pure definitions, built at release time; request and current state in, decision and next state out.
7. **Private atomic executor:** commits the exact approved state transition, journal, idempotency record, consumed approval, and authoritative revision together.
8. **Resource manager:** atomic reservations across all calls, then bounded settlement/cancellation.
9. **Audit/events:** sanitized per-stage events and durable commit-linked records; management view derived from them.

## Threat model

Adversary controls user text, retrieved content, proposed tool arguments, model output, duplicate delivery, request ordering, and attempts to call public routes directly. The reference agent is deliberately not trusted. The adversary does not control the gateway binary, trusted policy-admin credential, authenticated human approval record, private database, host clock, or process isolation. If those assumptions fail, the pure Lean theorems do not establish deployment safety.

Account identity is not a prompt field. Session identifiers are correlation keys, not authentication. Destination metadata and model trust classifications come from the catalog, not the request. Approval is resolved from a protected server record, not an agent boolean. The attack-feed file is data, never executable Python, shell, pickle, or Lean code.

## Policy schema

Prefer strict JSON at first. YAML is acceptable only with a safe data loader. Unknown keys, duplicate keys, wrong types, NaN/infinity, negative limits, malformed destinations, invalid feeds, and incompatible schema/model versions are rejected. A failed reload retains the last good epoch and emits an error.

Example (illustrative catalog; implement and validate its exact schema):

```json
{
  "schema_version": "mathguard-policy-1",
  "epoch": "7",
  "ledger": {
    "currency": "PLN",
    "accounts": ["alice-main", "bob-main", "merchant"],
    "owners": {"alice-main": "alice", "bob-main": "bob", "merchant": "merchant-owner"},
    "transfer_principals": ["alice", "bob"],
    "beneficiaries": {"alice": ["bob-main", "merchant"], "bob": ["alice-main"]},
    "max_transfer_minor": "50000",
    "debit_caps_minor": {"alice-main": "75000", "bob-main": "20000", "merchant": "0"},
    "approval_at_or_above_minor": "10000"
  },
  "models": {
    "allowed": ["local-demo"],
    "destinations": {"local-demo": {"confidentiality_clearance": "confidential", "trust": "internal"}},
    "max_output_tokens": "1024",
    "deadline_ms": "10000"
  },
  "resources": {"cost_micros": "250000", "tokens": "20000", "compute_ms": "60000", "tool_calls": "12", "max_inflight": "1"},
  "semantic": {"enabled": true, "threshold": "0.70", "timeout_action": "block"},
  "exports": {"allowed_destination_ids": ["internal-audit"], "public_clearance": "public"},
  "signatures": {"feed": "demo-signatures", "required": true}
}
```

Caps in the formal ledger model are **cumulative over the demo ledger lifetime**, not daily. Do not implement a midnight reset under this theorem. A daily/rolling limit requires a separate time-window model and reset theorem. Policy reload preserves counters. If a cap drops below existing usage, block further debits; never rewrite history or pretend past usage vanished.

Structural rules (integer accounting, guarded subtraction, paired posting, revision binding, atomicity, replay uniqueness) are fixed by the verified transition release. Operational rules (permissions, beneficiaries, threshold, budgets, semantic sensitivity, signatures) are configurable. Changes to structural semantics require a new reviewed proof artifact.

## API contract v1

| Route | Caller | Behavior |
|---|---|---|
| `POST /v1/agent/run` | User | Budgeted orchestration; bounded proposals through same gateway |
| `POST /v1/actions` | Authenticated client/agent session | Strict action envelope; decision and receipt; no identity override |
| `GET /v1/ledger/summary` | Account owner | Scoped read and labeled response |
| `POST /v1/approvals` | Authenticated owner | Issue approval for exact canonical pending request |
| `POST /v1/policy/validate` | Operator | Validate candidate with no activation |
| `POST /v1/policy/activate` | Operator | Atomic new epoch; preserve counters; invalidate stale pending work |
| `GET /v1/events` | Scoped user/operator | Sanitized SSE or polling |
| `GET /v1/audit/export` | Operator | Sanitized JSONL and summary |
| `POST /v1/tests/run` | Local operator only | Controlled fixture suite; no arbitrary code execution |
| `GET /v1/assurance` | User/operator | Exact proof/build manifest and limits |

Private raw mutation/store access must not be reachable by the reference agent. A standalone MCP wrapper can expose the same named tools after the ordinary action path works; do not call a bespoke JSON-over-HTTP tool shim “full MCP” without actual protocol support.

Action envelope for an exact transfer:

```json
{
  "schema_version": "mathguard-action-1",
  "request_id": "req-00017",
  "session_id": "server-issued-session",
  "expected_revision": "0",
  "policy_epoch": "7",
  "tool": "ledger.transfer",
  "arguments": {"source": "alice-main", "destination": "bob-main", "amount_minor": "2500", "currency": "PLN"},
  "approval_ref": null
}
```

Opaque IDs map injectively into internal typed IDs and are namespaced by the deployment/session registry. Canonical request content includes ID, source, destination, amount, revision, epoch. Store canonical bytes/typed fields for exact equality; hashing alone does not prove equality. Decimal strings avoid JavaScript integer precision loss; parser accepts only the documented canonical nonnegative integer grammar with length/range bounds. Unsupported accounts fail before `Fin n` construction. JSON duplicate keys and extra fields fail.

Example decision fields:

```json
{
  "outcome": "BLOCKED",
  "reason_codes": ["LEDGER_INSUFFICIENT_FUNDS"],
  "request_id": "req-00017",
  "trace_id": "trace-0042",
  "policy_epoch": "7",
  "ledger_revision_before": "0",
  "ledger_revision_after": "0",
  "receipt": null,
  "assurance_ref": "release-manifest-id"
}
```

## Evaluation pipeline

1. Authenticate and strictly parse; enforce ingress rate/size limits.
2. Take trusted session/model/tool metadata and current policy snapshot.
3. Check exact prior committed ID. Same principal and exact request → prior minimal receipt; changed payload/principal → conflict. Failed IDs do not create a permanent transaction receipt; retries are budget/rate limited.
4. Apply hard cheap controls: capability/object authorization, known signatures, data destinations, ledger fields, expected versions. Cheap failures do not need a semantic model call.
5. Reserve resources for any semantic/model operation **before** dispatch. Include semantic guard cost.
6. Run semantic assessment if required; malformed result, error, or timeout is restrictive under the configured policy. A classifier “safe” cannot erase any hard failure.
7. If approval is required, create a pending proposal. This does not reserve financial funds or authorize future execution. Approval must match exact request/principal/revision/epoch and not be expired/used.
8. For commitment, obtain transaction lock/current state and latest epoch, rerun hard predicates and check that semantic assessment/approval is bound to the exact request and active epoch. On staleness reject/re-propose; do not silently retry with new economic fields.
9. Execute the reviewed Lean transition; commit balances, journal, counters, approval consumption, idempotency record, revision, and commit-linked audit atomically.
10. Gate/filter response before delivery, settle resource reservations, publish sanitized outcome.

Semantic findings need exact request/policy binding. A long-running assessment cannot be attached to a different proposal. If the configured guard says “review,” human approval can satisfy the additional semantic requirement, but cannot waive any hard predicate. High-value approvals also satisfy the formal ledger approval predicate. Low-value semantic review receipts are enforced by the outer gateway and are outside the base ledger theorem until explicitly added to its model.

## Decision composition — do not use a fake total order

`ALLOW`, `ASK`, `REDACT`, and `BLOCK` are not interchangeable severity levels. Redaction changes an output; approval adds a prerequisite; blocking denies an effect. Model each proposed effect as permitted by the hard policy and further restricted by semantic policy. **Final executable effects are a subset of hard-permitted effects.**

- Deterministic deny → deny, regardless of semantic result.
- Deterministic permit + semantic deny → deny.
- Deterministic permit + semantic review → pending until trusted review; revalidate hard gates at commit.
- Redact an output → create a new labeled output, validate it again, and then gate it. Never redact an amount/beneficiary and execute a different transfer.

Core theorem is set intersection/no-override. It proves enforcement of restrictions, not that a classifier detects every attack.

## Atomic ledger implementation

For the first release use a single serializable commit transaction. Two transfers both reading revision `k` cannot both commit as `k+1`. A unique committed request ID and journal entry are inserted within the same transaction as balance/counter writes. Compare the expected revision with the authoritative revision after acquiring the lock.

Crash before commit → no money movement. Crash after commit/before response → exact retry returns existing receipt. If audit availability is essential, persist a commit-linked outbox in the same transaction; UI delivery can be retried independently. Do not mutate balances and append a journal later. Do not consume approval before a commit that may fail. Demo reset is an operator-only new ledger instance, with a new namespace and genesis, not a transaction that rewrites the current verified journal.

The Lean model treats each commit as atomic. Concurrency tests support the database adapter contract; they are not a formal database or scheduler proof. A malicious host or alternate writer is outside that contract.

## Resource governance

Track a vector: `cost_micros`, `tokens`, `compute_ms`, `tool_calls`. Use per-session limits and a deployment-level limiter so new sessions cannot trivially bypass total resource caps. The theorem applies independently to each accounting bucket; runtime must reserve all required buckets atomically or roll back all reservations before dispatch.

For each call calculate a conservative upper bound, including input tokens, maximum output, price schedule, and local deadline. Reserve under a unique ticket before dispatch. Require, componentwise, `spent + reserved + requested <= limit`. Bound concurrent tickets; semantic checks cannot recursively call themselves. Reject zero-resource dispatch and request tickets with no tool slot.

On a valid completion, actual usage must be componentwise at most the reservation. Remove ticket and add actual to spent atomically. On failure/cancellation, actual usage still counts; if unknown, charge the full reservation. Never release reservation just because a network request timed out while the remote provider may still execute. Keep it in flight until quiescence/reconciliation or settle pessimistically; fail closed for further use.

Provider usage greater than reservation → anomaly, quarantine session/provider and retain or charge the bound. The theorem covers accounted usage; it cannot retroactively prevent an external provider from overbilling or ignoring a token cap. Describe hard API-spend claims conditionally on provider upper-bound enforcement. Local worker deadlines need actual process termination or trusted provider cancellation; merely stopping the waiting coroutine does not stop GPU compute.

Lowering budget limits below `spent + reserved` cannot preserve the configured invariant. Reject that activation or place the bucket in an explicit exhausted/quarantined mode; the formal `budgetReconfigure` function rejects it. Do not reset counters during reload.

## Confidentiality and provenance

Keep confidentiality (`public < confidential < secret`) independent from trust (`trusted < external_untrusted`, where higher means more tainted). Each tool result receives trusted labels from its registry. The context label is the join of previous context, new result, and user input labels. Labels only rise during the demo session; a fresh independent session is needed to start clean. Persist labels with any memory; omit memory entirely in MVP if necessary.

Generated agent/model output inherits the whole context label. Before a remote model sees account data, gate that model as an outbound sink with its configured clearance. Gate export, logging, UI roles, and tool arguments as well. Authorization to read a secret does not imply authorization to send it to an arbitrary destination. No free-text instruction may lower a label.

Generic regex redaction is not a formal declassification proof. Keep the original label after regex masking. For a useful lower-classification view, define a narrow structured projection (e.g. fixed approved aggregate fields) with separate reviewed policy; do not promise information-theoretic noninterference. The supplied theorem establishes label-gate safety for modeled explicit outputs; timing, control-flow, request sizes, and statistical leakage remain outside scope.

## Historical feeds and security reporting

Feed entries: unique ID, version, source URL, description, exact/regex match type, bounded expression, affected action/content location, and restrictive response. Pin provenance; use safe bounded matching to avoid regex denial of service. Include examples inspired by documented instruction injection and dangerous loader/deserialization configurations; classify these as representative detections, not verified coverage of all CVEs. Feed cannot install/run a plugin or deserialize object code. Unknown or invalid feed never silently disables a required guard.

Events record policy/feed version, canonical action summary, reason codes, relevant label/capability, reservation/settlement, stage timings, and proof-artifact ref. Store sensitive raw content separately only if explicitly needed and access controlled; prefer hashes/redacted snippets. Hash-chain logs may demonstrate accidental tampering, but are not cryptographic authenticity proofs without protected anchoring and key management.

## Failure behavior and limits

Worker crash, invalid output, invalid schema, stale snapshot, database conflict, missing required classifier/feed, provider inconsistency, and failed audit transaction → no financial mutation. Read-only availability may degrade independently. Bound queue length and avoid storing attacker-controlled payloads without size limits.

A liveness guarantee is not claimed: valid actions may be delayed, require reapproval, or fail closed. Security classifiers can have false positives/negatives. The safety theorem applies to modeled operations under trusted labels, identity, policy, and atomic state transitions. Unknown operations are denied rather than passed through as arbitrary API calls.

## Definition of done

One authenticated positive and one negative action work through the same public path; a real model adapter and semantic guard are mediated; policies/signatures reload safely; budgets reserve and settle; approval/replay/races are correct; all reference effects are mediated; a startup script, schema, suite, and measured report exist. Exact checked theorem/build status appears in the manifest. No fixture or test result is described as a proof of the whole deployed service.
