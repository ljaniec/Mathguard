# Summary of changes for run ee5d328d-e8bc-4314-adc1-393b7ff9b6b7
I took "these requirements" to mean the Goldman Sachs AI Control Layer brief and rules in `reference/`, plus the Polish compendium PDF. The full answer is in `docs/07-REQUIREMENTS-ADAPTATION.md`. To back the design with checked proofs, I added a new Lean module, `Mathguard/Control.lean`. It builds with no `sorry`, and its axiom report shows nothing beyond `propext` and `Quot.sound`.

**The main gap.** The current design does most of its work on the ledger. The judges, though, score a general gateway that blocks, redacts or passes *every* AI interaction (prompts, model calls, MCP/tool calls, agent-to-agent messages, model-artifact loads), driven by a policy file they will edit live. The proposed change: keep the ledger as the showcase example of an irreversible tool, and put a generic, formally specified decision kernel in front of every interaction.

**The new kernel, `Mathguard/Control.lean`.** It's computable and compiles to C with the rest of the library. A decision is a set of independent flags (deny, ask for approval, redact), so no stage can relax another. The proved properties:
- **Hybrid controls:** a semantic "safe" verdict can never override a deterministic denial (`gate_executes_imp_hard`, `Decision.combine_executes`).
- **Strictness modes:** if the local model times out or returns malformed output, strict mode blocks, balanced mode asks for review, and permissive mode passes but records an alert.
- **Live policy edits:** tightening any setting can only add restrictions (`gate_mono`).
- **Policy reload:** a candidate is validated first, the last valid version is kept, and with no valid policy everything is blocked (`reloadAll_active_valid`, `no_policy_fail_closed`).
- **Runaway loops:** a session never dispatches more than `maxSteps` interactions (`sessionRun_steps_le`).
- **Signature feed:** content matching a feed signature is denied whatever the classifier says (`signature_denied`).
- **Model artifacts:** an artifact loads only if its hash is pinned and its format can't run code; pickle is always refused (`artifact_admitted_pinned_safe`).
- **Irreversible tools** require an approval record, and tool and model allowlists are enforced.
- **Audit log:** append-only, with exactly one event per interaction (`sessionRun_log`, `blockedCount_step`).
- **Memory isolation:** retrieval returns only the caller's entries (`recall_owned`).

Six concrete examples are also checked by `decide`. `lake exe mathguard` now prints the same cases at runtime, for example a loop of 5 under a step limit of 3: 3 dispatched, 5 logged, 2 blocked. That output is a runtime test, not a proof.

**What the design document covers:**
- the target architecture, with a diagram;
- how to run the proved code inside the request path: a long-lived compiled Lean worker is recommended over a C library or a Python re-implementation;
- how to keep the atomic commit requirement, using one SQLite transaction per `ledgerStep` commit;
- changes for each formal requirement: policy profiles, PII and secret detectors, a local Ollama model with a deadline, budgets and step limits, the signature feed, artifact scanning, the dashboard and export, and a three-tier test suite with a held-out prompt set and encoded, Polish, split and indirect attack variants;
- an OWASP LLM Top 10 table that labels each control as proved or design-only;
- a work order ranked by scoring weight, and questions to put to the organizers.

**Limits.** The proofs cover how detector outputs are combined and enforced. They don't show that the PII detector or the semantic model actually catches attacks, and they don't cover authentication, the JSON handling around the kernel, or crash and concurrency behaviour. So the claim stays "model verified; runtime tested" until the compiled kernel is the code deciding live requests. The compendium also says the deadline is 4 Oct at 11:00, not the 23:00 in the rules.

I also updated `README.md` and `scripts/Axioms.lean` (now 151 entries) and regenerated `docs/verification/axioms.txt`. All changes are committed.

# Summary of changes for run 6fe765d1-f56d-479f-abec-8894a2f99a0f
All 35 new targets are proved, with their statements unchanged: C1 14 of 14, P1 12 of 12, W1 9 of 9. No statement turned out to be false, so I'm not proposing any semantic corrections. No elaboration repairs were needed: every definition and statement you supplied compiles exactly as written. The full report is in `docs/verification/NEXT-CAMPAIGN.md`.

**Previous project.** The earlier 55-proof project was in the workspace, and I rebuilt it from source here. The 55 baseline targets (25 ledger, 14 budget, 16 flow) are unchanged, and their fresh axiom records are identical to the earlier ones. `Mathguard/Spec.lean` matches your canonical definitions in substance. Its `usageLE.decidable` instance is also in your text; only comments and layout differ. I didn't edit any baseline module. The new modules reuse the existing definitions and lemmas (`ledger_step_invariant`, `noncommit_no_mutation`, `fresh_commit_authorized`, `fresh_commit_versions`, `reserve_preserves`, and the label lemmas) instead of copying them. Because those proofs were available, I didn't need a `CoreLemmas.lean`.

**Versions.** Lean `v4.28.0` and Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`. `lakefile.toml` now pins that commit hash instead of the `v4.28.0` tag. The manifest already pointed to this commit; I only changed its `inputRev` field to the hash.

**Project structure.**
- New modules: `Mathguard/Composite.lean`, `Mathguard/PolicyHistory.lean` and `Mathguard/Wire.lean`, all in namespace `Mathguard.Next` with exported sections.
- They import `Mathguard.Spec` publicly, plus the proof modules they need. None of them imports the root, so there is no import cycle.
- `Mathguard.lean` imports all of them.
- Untouched copies of your request statements, with their intentional `sorry`s, are in `aristotle/next/`, outside the build. They compile with nothing but the expected `sorry` warnings.

**Commands and results.**
- `lake build`: succeeded (1952 jobs), no warnings.
- `lake exe mathguard`: the baseline demo output is unchanged. New lines show:
  - C1: an accepted action committing with balances 97500/22500/0 and 1 tool call reserved; an exact retry replaying with no new reservation; a hard denial blocking despite a semantic permit; a secret observation to a public sink blocked, with the label raised.
  - P1: after the reload, the old-epoch request is blocked and the new-epoch request commits.
  - W1: the round trip works and an unknown account is rejected.
  These demo lines are runtime tests, not proofs.
- `lake env lean scripts/Axioms.lean`: 98 records (55 baseline, 35 new, 8 new helper theorems). I extended this script to cover `Mathguard.Next`.
- `python3 scripts/check_next_statements.py`: PASS. This new script checks that all 35 theorem statements and every definition match the request files word for word, that the new modules contain no `sorry`, `admit`, `native_decide`, `axiom` or similar, and that none imports the root. It compares source text only; the actual proof check is the build plus the axiom report.
- `rg` finds no `sorry`, `admit` or `native_decide` in the production code.

**Targets.**
- **C1** (`Mathguard/Composite.lean`): `composite_initial_invariant`, `composite_commit_exact`, `composite_commit_gates`, `composite_step_invariant`, `composite_label_never_lowers`, `composite_observation_retained`, `composite_noncommit_financial_nonmutation`, `composite_hard_deny_cannot_be_overridden`, `composite_sensitive_flow_denied`, `composite_budget_denial_prevents_commit`, `composite_replay_no_new_reservation`, `composite_trace_invariant`, `composite_trace_label_never_lowers`, `demo_composite_accepts`.
- **P1** (`Mathguard/PolicyHistory.lean`): `governed_initial_invariant`, `governed_step_invariant`, `governed_trace_invariant`, `policy_reload_preserves_financial_state`, `nonincreasing_policy_epoch_rejected`, `policy_epoch_never_decreases`, `policy_epoch_trace_monotone`, `old_epoch_cannot_fresh_commit_after_reload`, `governed_history_extends`, `historical_authorization_uses_own_snapshot`, `demo_reload_blocks_old_request`, `demo_reload_accepts_new_request`.
- **W1** (`Mathguard/Wire.lean`): `wire_roundtrip`, `wire_decode_preserves_fields`, `wire_projection_injective`, `wire_source_out_of_range`, `wire_destination_out_of_range`, `wire_valid_indices_decode`, `wire_approval_cannot_match_changed_fields`, `demo_wire_decodes`, `demo_wire_rejects_unknown_account`.
- **8 new helper theorems** (proved, not targets): `compositeStep_label`, `compositeStep_of_commit`, `compositeStep_committed_iff`, `compositeStep_noncommit`, `transferGate_eq_true_iff`, `EvidenceChain.snoc`, `evidenceSound_of_step`, `evidenceAuthorized_of_sound`.
- The concrete witnesses are checked by the kernel with ordinary `decide`, or, for `demo_wire_decodes`, by applying `wire_roundtrip`.

**Axioms.** No new result depends on anything beyond the standard three, and none uses `sorryAx`, `ofReduceBool` or `trustCompiler`.
- `propext`, `Classical.choice`, `Quot.sound`: all 14 C1 targets; the four P1 invariant/authorization results; the five C1 helper theorems.
- `propext`, `Quot.sound`: the other 8 P1 targets and two P1 helpers.
- `propext` only: 7 W1 targets.
- No axioms: `wire_valid_indices_decode`, `wire_approval_cannot_match_changed_fields`, `EvidenceChain.snoc`.
The complete output is in `docs/verification/axioms.txt`.

**What this does not establish.** These are proofs about the pure Lean model.
- C1 is a pure joint state update. It does not prove that database writes or mutable cells are atomic. It doesn't authenticate the assessment, label, sink, policy or resource bound, and it doesn't show that an assessment was made against the exact policy contents.
- P1 is a separate model, not combined with C1. It assumes the administrator is authenticated, and an exact retry may still replay after a reload.
- W1 is not a verified JSON parser.
- None of the packages covers authenticated context construction, genuine approval issuance, label provenance, classifier accuracy, provider resource bounds, database concurrency or crash recovery, full noninterference, or end-to-end security.

The overall claim is still "model verified; runtime tested". I opened no pull requests because I don't have write access to the repository; all the work is in this project.

# Summary of changes for run d1f899d1-689d-42d3-ba08-41d4778ff40c
All 55 theorem targets in the Mathguard model-v1 pack are now proved in Lean 4.28.0 / Mathlib `v4.28.0`: 25 ledger, 14 budget and 16 flow. `lake build` passes with no warnings. There is no `sorry`, `admit`, `native_decide` or added axiom in the project. Running `#print axioms` on every target lists only `propext`, `Classical.choice` and `Quot.sound`; the output is saved in `docs/verification/axioms.txt`. A script compared every theorem statement in my files with the original request files and they all match.

**Project structure.** The old build could not have worked: `import Spec` didn't resolve, and the three standalone files repeated the same definitions. The project is now one Lake library plus an executable:
- `Mathguard/Spec.lean`: the reviewed definitions, unchanged in meaning.
- `Mathguard/Ledger.lean`, `Mathguard/Budget.lean`, `Mathguard/Flow.lean`: the proofs. Each has a module docstring and named helper lemmas, including:
  - unpacked forms of `admission` and `approvalOK`;
  - `ledgerStep_committed_iff`, plus helpers that replay the journal one entry at a time;
  - a general induction principle over ledger traces;
  - an exact lemma for removing a ticket by its unique ID (`sum_filter_id_ne_add`);
  - characterisations of `reserve` and `settle`;
  - the reflexivity, transitivity and monotonicity facts for labels.
- `Mathguard.lean`: imports everything.
- `scripts/Axioms.lean`: reruns the axiom report.

The original `aristotle/` pack is left unchanged as the specification of record, with a status note added; it is not part of the build. `README.md` now describes the layout, the build and check commands, and the repairs below.

**Two repairs to get the files to compile.** Neither changes what the code does or what the theorems say.
1. Added a `Decidable` instance for `usageLE`, which checks a condition for each of the 4 resources. Without it the `if` inside `settle` does not compile.
2. In `demo_isolated_funds_rejection`, the line `approvalThreshold := 200000` was indented one column short, which is a parse error. It is now aligned.

**C code and the atomic commit.** Every definition can be compiled. `lake build` turns the model into C under `.lake/build/ir/Mathguard/`; for example `Spec.c` contains `ledgerStep`, `admission`, `settle`, `budgetStep` and `flowAllowed`. It then links a native binary.
- `Mathguard/Runtime.lean` adds `atomicLedgerStep`. It runs the reviewed `ledgerStep` and stores the new state in a single `IO.Ref.modifyGet` call. `ledgerUpdate_eq` proves that the update it performs is exactly `ledgerStep`'s outcome and new state.
- `Main.lean` (`lake exe mathguard`) runs the demo cases. Observed output: a commit giving balances 97500/22500/0, an exact retry that replays, a blocked stale request, a high-value request blocked without approval and then committed with an approval bound to it, the budget refusing a second 6-of-10 reservation, and the flow checks.

**Limits.** What is verified is the model. The proofs say nothing about the runtime pieces: authentication, how the context is built, persistence, or how the policy is configured. `atomicLedgerStep` running the reviewed transition is true by construction, not a proved theorem about concurrency. So the "model verified; runtime tested" limit in your docs still holds for everything outside the model.