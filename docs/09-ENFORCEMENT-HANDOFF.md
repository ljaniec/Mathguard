# Mathguard — specification for the enforcement-engine AI agent

## Copy-paste assignment

Implement the actual Mathguard gateway/enforcement engine in `https://github.com/ljaniec/Mathguard`. You are a team member's AI coding agent. Use PRs at each milestone so Prelint and the coordinator can review progress. Coordinate through `docs/07-TEAM-INTEGRATION-CONTRACT.md`; own `gateway/`, `policies/`, `feeds/`, engine tests, and startup integration. Łukasz owns model/proof semantics. Propose any Lean worker/adapter additions in a narrow PR with that owner; do not change `Mathguard/Spec.lean` or redo the completed 55 proofs to make an implementation easier.

Start from imported foundation PR #1 / `integration/aristotle-model-v1` or its merged successor. Read `docs/04-ENFORCEMENT-ENGINE.md`, `docs/verification/IMPORT-AUDIT.md`, the shared contract, and this assignment. The current binary runs **hard-coded demonstrations**; it is not already a JSONL worker, API gateway, authentication service, persistence layer, or complete product.

The supplied Aristotle run reports all 55 original model targets checked under Lean 4.28.0 and pinned Mathlib. Static import checks pass; independent local rebuild is not available in the integration environment. You must run the pinned checks on your host and keep the distinction visible. The next 35 targets are requests, not verified modules.

## Objective

Deliver a functional lightweight hybrid control layer that mediates agent/model/tool interactions, applies one versioned policy catalog, restricts actions with semantic checks, controls budgets, accepts data-only historical signatures, and emits useful security evidence. A simulated ledger is its reference application. Its private executor must execute the reviewed transition rather than a separately invented banking algorithm.

The engine must enforce the hard policy for arbitrary model proposals. No model output, caller identity claim, fake approval boolean, guessed label, or parsed explanation may supply authority.

## Foundation you may reuse

- `Mathguard/Spec.lean`: executable ledger/budget/flow definitions.
- `Mathguard/Ledger.lean`: exact guard extraction, journal/invariant/trace/replay/approval/version lemmas.
- `Mathguard/Budget.lean`: atomic accounting-model reservation/settlement invariants and exact ticket-removal lemmas.
- `Mathguard/Flow.lean`: label joins, output gates, semantic restrict-only lemmas.
- `Mathguard/Runtime.lean`: `ledgerUpdate`, definitional equality `ledgerUpdate_eq`, in-memory `atomicLedgerStep`.
- `Main.lean`: examples only; do not parse its printed demo as an API.

`IO.Ref.modifyGet` is the in-memory update primitive supplied by Lean's runtime. The ledger cell does not include the budget, active policy, approval registry, or durable audit outbox. Putting those in separate mutable cells does not create one joint transaction. The equality theorem does not prove database concurrency or crash safety.

## Execution strategy — select once, document

Preferred: a persistent compiled Lean worker executes typed pure transitions for a private authoritative state, or returns a next-state value for a serialized store transaction. Add a separate executable target such as `mathguard-worker`; keep the demo target. JSONL input/output needs a schema, bounded buffers, and stderr-only diagnostic logging. Financial responses must come from the same transition snapshot.

Two acceptable initial deployments:

1. **Single-process, volatile PoC:** one serialized owner of all ledger/resource/policy state; reset starts a new genesis/namespace. Clearly label data as volatile and do not claim crash recovery.
2. **Durable gateway/store PoC:** take an authoritative SQLite snapshot under a serializable transaction, call the reviewed pure worker with the canonical state/request, verify request/epoch/revision bindings, and commit exactly the returned ledger/resource state, idempotency record, approval consumption, and audit outbox together. Crash before commit has no effect; after commit, exact retry returns the receipt.

Do not let a volatile worker commit ahead of a separate durable database and then call that transaction atomic. If the worker is a pure candidate calculator, its state cannot independently advance before the store commits. If durability is not ready, choose the first deployment honestly and test it.

A Python mirror is a fallback only: differential-test it against the Lean worker and state **model verified; runtime mirror tested; refinement unproved**. No permissive fallback when the Lean worker times out/crashes. Keep financial endpoints closed on unavailability.

## First engine milestone

1. Run `bash scripts/check-lean.sh` on the pinned workspace/cache; record result, executable/source hashes, and environment.
2. Create strict shared schema and the canonical three-account fixture in `contracts/` with the product agent. Match the actual `demoPolicy`; do not add Bob's beneficiaries while claiming the identical formal fixture.
3. Implement server-issued demo credentials, every-request authentication, principal/context construction, and a private action route.
4. Add the worker adapter and authoritative transition/store boundary. Return positive Alice → Bob 2500 and an isolated insufficient-funds rejection through the same route.
5. Assert exact balances/journal/revision after positive and negative paths. Do not advance UI/backend counters independently of the authoritative result.

## Required controls

| Area | Implementation | Required negative/positive evidence |
|---|---|---|
| Strict wire parsing | Canonical decimal strings, duplicate/unknown-key rejection, account/currency/size bounds | Zero/negative/fractional/overflow/unknown account rejected; valid string preserved |
| Identity/authority | Gateway-derived principal; catalog ownership/capabilities/beneficiaries | Properly authenticated wrong owner blocked; permitted owner allowed |
| Ledger arithmetic | Reviewed `ledgerStep`, sufficient funds/distinct endpoints/caps | Exact transfer/conservation/frame; isolated denial cases |
| Approval | Owner-only protected issuance; exact canonical request/revision/epoch/expiry/nonce | Substitution, forgery, expiry, reuse blocked; boundary-valid approval accepted |
| Replay/versioning | Exact committed payload + principal; unique ID; latest revision/epoch | Duplicate nonmutation, conflict, concurrent old-revision requests |
| Resources | Reserve before model/semantic/tool dispatch; settle bounded actual; charge unknown bound | Oversubscription denied; no zero-cost local-compute bypass |
| Semantic restriction | Separate bounded real guard adapter with exact action/policy binding | Hard deny survives semantic safe; semantic veto/review restricts |
| Data flow | Trusted source/sink labels; whole-context joins; remote model/output gates | Sensitive export denied; permitted internal/public data allowed |
| Attack feeds | Validated bounded data-only signatures, provenance/version | Reload catches new example; invalid feed cannot disable required guard |
| Audit/reporting | Sanitized per-stage traces, resource deltas, policy/feed/proof refs | Useful export without credentials/secret payloads |

The detailed old engine specification contains full failure and threat semantics. Keep those requirements unless a specific scope cut is explicitly documented and reflected in the assurance panel.

## Composite gate and transaction order

Apply cheap hard checks, reserve the semantic/model call, obtain its bounded assessment, then perform the financial action's joint admission/commit. No action executes before its actual hard/flow/semantic/resource gate succeeds. A semantic “safe” never erases a hard denial. Review adds an extra trusted approval prerequisite; it cannot waive owner/funds/version/cap checks.

Bind semantic assessment to the complete canonical action and active policy snapshot. Revalidate policy epoch/state revision after asynchronous work. An owner approval cannot authorize new economic fields or new version bindings. Do not silently rebase/retry an old approved payment at a new revision.

Implement the shared contract's exact `PENDING_APPROVAL` rule: all non-approval gates must pass, and only an absent required high-value approval or catalog-authorized semantic review may remain unresolved. Supplied invalid approvals, hard denials, explicit semantic denials/unavailability, stale proposals, and ID conflicts stay blocked/closed. Report the exact approval requirements; approval issuance alone cannot execute anything. Add isolated tests proving these distinctions.

New C1 request models a joint ledger/budget/label transition. You can implement this pipeline using the existing kernels while C1 is pending, with a tested composition boundary. Do not label the composition formally verified until C1 is checked and the runtime actually executes the reviewed composite function or has a reviewed refinement argument. Similarly P1 supports policy-history claims and W1 covers typed account-index projection only.

Implement every applicable test under the shared contract's **Joint transition acceptance tests**. Failure injection after a tentative financial reservation must leave no orphan ticket, debit, approval consumption, or commit receipt. Race tests must inspect actual authoritative state and dispatch counts. E2 requires duplicate/revision races and E3 requires budget competition/rollback tests; E4 adds durable crash recovery or explicit volatile reset tests. Earlier guard/model charges and conservative label joins are retained, not refunded by a later financial denial.

## Resource details

Use `[cost_micros,tokens,compute_ms,tool_calls]`. Derive conservative bounds from model/provider/token/deadline settings and trusted prices; never accept caller bounds as authority. Limit queue length/inflight and require a positive call slot. Budget the semantic guard, proposer, retries, tools, and API ingress abuse appropriately. Reserve session/global buckets atomically or fail all-or-none; counters survive policy reload.

Actual usage ≤ reserved bound permits settlement. Unknown/failure usage charges full bound. A coroutine timeout does not stop a GPU/remote job; hold/charge the reservation and enforce real cancellation/worker termination or a documented bounded provider contract. Usage above the reservation is an anomaly/quarantine, not a refund-and-continue path. Zero API price still has token/time/call limits. Report accounted budget guarantees separately from provider overbilling/clock/runtime assumptions.

## Context/approval/policy construction

Lean `Context` assumes trusted principal, time, and resolved approval. Do not expose raw context construction to the financial agent. Account ownership and labels come from the catalog/registry, not tool arguments. A session key correlates work but is not authentication. Model/tools use scoped credentials held only by gateway adapters.

Catalog reload: validate schema and supported rule names; freeze immutable contents; activate a strictly higher epoch; preserve ledger/debit/resource counters and history. Invalid catalog/feed retains last good controls. A request at the old epoch cannot make a fresh commit; already committed exact retry may replay a minimal authorized receipt. Budget limit reduction below spent plus reserved must reject or enter explicit quarantine, never reset usage.

Use safe JSON or safe data-only YAML loading; no pickle or executable expressions. Historical signatures match text/structured configuration without running malicious payloads. Paths/domains/tools use explicit allowlists. Unknown actions fail closed. Disable plugin installation, arbitrary shell, untrusted model loaders, and unsafe deserialization in the initial executor.

## Data boundaries

Confidentiality and provenance are separate. Join user/tool/document/context labels conservatively. Model outputs, generated tool arguments, persisted memory, logs, UI audiences, and remote model inputs inherit the context classification. The remote model itself is an outbound sink: do not send confidential context to a low-clearance provider and then only gate the final answer.

Regex masking preserves the original classification; it is not verified declassification. Useful lower-sensitivity structured summaries require an explicit reviewed projection/release rule. Current proofs are label-gate safety, not full noninterference or perfect prompt-injection detection.

## Milestone PRs and tests

| PR | Work | Evidence |
|---|---|---|
| E1 | Worker/strict schemas/authenticated positive-negative ledger path | Pinned build; exact store state and engine responses |
| E2 | Bound approval, replay, revision race, catalog activation | Forgery/substitution/expiry/concurrent duplicate tests |
| E3 | Model/semantic/resource/flow/feed mediation | Dispatch-count assertions, oversubscription tests, real guard call |
| E4 | Durable/volatile contract, audit/events/startup/performance | Crash/retry if durable; truthful mode; measured stage timings |

Use `docs/06-VALIDATION-AND-DEMO.md`'s existing detailed matrix. Assert state and dispatch counts, not just response status. Isolate guard failures; do not claim five tests from one input violating five predicates. Add generated/differential vectors at parser/worker boundaries with reproducible seeds and critical amount/version/expiry boundaries. Prove/tests must remain tied to the same definition hash.

Each PR description: concrete behavior, executed checks, formal/runtime boundary, unimplemented dependency, next milestone. Read Prelint findings and resolve real correctness issues; do not invent approval from silence. Keep `STATUS.md` current. No new GitHub Actions; use local scripts and repository app reviews. Keep all credentials outside version control.

## Definition of done

The reference agent cannot bypass model/tool/store gates. Real valid/invalid ledger actions, approvals, replay, version checks, budget admission, semantic restrictions, flow checks, feed reload, and sanitized reports run through the public engine. A startup script and executable offline suite exist; one available real local-model guard interaction is demonstrated. Performance is measured, not fabricated. The proof panel states exactly which pure model targets are checked and which parser/auth/store/provider/composition guarantees are assumptions or tests.
