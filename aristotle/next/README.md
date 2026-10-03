# Next Aristotle campaign — three focused requests

Baseline: imported run `d1f899d1-689d-42d3-ba08-41d4778ff40c`, Lean 4.28.0, Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`. **The original 55 targets are completed according to that run. Do not re-prove them, rewrite their definitions, or rebuild duplicate standalone models.** Reuse `Mathguard.Spec`, `Mathguard.Ledger`, `Mathguard.Budget`, and `Mathguard.Flow`.

These new request files are **uncompiled specifications with intentional proof holes**, excluded from the production Lake targets. The local integration environment has no Lean toolchain. They must first be typechecked in the supplied pinned project. The proof goal is to connect already proved mechanisms to useful integration behavior while preserving model-v1.

| Priority / run | File | Targets | Result sought |
|---|---|---:|---|
| First — C1 | `CompositeRequest.lean` | 14 | One financial transition requires hard/semantic/flow permission and atomic tool-resource reservation; ledger and budget invariants compose |
| Second — P1 | `PolicyHistoryRequest.lean` | 12 | Safe policy reload with monotone epochs and immutable evidence of the policy that authorized each historical action |
| Third — W1 | `WireRequest.lean` | 9 | Exact projection between typed account indices/wire fields and requests; no silent amount/beneficiary/version substitution |

Total: **35 new targets**, not 35 completed proofs. Run C1 first; P1 and W1 are independent once the pinned project imports successfully. If capacity allows independent runs, they may proceed separately; never run multiple expensive full Mathlib builds on the same host.

## Paste this common instruction into each run

Continue Mathguard from the supplied **buildable Lake project**, not from the old standalone authoring pack. The baseline already has all 55 model-v1 proofs. First verify the pinned imports/build and run `scripts/Axioms.lean`. Reuse those theorems as lemmas. Do not change or redo them.

Work on only the assigned request file under `aristotle/next/`. It imports `Mathguard` and adds a namespace `Mathguard.Next`; this avoids the previous unresolved `import Spec` and repeated-definition problem. First typecheck its definitions/targets. Preserve exact transition semantics and theorem statements. Identify elaboration-only repairs. If a target is false, return a minimal counterexample and proposed semantic repair; do not silently weaken the statement or add its conclusion as an assumption.

Replace every target `sorry` with an ordinary kernel-checkable proof. No arbitrary axioms, `admit`, `native_decide`, `decide +native`, kernel-skip options, declaration tricks, unsafe proof bypass, or new trust shortcuts. Inspect `#print axioms` for every new exported theorem. Standard `propext`, `Classical.choice`, and `Quot.sound` are permitted and must be reported.

When complete, place reviewed definitions/proofs in a **single production module** (`Mathguard/Composite.lean`, `Mathguard/PolicyHistory.lean`, or `Mathguard/Wire.lean`), with correct module visibility/imports for Lean 4.28.0. Import it once from `Mathguard.lean`. Keep the original request unchanged as the specification of record and outside the release build. Preserve all existing dependency pins. Update the axiom script to include the new exported targets, and report baseline vs new counts separately.

Return the modified project, exact build/check commands and results, axiom report, statement-comparison report, accepted/blocked witnesses, and a bounded assurance explanation. Do not call a file with remaining holes fully verified. Do not claim database, authentication, actual provider spend, JSON-parser correctness, or full deployed security from these targets.

## C1 — composite financial supervisor

The existing proofs concern separate kernels. A gateway can still fail if it commits the ledger before checking a budget or if a semantic verdict overwrites a hard denial. C1 defines a **pure joint state update**: ledger + budget + conservative context label. A candidate commit occurs only after the flow/hard/semantic gate, ledger admission, a positive tool-call reservation, and budget reservation all succeed.

On financial rejection/replay, ledger and budget remain unchanged; the observed label still joins into the context. This is intentional and must not be mistaken for a theorem that every field is unchanged. Exact replay does not allocate a new financial-tool ticket once the gate permits delivery. The original ledger's replay meaning remains intact, but the composite output gate may still deny delivery.

`Assessment.boundRequest` must match the exact candidate request; its epoch/revision are included in that request. The Boolean semantic permit is a restrict-only input. The outer runtime must obtain this assessment from a trusted guard adapter and bind it to the active catalog; the model does not prove the classifier's accuracy or artifact authenticity. Likewise source labels, sink metadata, hard-extra predicate, and resource bounds are trusted adapter inputs.

The financial-tool reservation is made in the same **modeled** state update as the ledger commit. Semantic/model calls are separately budgeted before they happen; C1 does not charge a classifier invocation retroactively. Resource settlement uses the existing budget kernel after the tool invocation. The executor must eventually implement an atomic joint state/store transaction or serialize the joint state under one owner. The current `IO.Ref (Ledger n)` wrapper alone does not provide a joint budget/ledger transaction.

Proof order: gate extraction, committed-result characterization, noncommit frame, preservation from the two existing invariant lemmas, label upper bounds, denial corollaries, trace induction over arbitrary per-input policies, accepted witness. Do not add global invariants to admission.

## P1 — versioned policy and historical evidence

The existing `ledger_trace_authorized` uses one policy. After a policy change, asking whether all old entries satisfy the **new** permissions is the wrong claim. P1 stores the immutable active policy snapshot with each attempted transition and proves history consistency/authorization against that snapshot.

Policy activation requires a strictly increasing epoch and never rewrites balances, counters, approvals, or history. Every transfer evidence record contains exact before/after, policy, context, request, and outcome. `EvidenceChain` links those transitions from genesis to the current ledger. Fresh actions under an old epoch cannot commit after a higher-epoch activation; exact old receipts may still replay without a new financial effect.

The `activate` event assumes an authenticated/config-validated administrator. No theorem proves that an arbitrary caller may not create this event. The implementation must enforce that boundary. In-memory policy values are mathematical snapshots; runtime snapshots need immutable catalog contents/version IDs. Ownership, cap changes, and semantic settings belong to catalog validation; this request does not invent new business restrictions beyond model-v1.

Proof order: evidence soundness/authorization for one constructed record, chain append helper, initialization and step preservation, trace induction, epoch and history frame lemmas, old/new request witnesses. Reuse policy-parametric `ledger_step_invariant`.

## W1 — typed wire projection

W1 starts **after strict JSON/string integer parsing and account-name resolution**. A `WireTransfer` uses naturals, not floats or unchecked strings. Its two account indices must be below `n`; `fromWire` constructs `Fin n` only with those proofs. IDs, amount, epoch, and revision pass through unchanged. Roundtrip/injectivity prevents the typed adapter from silently altering a candidate or approval binding.

This is a useful narrow refinement theorem, not a complete JSON-parser theorem. Duplicate JSON keys, integer grammar/length bounds, unsupported currency, credential extraction, account-name registry injection, and process serialization remain implementation obligations. Do not rename W1 “verified JSON parser.” Do not add context principal/approval creation fields to the wire transfer.

After completion, the enforcement agent should call this definition from the Lean worker or demonstrate that its index projection is exactly this function; a separate unproved mirror does not inherit the theorem automatically.

## Gate after return

Open one PR per completed package. Include the statement comparison and current axiom report; keep the 55-target baseline green. Prelint findings must be read and addressed; tool silence is not an approval. The coordinator runs local checks on the integrated head before any assurance count is updated. Deferred theorem/runtime boundaries remain visible in `STATUS.md` and the dashboard.
