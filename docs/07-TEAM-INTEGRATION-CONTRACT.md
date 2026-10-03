# Team-agent integration contract — Mathguard v1

This document freezes the first integration surface for the **agent/product/visualization agent** and **enforcement-engine agent**. The coding agents may belong to different team members; both contribute to `ljaniec/Mathguard` via PRs. Łukasz coordinates the formal definitions and integration. Use the foundation branch until its PR merges; do not start from an unbuildable old standalone pack.

## Ownership and change protocol

| Owner | Files / responsibility |
|---|---|
| Formal coordinator | `Mathguard/*.lean`, `Mathguard.lean`, Lake/toolchain pins, proof manifest, `aristotle/` |
| Enforcement agent | `gateway/`, `worker/` adapter if approved, `policies/`, `feeds/`, engine tests, startup integration |
| Agent/product agent | `agent/`, `dashboard/`, UI fixtures, demo choreography, frontend tests |
| Shared contract | `contracts/`, this document; changes agreed in a dedicated small PR before consumers change |

Do not modify another owner's files to bypass an integration problem. Open a narrow contract/model proposal when needed. All branches use PRs; preserve existing logo and user text. Do not merge or force-push another agent's branch. Prelint may identify drift, but it does not verify theorem meaning or replace local tests.

## Public routes and responsibilities

| Route | Owner | Minimum result |
|---|---|---|
| `POST /v1/agent/run` | Product orchestrator calling engine | Bounded live/scripted proposer through gateway; trace ID |
| `POST /v1/actions` | Engine | Canonical action decision; real receipt only after commit |
| `GET /v1/ledger/summary` | Engine | Authorized masked snapshot, revision, policy epoch |
| `POST /v1/approvals` | Engine | Owner-issued receipt for exact pending canonical action |
| `POST /v1/policy/validate` | Engine | Validation errors; no activation |
| `POST /v1/policy/activate` | Engine | New active epoch, unchanged financial counters |
| `GET /v1/events` | Engine | Sanitized SSE or polling records |
| `GET /v1/audit/export` | Engine | Operator-only JSONL |
| `GET /v1/assurance` | Formal manifest served by engine | Exact baseline/new target counts and runtime limits |

Demo persona credentials are server issued; a persona dropdown cannot set authoritative identity by adding an `actor` field. A local fixture mode can authenticate against explicit separate demo tokens. The financial agent cannot call approval creation with the owner's credential. If `/v1/agent/run` is hosted by the product service, that service still calls model/action routes through the same enforcement path.

## Canonical transfer envelope

```json
{
  "schema_version": "mathguard-action-1",
  "request_id": "req-00017",
  "session_id": "server-issued-session",
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

Strict schema: no unknown keys or duplicate JSON keys; string nonnegative integers in canonical decimal form (`0` or a nonzero digit followed by digits), bounded length/range; no float/exponent/negative conversion. Canonical account map: `alice-main ↔ Fin 3 index 0`, `bob-main ↔ 1`, `merchant ↔ 2`. Demo principal map: authenticated Alice ↔ `1`, Bob ↔ `2`, Merchant owner ↔ `3`. The policy contains permissions; the wire envelope never supplies principal/owner/approval contents. IDs map injectively into the internal namespace; exact payload bytes/typed fields are retained for idempotency, not only a hash.

Genesis `(100000,20000,0)`, PLN minor units, epoch `7`, revision `0`. Engine fixture/catalog and formal `demoPolicy` must agree on any behavior claimed as the **same** demo. `demoPolicy` currently allows Alice to send to Bob/Merchant and enables principal 2 but disallows all of Bob's beneficiaries. A catalog permitting Bob → Alice is a different policy, not a faithful serialization of `demoPolicy`. Test it separately and label the active policy correctly.

## Decision vocabulary

Public `outcome` is exactly one of:

`COMMITTED`, `REPLAYED`, `PENDING_APPROVAL`, `BLOCKED`, `ERROR_CLOSED`.

`REDACTED_OUTPUT` is an **output disposition**, not a financial outcome. Include it separately as `output_disposition` when applicable. Do not run redaction on an amount/beneficiary and then execute a changed payment. `PENDING_APPROVAL` belongs to the outer gateway; the core ledger with missing required approval returns `blocked`. Likewise specific reason codes come from reviewed gateway predicates/explanations; model-v1's core has only the three `LedgerOutcome` constructors.

Return `PENDING_APPROVAL` only for a fresh canonical proposal whose authentication, schema, identity, capability, beneficiary, amount, account, cap, funds, epoch/revision, flow, signature, and other non-approval gates pass at the authoritative snapshot. Check resource capacity without allocating a financial-tool ticket for the pending proposal. The only unresolved prerequisites must be an absent high-value approval (`amount >= approvalThreshold`) or an explicit catalog-authorized semantic review. Report the applicable `approval_requirements` as `high_value` and/or `semantic_review`, with `APPROVAL_REQUIRED` and/or `SEMANTIC_REVIEW`. An explicit semantic denial or unavailable guard remains closed; it cannot become an approval prompt.

An invalid, expired, consumed, or substituted supplied approval is `BLOCKED` with its specific reason, not silently replaced by a pending prompt. An existing request ID first takes the exact replay/conflict path; it never becomes a new pending payment. Pending has no financial effect, no consumed approval, and no financial-tool reservation; separately incurred model/guard costs and observed label joins remain accounted. Approval issuance does not execute the proposal. Resubmission rechecks every gate at the current snapshot and uses the exact original action; stale work requires a new proposal. Test the positive pending case and each isolated non-approval failure, plus invalid-approval, replay, conflict, and stale resubmission cases.

Minimum response fields: `outcome`, `reason_codes[]`, `request_id`, `trace_id`, `policy_epoch`, `ledger_revision_before`, `ledger_revision_after`, `receipt` (nullable), `output_disposition`, `assurance_ref`. A receipt contains commit ID, canonical transfer, committed revision, prior/replay status, and only authorized balance fields. Client UI must not generate a commit receipt.

Stable initial reason codes: `AUTH_REQUIRED`, `SCHEMA_INVALID`, `TOOL_NOT_ALLOWED`, `OWNER_MISMATCH`, `CAPABILITY_DENIED`, `BENEFICIARY_DENIED`, `AMOUNT_INVALID`, `SAME_ACCOUNT`, `TRANSFER_CAP`, `INSUFFICIENT_FUNDS`, `DEBIT_CAP`, `APPROVAL_REQUIRED`, `APPROVAL_INVALID`, `APPROVAL_EXPIRED`, `APPROVAL_USED`, `STALE_REVISION`, `STALE_POLICY`, `IDEMPOTENCY_CONFLICT`, `FLOW_DENIED`, `SIGNATURE_MATCH`, `SEMANTIC_DENIED`, `SEMANTIC_REVIEW`, `SEMANTIC_UNAVAILABLE`, `BUDGET_EXHAUSTED`, `WORKER_UNAVAILABLE`, `STORE_CONFLICT`. Store/public reason mapping must not itself leak sensitive account facts to unauthorized callers.

## Events, budgets, and assurance

Events: ordered sequence per trace, event ID, trace ID, stage, sanitized action summary, financial outcome, reason codes, epoch/revision, resource delta, latency, assurance ref, mode `live` or `fixture`. Deliver via SSE or bounded polling; consumers deduplicate IDs and tolerate reconnects. A commit event follows authoritative commit, not a frontend timer.

Budget order is fixed: `[cost_micros, tokens, compute_ms, tool_calls]`. Surface limit, spent, reserved, inflight, and provider identity. Cost price zero does not mean unlimited local compute. Both financial tool and guard/model calls are charged in their appropriate accounting buckets. Global and session buckets are distinct but admission is all-or-none.

Assurance minimum: model version, source SHA, toolchain, Mathlib commit, target counts by kernel, evidence origin, current local build status, runtime strategy, unresolved integration assumptions. Baseline: 55 targets reported checked by supplied run; integration statically audited; no independent local Lean rebuild here. The 35 next targets are `REQUESTED`, not added to the verified count until checked.

The formal coordinator updates a package's proof count only after reviewing its production source, exact statement comparison, pinned independent build, and complete fresh axiom report. Extend the provenance checker for the new namespace/targets; a baseline-only pass does not audit new proofs. The enforcement agent supplies the separate runtime evidence: the execution path calls the reviewed function or documents a coordinator-reviewed refinement argument, with the integration tests below. Proof completion and runtime integration have separate evidence fields; proving C1 does not by itself upgrade the deployed transaction claim.

## Joint transition acceptance tests

The enforcement agent must include these executable tests in the integration suite before marking joint financial admission complete. Use deterministic barriers and failure hooks at real adapter/store boundaries; assert the entire authoritative state and dispatch count, not only HTTP outcomes.

| Test | Required observation |
|---|---|
| Financial reservation denial after otherwise valid gates | No ledger/journal/revision change, approval consumption, financial ticket, or tool dispatch; previously charged guard work remains charged |
| Failure after candidate computation or tentative reservation, before publication | No partially published financial state; any tentative financial reservation is discarded with the candidate |
| Concurrent duplicate and competing stale-revision proposals | One financial commit/ticket/approval consumption for the winning action; an exact duplicate replays, a conflicting or stale loser has no financial effect |
| Competing actions with one remaining resource slot | Capacity is never oversubscribed; a loser cannot leave a debit or orphan financial ticket |
| Failure on either side of durable store commit | Before commit: full rollback. After commit/lost response: exact retry returns the same receipt, with no second debit or charge; committed outbox events use stable IDs for deduplication |
| Volatile deployment reset | In-process failures publish no partial joint state; process restart explicitly starts a new genesis/namespace and never claims recovery of the prior ledger |

Run the durable crash cases only when durability is claimed; the volatile reset case is mandatory for volatile deployments. Label observation and guard/model accounting can advance on a denied financial action as documented in C1; the financial nonmutation assertions do not erase those effects. Separate mutable cells without a joint publication boundary do not satisfy these tests.

## Integration milestones

1. Shared exact fixture and strict schemas; product stub response explicitly marked fixture.
2. Positive transfer and rejection through the real compiled kernel path; frontend replaces fixture decision source.
3. Bound owner approval, exact retry, stale policy/revision, and loop/resource denial.
4. Real semantic call and conservative sensitive-data flow; signature feed activation; sanitized audit export.
5. Integrated automated suite, measured performance, truthful assurance panel, maximum-ten-slide submission.

Publish a PR at each milestone with behavior changed, checks actually run, current gaps, and next dependency. Maintain `STATUS.md`; when a contract is changed, both agents update fixtures/tests in the same reviewed change rather than maintaining two subtly different versions.
