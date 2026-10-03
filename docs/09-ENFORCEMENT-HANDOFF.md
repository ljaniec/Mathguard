# Copy-paste assignment: enforcement engine and live security evidence

You are the enforcement-engine AI agent for **Mathguard**, `https://github.com/ljaniec/Mathguard`, HackYeah 2026 Goldman Sachs AI Control Layer. Start from the newest reviewed challenge-recovery PR/branch. Use PRs and Prelint, local checks, and no GitHub Actions. Own `gateway/`, `policies/`, `feeds/`, engine tests and startup/evaluation scripts. Coordinate `Mathguard/Worker.lean` changes with Łukasz, the formal-model owner.

Read `STATUS.md`, `docs/10-REQUIREMENTS-RECOVERY.md`, `docs/07-TEAM-INTEGRATION-CONTRACT.md`, then the broader `docs/04-ENFORCEMENT-ENGINE.md`. The worker/gateway/dashboard now exist. Do not implement a Python banking mirror or repeat the original 55 proofs. The model and five extra equality targets are checked; the new parser/worker composition/provider/runtime boundary is tested, not proved.

## P0: make the live hybrid path demonstrable

1. Run `bash scripts/check-local.sh` with pinned Lean 4.28.0 / Mathlib. Keep the worker executable separate from `Main.lean`'s native demo. Record exact SHA and evidence.
2. Connect the actual available local OpenAI-compatible endpoint. Set `MATHGUARD_MODEL_URL`; set both model catalog fields to its exact model ID. Record server/model/weights revision and license. Ollama's compatible endpoint is typically under `/v1`; verify against the installed server rather than assuming it supports all response-format options.
3. Run one normal model interaction and one semantically suspicious request that does not merely hit a known literal signature. Show an actual structured AI verdict. Invalid JSON, timeout, missing model or transport failure closes the current operation and must never count as a successful detector classification.
4. Run the reference agent through the public gateway, including a valid financial proposal. Owner approval remains separate; the agent must never receive owner/operator credentials or a direct provider/worker route.
5. Run `scripts/evaluate-live.py` against a development corpus and a separately human-authored unseen corpus. Label the latter accurately; do not call a jointly developed suite “held out.” Report attack success, false positives and availability/schema failures separately, by category.
6. Rehearse judge edits to active policy and signature feed. The current design reloads on the next authenticated POST; it has explicit reload, strict validation, monotonic versions and last-good retention. Preserve all ledger/resource counters. Removing a text signature must not remove the Lean ownership/funds/replay guards.

## Current implementation boundary to preserve

- One gateway lock serializes provider calls, worker transitions and reload. This limits throughput deliberately; report measured latency and queue limits. The Lean worker owns one volatile ledger/global resource budget. No automatic restart after worker failure.
- `execute` uses the actual reviewed `ledgerStep`, `reserveOptimized` and `chargeBound`. Tentative values are pure; state is published only after both financial admission and the tool-slot reservation succeed. Earlier classifier/model charges remain after a financial denial.
- Provider calls reserve a trusted configured bound and charge it in full. Actual-usage refunds are a future optimization. Unknown costs are not assumed zero. The default is a local zero-price model with positive token/time/call charges.
- Timeout kills the adapter process, not necessarily an upstream GPU request. It quarantines further dispatch. Do not silently retry or release the reservation. Adding cancellation needs a verified provider contract or observed job termination.
- Regex masking preserves detected confidentiality. The current detector does not classify every possible natural-language secret. Flow proofs concern trusted labels, not perfect label assignment or noninterference.
- Exact replay returns a prior masked receipt and no new effect/call charge. Stale fresh actions, substituted approvals and conflicts block. A semantic review is blocked; approval does not bypass it.
- Arbitrary shell, unsafe deserialization and model/plugin loading are unavailable. Artifact checks inspect bounded bytes/hash/header/allowlisted provenance without executing them. This does not validate the entire configured provider's weight supply chain.
- Audit is sanitized and bounded/volatile. Do not claim durable crash recovery or tamper-proof forensic retention.

## P1: coverage and evidence improvements

| Task | Acceptance test |
|---|---|
| Actual prompt-injection quality | English/Polish, indirect tool/document content, encoded variants, multi-turn requests and benign near-matches; disjoint evaluation evidence |
| Provider bounds/calibration | Exact tokenization or conservative tested envelope; over-bound usage quarantine; direct vs mediated p50/p95 including errors |
| Complete audit metadata | Per-stage timing/charges, active policy/feed hashes, sanitized reasons; parser/auth rejects visible without raw payloads |
| Source-backed historical signatures | Each representative signature has source, attack family, version and benign counterexample; safe inert payload only |
| Policy schema edge cases | Duplicate keys, unknown fields, invalid ranges, lower limits, stale versions, failed feed, concurrent edit |
| Principal/session abuse | Foreign session, role escalation, session floods, bound approval substitution/reuse, expired approval retry |
| Budget race/failure | Concurrent resource competition, settlement unknowns, worker death before/after dispatch, no over-admission |
| Packaging | Clean checkout, documented toolchain/cache/model setup; operator can start and run tests without paid API |

Do not advertise universal prompt-injection resistance from a handful of literal matches or classifier fixtures. Separate model detection metrics from deterministic action safety. A hostile model proposal cannot override an invalid ledger action even if its guard verdict is safe.

## P2 after submission

Per-session resource vectors plus atomic global admission; persistent outbox and transaction recovery; scalable single-authority budget service; full MCP transport adapter; generalized ownership catalog; full artifact provenance integration. These are valuable, but not substitutes for the four mandatory deliverables tonight.

For formal follow-up, first align a small exact composite theorem with the function actually executed by the worker: no financial change on rejection, exact replay has no additional financial charge, one committed transfer consumes exactly one tool slot, budget and ledger invariants preserved together, policy reconfiguration preserves counters. Keep provider/authentication/clock/IO assumptions explicit. The previously prepared composite/history/wire request pack is on the planning/integration branch; inspect its current state before creating new Aristotle work. No new request becomes part of the verified count until compiled and axiom-audited.

Every PR must state actual behavior, checks run, current live-model evidence, remaining limits, and requirement IDs from the recovery matrix. Preserve the model definitions unless the formal owner reviews a necessary semantic change.
