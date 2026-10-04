# Mathguard next campaign — C1 / P1 / W1 verification report

Date: 2026-10-03.

## Workspace mode

The previous Mathguard project (baseline run d1f899d1-689d-42d3-ba08-41d4778ff40c) **was available**
in this workspace and was **rebuilt from source** here: `lake build` succeeded with no warnings and
the 55 baseline axiom records were regenerated and are byte-identical to the previously recorded
`docs/verification/axioms.txt` entries. The baseline modules `Mathguard/Spec.lean`,
`Ledger.lean`, `Budget.lean`, `Flow.lean` and `Runtime.lean` were not modified.

`Mathguard/Spec.lean` was compared with the canonical definitions of the campaign brief (section 5).
There is **no substantive mismatch**. The only difference is the `usageLE.decidable` instance, which
the brief's canonical text also contains. Comments and line breaks differ, but the definitions are
the same. No baseline definition is duplicated: the new modules import `Mathguard.Spec` and the
baseline proof modules, and they reuse `ledger_initial_invariant`, `ledger_step_invariant`,
`noncommit_no_mutation`, `fresh_commit_authorized`, `fresh_commit_versions`,
`budget_initial_invariant`, `reserve_preserves`, `labelLE_refl`, `labelLE_trans`,
`label_join_upper_left` and `label_join_upper_right`. Because the baseline proofs were available,
no `CoreLemmas.lean` was needed.

## Toolchain

* Lean `leanprover/lean4:v4.28.0` (`lean-toolchain`).
* Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365` (tag `v4.28.0`). This is now pinned by commit
  in `lakefile.toml`. The manifest already resolved to this commit; only its `inputRev` field was
  changed to the hash.

## Module structure

| Module | Imports | Namespace |
|---|---|---|
| `Mathguard/Composite.lean` | `public Mathguard.Spec`, `Mathguard.Ledger`, `Mathguard.Budget`, `Mathguard.Flow` | `Mathguard.Next` |
| `Mathguard/PolicyHistory.lean` | `public Mathguard.Spec`, `Mathguard.Ledger` | `Mathguard.Next` |
| `Mathguard/Wire.lean` | `public Mathguard.Spec` | `Mathguard.Next` |

Each module is a Lean `module` with an `@[expose] public section`. The root `Mathguard.lean`
imports all production modules, and none of them imports the root, so there is no import cycle.
The unchanged request statements, with their intentional `sorry` holes, are in `aristotle/next/`.
That directory is outside the Lake build. Each request file elaborates against `Mathguard.Spec`
with no errors (`lake env lean aristotle/next/<file>.lean` reports only the expected
`declaration uses 'sorry'` warnings).

## Commands and observed results

```
lake build                               # Build completed successfully (1952 jobs), no warnings
lake exe mathguard                       # baseline demo output unchanged, plus C1/P1/W1 lines (below)
lake env lean scripts/Axioms.lean        # 98 records = 55 baseline + 35 new + 8 supporting
python3 scripts/check_next_statements.py # RESULT: PASS, 35 theorem statements compared
```

The demo now also prints:

```
== Composite admission (C1, pure joint update)
accepted action: committed, balances [97500, 22500, 0], spent=[0, 0, 0, 0] reserved=[1, 1, 1, 1] pending=1
exact retry: replayed, spent=[0, 0, 0, 0] reserved=[1, 1, 1, 1] pending=1
hard deny with semantic permit: blocked
secret observation to public sink: blocked, label raised: true
== Policy activation (P1)
active epoch after reload: 8
history outcomes: [blocked, committed]
== Wire projection (W1)
roundtrip ok: true
unknown account rejected: true
```

The demo is runtime testing, not proof. The corresponding proved witnesses are
`demo_composite_accepts`, `demo_reload_blocks_old_request`, `demo_reload_accepts_new_request`,
`demo_wire_decodes` and `demo_wire_rejects_unknown_account`. All five are proved by
kernel-checked `decide` (or, for `demo_wire_decodes`, by `wire_roundtrip`).

## Target status

**Baseline: 55 of 55** were previously proved. They were rebuilt here and are unchanged.

**New: 35 of 35 proved.**

C1 composite financial admission (14 of 14 proved): `composite_initial_invariant`,
`composite_commit_exact`, `composite_commit_gates`, `composite_step_invariant`,
`composite_label_never_lowers`, `composite_observation_retained`,
`composite_noncommit_financial_nonmutation`, `composite_hard_deny_cannot_be_overridden`,
`composite_sensitive_flow_denied`, `composite_budget_denial_prevents_commit`,
`composite_replay_no_new_reservation`, `composite_trace_invariant`,
`composite_trace_label_never_lowers`, `demo_composite_accepts`.

P1 policy activation and historical evidence (12 of 12 proved): `governed_initial_invariant`,
`governed_step_invariant`, `governed_trace_invariant`, `policy_reload_preserves_financial_state`,
`nonincreasing_policy_epoch_rejected`, `policy_epoch_never_decreases`,
`policy_epoch_trace_monotone`, `old_epoch_cannot_fresh_commit_after_reload`,
`governed_history_extends`, `historical_authorization_uses_own_snapshot`,
`demo_reload_blocks_old_request`, `demo_reload_accepts_new_request`.

W1 typed wire projection (9 of 9 proved): `wire_roundtrip`, `wire_decode_preserves_fields`,
`wire_projection_injective`, `wire_source_out_of_range`, `wire_destination_out_of_range`,
`wire_valid_indices_decode`, `wire_approval_cannot_match_changed_fields`, `demo_wire_decodes`,
`demo_wire_rejects_unknown_account`.

**New exported supporting theorems: 8.** These are proved helpers, not targets.

* In `Composite.lean`:
  * `compositeStep_label`: the label is always the join with the observation.
  * `compositeStep_of_commit`: the committed branch, written out.
  * `compositeStep_committed_iff`: commit happens exactly when the gate passes, the ledger
    commits freshly, at least one tool call is reserved, and the reservation fits.
  * `compositeStep_noncommit`: a non-committed step leaves the ledger and budget unchanged.
  * `transferGate_eq_true_iff`
* In `PolicyHistory.lean`:
  * `EvidenceChain.snoc`
  * `evidenceSound_of_step`
  * `evidenceAuthorized_of_sound`

## Elaboration repairs and semantic corrections

* No elaboration repair was needed. All supplied definitions and statements elaborate as written.
* No statement was found false and no semantic correction is proposed. No statement was changed.
* Other changes (none of them semantic):
  * Each production module has a module header and docstring.
  * Helper theorems are inserted before the targets.
  * Mathlib is pinned by commit.
  * The demo executable is extended.

## Statement comparison

`scripts/check_next_statements.py` takes every top-level declaration in the request files. For a
theorem, it requires the statement text up to `:= by` to appear verbatim in the production module.
For a structure, inductive type or definition, it requires the whole block to appear verbatim.

* Result: C1 14 of 14, P1 12 of 12 and W1 9 of 9 theorem statements match, and all definitions
  match.
* The script also checks that the production modules contain no `sorry`, `admit`,
  `native_decide`, `decide +native`, `axiom`, `implemented_by`, kernel-skip option or `unsafe`.
* It also checks that no production module imports the root module.

This is a static source comparison; the proof check is `lake build` together with the axiom report.

## Fresh axiom dependencies (new targets)

The full output is in `docs/verification/axioms.txt`. No record contains `sorryAx`,
`Lean.ofReduceBool` or `Lean.trustCompiler`. The new results use only:

* `propext`, `Classical.choice`, `Quot.sound`:
  * all 14 C1 targets;
  * `governed_initial_invariant`, `governed_step_invariant`, `governed_trace_invariant` and
    `historical_authorization_uses_own_snapshot`;
  * the five C1 supporting theorems.
* `propext`, `Quot.sound`:
  * the remaining 8 P1 targets;
  * `evidenceSound_of_step` and `evidenceAuthorized_of_sound`.
* `propext`: `wire_roundtrip`, `wire_decode_preserves_fields`, `wire_projection_injective`,
  `wire_source_out_of_range`, `wire_destination_out_of_range`, `demo_wire_decodes` and
  `demo_wire_rejects_unknown_account`.
* No axioms: `wire_valid_indices_decode`, `wire_approval_cannot_match_changed_fields` and
  `EvidenceChain.snoc`.

## Verification boundary

The proofs cover the pure Lean model. In particular:

* **C1** proves a pure joint state update. It does not prove that separate database writes or
  mutable cells are atomic.
  * The assessment, source label, sink, policy and resource bound are trusted adapter inputs.
    C1 does not authenticate them.
  * The request epoch does not show that an assessment was produced against the exact immutable
    policy contents.
  * C1 neither refunds nor accounts for earlier proposer/classifier costs.
  * On denial or replay, the ledger and budget are unchanged, but the context label may rise.
* **P1** is a separate ledger-and-history model, not composed with C1's budget/label state.
  * Activation assumes an authenticated, validated administrator.
  * An exact committed retry may still replay after a reload. Only a fresh commit under a stale
    epoch is excluded.
* **W1** starts after strict JSON parsing, canonical integer-string validation and account-name
  resolution. It is not a verified JSON parser.

None of these packages establishes:

* authenticated runtime context construction or genuine approval issuance;
* correct JSON parsing;
* trustworthy catalog or label provenance;
* semantic-classifier accuracy;
* provider resource bounds;
* database concurrency or crash recovery;
* full noninterference;
* end-to-end security of the deployed product.

The overall claim remains "model verified; runtime tested".

## Repository

No pull requests were opened. This environment has no write access to `ljaniec/Mathguard`, so all
work is delivered in this project tree.
