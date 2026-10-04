# Final-hardening results (H1 first; grounded parts of H2, H3, H5)

Status: **checked Lean proofs for H1, plus the parts of H2, H3 and H5 that can be stated
against existing compiled definitions.** H4, H6, H7 and the host/SQLite parts of H2, H3 and
H5 were not attempted (see the last section). The 156-record catalog in `scripts/Axioms.lean` is unchanged.
The new results get their own axiom report and are not counted in the catalog.

## Independent submission integration

Both user-supplied final archives had identical extracted contents. Their file SHA-256
for the second attachment is `b5b2d30a7dbed067ddaf9aa0679bdfc0f6e84db8b618ca587a4875dd7373ca79`.
The archived manifest still had `inputRev: v4.28.0`, contrary to the supplied summary;
integration corrected that metadata without changing the resolved dependency revision.
Current submission files were retained rather than replaced by older archive copies.

Independent `make test` passed **14 static tests, 189 runtime/integration cases, the
156 original plus 85 release axiom records, and all nine native H1 checks**. A final
release/worker/tests/benchmark build had no warnings. The axiom gate also rejected a
forbidden-dependency mutation and a missing-record mutation. All 64 runtime receipt
source fingerprints and the worker binary were verified. The revised worker passed a
fresh **ten-case actual local Ollama rehearsal**, including ledger approval/retry,
live invalid-policy retention and restart of the same newly created journal.

[Validation receipt](../../evidence/release-hardening-validation.json) ·
[fresh runtime receipt](../../evidence/integration.json) ·
[fresh live rehearsal](../../evidence/release-h1-live-rehearsal.json).
The earlier model evaluations, live rehearsals and dashboard capture stay unchanged and
identify the older worker. Existing journals bound to that binary are intentionally
refused by the revised worker; no migration is claimed. Use a separate private runtime
for a fresh demo, preserving the old state and matching worker.

## Baseline and fingerprints

* Source: `https://github.com/ljaniec/Mathguard`, commit
  `c1736f92ae8c1dadfaac8c680cade626e2f5486c` (`c1736f9`). The project tree was synced to
  that commit for the original proof campaign. The delivered follow-up also changes the
  approval-null decoder in `Worker.lean`. Integration starts from current upstream
  `27f03da`, retaining the current README, judge guide, dashboard evidence and presentation.
  Mathlib's resolved revision is unchanged; the requirement and manifest input revision
  both use its existing commit hash. A separate `MathguardRelease` library is added.
* Lean `v4.28.0`, Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`.
* Proof-campaign source fingerprints (historical documentation hashes identify the
  campaign's inputs, not the later submission documentation):

| File | SHA-256 |
|---|---|
| `Mathguard/Worker.lean` | `dad3a82a2e713f394047aedf2bd41e3f6934ee1a2754f21a36ecdfec8c202d2b` (was `ddb7f9576bcfdf1fb40020c28b9120de2a7b2fd882cc131de55364ab7271264f` at `c1736f9`) |
| `Mathguard/Spec.lean` | `b5f1f1ecc519435a24442974d679cdab63432df5c6b40aeb39dbfd4a5a63f62b` |
| `Mathguard/OptimizedBudget.lean` | `567d08790f81e3b70c307d267fe44f47f84dc2b72c63a14138025f4d9fbd3b92` |
| `Mathguard/Control.lean` | `ebe09b1525b4d50ca4889acd0f756db5100a189552d2506940d2e649a96c3b65` |
| `Mathguard/Wire.lean` | `421aa3e1452d42a7f6ce8130cd5fa43c9f8763726962b20ea3ee3b7918493252` |
| `Mathguard/Composite.lean` | `00dfcd6f3997592b2489e0b754720df6ce52d7ac36efc49d3cbe6dddf9635192` |
| `Mathguard/PolicyHistory.lean` | `761550f229de3e13c638272038b006670762677ef96b1114e0ff2285d55c968a` |
| `Mathguard/Ledger.lean` | `3647d048e9be9f374568597bfe02e2f8fe186e123450970b596767be26a0d3fa` |
| `Mathguard/Budget.lean` | `a9c4331758012c7db179c7eb8b63f4fec31e75f096af334c4d4ce30be869a285` |
| `aristotle/release/RuntimeSpec.lean` | `5da93063502b4549a1bca8eb9f57b34d352f1955dc6c9545991b59859ef77e72` |
| `aristotle/FINAL-HARDENING-HANDOFF.md` | `2fb043fe65e8aeb08cde53688c1af7f27b334b342793d0eba80159c74ec6e4ca` |
| `docs/15-FINAL-RELEASE-PLAN.md` | `d4db89bae7a9313aff2a5f62dc19ca682e0776e14c4e8cce1b4582b23b5a8176` |
| `docs/verification/RELEASE-ASSURANCE.md` | `ac08023b550af26b98046468d5fc591b97a1de14d8d6518545bdc15fd635dd38` |

No original target statement or `RuntimeSpec` definition was changed. The one production
change is the null test in `Worker.context` (next section); the proofs themselves live in new
files under `aristotle/release/`.

## Commands

```
lake build                                  # production library + demo (unchanged)
lake build MathguardRelease mathguard-worker # RuntimeSpec + release proofs + worker binary
lake env lean scripts/release/ReleaseAxioms.lean   # fresh axiom report (85 theorems)
python3 scripts/release_h1_native.py        # native cases against the compiled worker
```

All four were run for this report. Both builds succeeded. The axiom report lists
85 theorems, each depending on at most `propext`, `Classical.choice` and `Quot.sound`. One
theorem, `TicketsBelow.fresh`, depends on none. There is no `sorryAx`, `Lean.ofReduceBool`
or `Lean.trustCompiler`, and the release files contain no `native_decide`. The full output
is in `release-hardening-axioms.txt`. The native script reported 9 of 9 checks passing.

## Null handling in `Worker.context` (assumption removed)

An earlier version of these results carried an explicit hypothesis `JsonNullTestFaithful`,
because `Worker.context` tested for an approval with `a != Json.null`. Lean core implements
`BEq Json` with a `private partial def`, which the logic cannot evaluate.

`Worker.context` now delegates to `Worker.approvalOpt`, which recognizes an absent approval
by a structural pattern match (`match a with | .null => pure none | a => …`). The decoded
fields and their evaluation/error order are the same as before (approval, then `principal`,
then `now`). With this change the hypothesis is gone: `context_contextJson`,
`dispatch_executeJson_spec`, `dispatch_executeJson_refines`, `dispatch_previewJson_spec`,
`demo_h1_preview` and `demo_h1_dispatch_commit` are all unconditional. The helper
`approvalOpt_of_ne_null` unfolds the decoder on a non-`null` value.

After the change, the full default build, `lake build MathguardRelease mathguard-worker`,
the native H1 script and the 189-test Python runtime suite were rerun and pass. The
recorded rehearsal evidence under `evidence/` predates this change and fingerprints the
earlier `Worker.lean`.

## H1 — exact financial worker transition (`aristotle/release/ReleaseH1.lean`)

| Handoff target | Theorem(s) | Hypotheses |
|---|---|---|
| 1 `FinancialInvariant r.state` | `executeCore_financialInvariant` | `FinancialInvariant s` |
| 2 commit iff ledger commits and exact ticket reserves+charges | `executeCore_committed_iff` | none |
| 2 (capacity form) | `executeCore_committed_iff_capacity`, `WorkerInvariant.committed_iff_capacity` | `BudgetInvariant s.budget` and `s.nextTicket ∉ s.budget.seen`, or the reachable `WorkerInvariant` |
| 3 commit: ledger, `spent 3 + 1`, dims 0–2, pending, next ticket | `executeCore_commit_state` (full state equality), `executeCore_commit_exact` | `BudgetInvariant s.budget` |
| 4 noncommit: nothing published | `executeCore_noncommit_unchanged` | none |
| 4 replay: no reservation/charge, any policy/clock/approval | `executeCore_exact_replay`, `executeCore_replay_any_policy_clock_approval`, `executeCore_replayed_iff`, `executeCore_conflict` | none |
| 5 actual `Worker.dispatch` of `executeJson` | `dispatch_executeJson_refines`, `dispatch_executeJson_spec` (totality and exact branch), `dispatch_executeJson_uninitialized` | none |
| 5 preview does not mutate; `ALLOWED` iff execute would commit | `dispatch_previewJson_spec` | none |
| 6 decoders invert encoders | `request_requestJson`, `context_contextJson` | none |
| ticket freshness from a reachable invariant | `TicketsBelow`, `executeCore_ticketsBelow`; for every command, see H2 below | — |

Reply mapping: `ExecuteReplyTag` maps `committed` to `COMMITTED`, `replayed` to `REPLAYED`,
and `blocked` to `BLOCKED` or `PENDING_APPROVAL`. In every branch the reply is
`Worker.result s' tag reason`, so the reason string (for example `APPROVAL_REQUIRED`,
`BUDGET_EXHAUSTED`, `IDEMPOTENCY_CONFLICT`) is kept. `executeReplyTag_committed_iff`
states that the reply reports a commit exactly on the committing branch.

Rejected counterexamples, by theorem:

* Publishing the ledger before a failed reservation: `executeCore_noncommit_unchanged`,
  `executeCore_of_reserve_none`.
* Incrementing the next ticket on preview or replay: `dispatch_previewJson_spec`,
  `executeCore_exact_replay`.
* Refunding earlier charges on denial: noncommit leaves the budget unchanged, and
  `dispatch_monotone` shows spent never decreases.
* Charging two slots or zero slots: `executeCore_commit_exact`.
* Equating C1 states with the runtime: H1 is stated directly on `Worker.State`, with no
  appeal to C1.

The worker's `internal settlement failure` branch is unreachable
(`chargeBound_after_reserve_isSome`), which is why the dispatch is total on initialized
workers.

Kernel-checked concrete cases (`decide`, no `native_decide`): `demo_h1_fresh_commit`,
`demo_h1_capacity_denial`, `demo_h1_expired_exact_replay` (policy epoch 7 to 8, expired
approval, late clock) and `demo_h1_conflict`. `demo_h1_preview` and
`demo_h1_dispatch_commit` run through the actual `Worker.dispatch` (no assumption).

Native cases (`scripts/release_h1_native.py`): the command bytes come from the Lean
`executeJson`/`previewJson` encoders (`scripts/release/H1Commands.lean`) and are piped into
the compiled `mathguard-worker`. The checks cover: uninitialized rejection, preview,
fresh commit (one slot), expired exact replay after a policy reload, conflict, capacity
denial (no ticket consumed). All 9 checks passed (the former tenth check, of the
compiled `Json` null test, is no longer needed). This is a
runtime test, not a proof.

## H2 — exact-response replay, at the worker level (`aristotle/release/ReleaseDispatch.lean`)

* `dispatch_ok_cases`: any accepted command, of any kind, makes one of seven state
  transitions. No JSON assumption is needed.
* `dispatch_preserves_workerInvariant`, `workerFrame_preserves_workerInvariant`,
  `initial_workerInvariant`: the reachable invariant is
  `FinancialInvariant ∧ TicketsBelow`. It derives freshness of the financial ticket for
  every reachable state.
* `dispatch_monotone`: journal and seen-ticket prefixes, spent, the next ticket and (once
  initialized) the policy epoch never go backwards.
* Target 1: `replayCompleted_nil`, `replayCompleted_append`,
  `replayCompleted_append_of_ok`.
* Target 2: `replayCompleted_ok_state` (equals sequential `workerFrame` replay) and
  `replayCompleted_preserves` (invariants, tickets, charges).
* Target 4, worker level: `committed_retry_replays`, `retry_after_replay`. After a commit
  and any later successful replay, an exact retry by the same principal is `.replayed`,
  with no new debit or charge.
* Target 5, in part: `replayCompleted_mismatch` and `replayCompleted_append_of_error` (a
  response mismatch yields no recovered state).
* `replayCompleted_rejected`: a recorded rejected command does not abort replay. Its
  hypothesis is the compiled `==` on the recorded frame.

Not covered: `DurableState`, `begin`/`complete`/`crash`/`recover`/`acknowledge`, sequence
and version binding, receipts, SQLite, fsync, locking, and target 6. These need the frozen
host persistence contract.

## H3 — generic approval binding (`aristotle/release/ReleaseApproval.lean`)

* Targets 1–3, on the unchanged `RuntimeSpec` definitions:
  `genericApprovalValid_iff`, `genericApprovalValid_fields`,
  `consume_rejects_other_binding`, `consume_rejects_changed_interaction`,
  `consume_rejects_changed_content`, `consume_rejects_changed_config`,
  `consume_marks_used`, `consume_twice_fails` (any interaction, any time, same timestamp
  included) and `consume_after_expiry_fails`.
* Target 4 uses a proposed model, defined here for review: `issueGenericApproval`
  (owner-authenticated, `used = false`) and `genericAdmit` (G1 gate with
  `approved := genericApprovalValid …`, combined with budget admission). Results:
  `issued_valid`, `genericAdmit_irreversible`, `semantic_review_blocks_despite_approval`
  and `unavailable_blocks_despite_approval` (balanced or strict model unavailability is not
  owner-overridable).
* Target 5: `freshApprovalNonce_fresh` (monotone allocator above consumed and outstanding
  nonces), `probe_nonce_fresh` (the worker's synthetic probe nonce),
  `length_allocator_collides` (the `len+1` counterexample) and
  `refs_invalid_after_restart`.
* Not covered: refinement to the host's approval records and digest binding, and the
  host's race and restart behaviour.

## H5 — worker-level reload (`aristotle/release/ReleaseReload.lean`)

* `dispatch_configure` and `configure_preserves`: an accepted `configure` keeps the
  ledger, spent, pending, seen and next ticket. The new limit is at least spent plus
  reserved in every dimension. The epoch strictly increases once the worker is initialized.
  The new compiled controls are valid and active.
* `rejected_command_unchanged`: a rejected command, including a rejected reload, leaves
  the state unchanged.
* `configure_stales_old_epoch`: after a reload, requests bound to an older epoch cannot
  freshly commit.
* `dispatch_control_configure`: a controls-only reload changes nothing else.
  `controlPolicy_valid` shows that the parser only returns valid control policies.
* Not covered: the host's two-file last-good snapshot, feed versions, its persistence
  envelope, and re-sanitization of retained history.

## Not attempted

* H4 (byte-level decoder), H6 (provider call stages) and H7 (audit trace and export)
  need host structures that the handoff says must first be frozen against the final
  implemented host contract. There are no compiled Lean definitions for them in `c1736f9`.
* No result here claims detector completeness, model quality, latency, exactly-once
  external effects, tamper resistance, or that the host runs these definitions. The
  assurance claim for the full stack remains as stated in `RELEASE-ASSURANCE.md`.
