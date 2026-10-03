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