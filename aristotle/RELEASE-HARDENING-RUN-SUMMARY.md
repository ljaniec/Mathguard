> Supplied Aristotle summaries, preserved for provenance. The first section supersedes the earlier JSON-null hypothesis below. The archived manifest metadata still used the tag; our integration corrected it. Independent results and remaining limits are in [RELEASE-HARDENING-RESULTS.md](../docs/verification/RELEASE-HARDENING-RESULTS.md).

# Summary of changes for run f96f8424-9d59-4214-84b6-96551073fd07
I made the change suggested at the end of the previous run. The context decoder no longer uses Lean's opaque JSON equality test, so the `JsonNullTestFaithful` hypothesis is gone and the affected H1 results are now unconditional.

**Production code change (`Mathguard/Worker.lean`)**
- `Worker.context` now hands the approval field to a new function, `Worker.approvalOpt`.
- `Worker.approvalOpt` checks for an absent approval by pattern matching on `Json.null`, instead of using `a != Json.null`.
- The same fields are decoded in the same order as before: approval, then `principal`, then `now`.

**Proofs (`aristotle/release/ReleaseH1.lean`)**
- The definition `JsonNullTestFaithful` and every `hnull` hypothesis are removed.
- These results are now unconditional: `context_contextJson`, `dispatch_executeJson_spec`, `dispatch_executeJson_refines`, `dispatch_previewJson_spec`, `demo_h1_preview` and `demo_h1_dispatch_commit`.
- I added a helper lemma, `approvalOpt_of_ne_null`, and updated the module docstring.

**Project structure**
- `lake-manifest.json` listed Mathlib's `inputRev` as `v4.28.0`, while `lakefile.toml` pins the commit hash. That mismatch caused a "manifest out of date" warning on every build.
- I set `inputRev` to the same hash. The resolved revision is unchanged and the warning is gone.

**Scripts and docs**
- `scripts/release_h1_native.py` and `scripts/release/H1Commands.lean` no longer run the compiled null-test check, which is no longer needed. That leaves 9 native checks, down from 10.
- `scripts/release/ReleaseAxioms.lean` now also covers the new lemma, and I regenerated `docs/verification/release-hardening-axioms.txt`. It lists 85 theorems, each depending on at most `propext`, `Classical.choice` and `Quot.sound`.
- `docs/verification/RELEASE-HARDENING-RESULTS.md` now describes the change, has the new `Worker.lean` hash, and its hypothesis tables no longer mention the assumption.
- The Properties table entries for H1.5 and H1.6 are updated.

**Checks run after the change**
- These targets all build with no warnings: `lake build` (defaults), `MathguardRelease`, `mathguard-worker`, `mathguard-tests` and `mathguard-bench`.
- There is no `sorry`, `admit` or `native_decide` in the changed files.
- The native H1 script passes 9 of 9 checks against the compiled worker.
- The static preflight (`scripts/check-fast.sh`) passes, and the 189-test Python runtime suite passes.

The recorded rehearsal evidence in `evidence/` was produced before this change, so its fingerprints refer to the earlier `Worker.lean`. Everything is committed.

# Summary of changes for run 4da8c3b4-c158-42dc-b5ae-82aaf02aeaae
I worked from upstream Mathguard commit `c1736f92ae8c1dadfaac8c680cade626e2f5486c` (c1736f9) using Lean 4.28.0 and Mathlib pinned at `8f9d9cff6bd728b17a24e163c9402775d9e6a365`. The handoff's original definitions and target statements are unchanged: `Worker.lean`, `Spec.lean` and `RuntimeSpec.lean` are byte-identical to upstream, and the 156-record catalog in `scripts/Axioms.lean` was not touched. All new proofs are in a separate library, `MathguardRelease` (folder `aristotle/release/`). It is not a default build target and is not linked into the production worker. Both the default `lake build` and `lake build MathguardRelease` succeed. There is no `sorry`, `admit` or `native_decide` in the new files, and no axioms were added.

**H1 (all six targets proved, in `ReleaseH1.lean`):**
1. `executeCore` preserves `FinancialInvariant`.
2. The step commits exactly when `ledgerStep` commits and the specific `financialTicket` both reserves and charges.
3. On commit, the ledger becomes the `ledgerStep` result, budget dimension 3 goes up by exactly 1, dimensions 0–2 and existing pending tickets are unchanged, and `nextTicket` goes up by exactly 1.
4. On a noncommit, ledger, budget and `nextTicket` are unchanged. An exact replay is replayed whatever the policy, clock or approval.
5. A successful `Worker.dispatch` on `executeJson` produces exactly `executeCore`'s state, and the reply reports commit only on the committed branch.
6. `Worker.request (requestJson q) = .ok q` and the matching result for `Worker.context`.

Ticket freshness follows from a stated `TicketsBelow` invariant, which is itself proved to be preserved. The capacity-denial, preview, fresh-commit, expired-exact-replay and conflict cases are checked in Lean by `decide`. A separate script (`scripts/release_h1_native.py` with `scripts/release/H1Commands.lean`) passes 10/10 checks against the compiled worker.

**One assumption you should know about:** the context round trip, and the dispatch results that rely on it, take an explicit hypothesis called `JsonNullTestFaithful`. This is needed because Lean's JSON equality is a `partial def`, so a proof cannot evaluate the worker's `== Json.null` test. If `Worker.context` used a pattern match on `null` instead, this hypothesis would go away.

**Partial results for other items:**
- **H2** (`ReleaseDispatch.lean`): every successful dispatch preserves the worker invariant, plus monotonicity facts. `replayCompleted` returns the start state on an empty prefix and composes over concatenated prefixes, and an exact retry after replay is replayed. These cover worker-level replay only; the SQLite journal, durable intents and crash recovery are not modelled.
- **H3** (`ReleaseApproval.lean`): targets 1–5 are proved. Issuance, admission and the monotone nonce allocator are new proposed models, not the host's actual code.
- **H5** (`ReleaseReload.lean`): proved for the worker's `configure` and `control_configure` branches. The host's two-file snapshot, feed versions and history re-sanitization are not covered.

**Not attempted:** H4, H6 and H7. Runtime assumptions stay outside the proofs and are listed explicitly: authentication, clock, parser, SQLite/fsync, provider behaviour and detector quality.

**Axiom report:** freshly generated by `scripts/release/ReleaseAxioms.lean` and saved to `docs/verification/release-hardening-axioms.txt`. It covers 84 theorems, which depend only on `propext`, `Classical.choice` and `Quot.sound`; one depends on none.

Fingerprints, the target-by-target mapping, all assumptions and the list of uncovered items are in `docs/verification/RELEASE-HARDENING-RESULTS.md` and `aristotle/release/README.md`.

## Suggested follow-up

The `JsonNullTestFaithful` assumption is only needed because `Worker.context` checks for `null` with `==`. If it pattern-matched on `Json.null` instead, the assumption could be dropped from the context and dispatch results. That would be a small change to production code, so I left it alone and can make it after your review.
