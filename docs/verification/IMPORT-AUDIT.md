# Aristotle import audit — 3 October 2026

Source: user-supplied `67b0cd4c-acaa-40a7-8292-bec3a55e0c80-aristotle.tar.gz`, run `d1f899d1-689d-42d3-ba08-41d4778ff40c`.

## Findings

- Imported one Lake library, five `Mathguard/` modules, the demo executable, pinned toolchain/manifest, 55-target axiom script, and supplied report.
- Production definitions have the same normalized bodies as the original request. Imports/module visibility changed and a bounded decidability instance for `usageLE` was added. This instance permits executable settlement without changing the predicate.
- The 25 ledger, 14 budget, and 16 flow target signatures match the original request after whitespace normalization and the existing implicit account-count binder are accounted for. The isolated-funds witness indentation repair is syntactic.
- Production source contains no proof holes, explicit new axioms, or native-decision proof shortcuts under the static source check. The supplied axiom report contains all 55 target names and only `propext`, `Classical.choice`, and `Quot.sound`; some targets have no axioms.
- The original `aristotle/` files remain unchanged as historical requests and are excluded from the default Lake library/executable targets. Do not build the duplicate standalone files into the library.
- Preserve the existing repository logo and source reference files. The import does not replace them with archive copies.

## Verification status

The supplied run reports a warning-free `lake build` and observed native demo outputs. **This integration environment has no Lean/Lake/Elan executable and has not independently rerun those commands.** Static comparison and supplied reports support provenance; they are not a fresh kernel check. `scripts/check-lean.sh` provides the local rebuild, current axiom audit, and native demo command sequence. Its missing-toolchain path fails, rather than reporting success.

## Runtime boundary

`ledgerUpdate_eq` is a definitional equality between the update wrapper and the reviewed transition. `atomicLedgerStep` uses `IO.Ref.modifyGet`; this is a useful in-memory runtime boundary, with atomic behavior supplied by the Lean runtime implementation. It does not prove authentication, durable commits, policy/context construction, combined budget/ledger transactions, crash recovery, or whole-stack concurrency correctness. A separate `cell.balances` read after an update may observe a later transition if other callers run; production receipts should come from the same update/transaction rather than a subsequent read.

Pinned source: https://github.com/leanprover/lean4/blob/v4.28.0/src/Init/System/ST.lean. The implementation uses an `implemented_by` runtime routine for reference modification. Runtime semantics/compiler behavior remain trusted; no native-evaluation shortcut is used in the model proofs.

## Build hygiene

The imported manifest had a stale root package name `RequestProject`; this import changes only that metadata to match `lakefile.toml`'s `Mathguard`. Dependency SHAs remain unchanged, including Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`. No GitHub Actions workflows are added. The historical Aristotle summary/report is retained and labeled as supplied evidence.

## Prelint review disposition

The first review identified that the canonical `scripts/check-local.sh` path was absent and the formal-only script did not invoke an integration suite. The full release entry point now exists: it runs the formal checks and requires `scripts/test-integration.sh`, failing if the still-unimplemented gateway suite is missing. `check-lean.sh` remains explicitly the formal/demo subgate, not a full release check.

Runtime call-site documentation now states volatility and warns that the independent balances read is not a commit receipt. The imported API name is preserved for source compatibility; atomic reference modification and durability are distinct guarantees. The enforcement handoff requires commit-correlated responses and a deliberate volatile/durable deployment choice. Combined gating is the first new formal request. Actual model/guard resource consumption may still be charged on failed financial requests; only the financial-tool ticket is coupled to a new transfer in that request. CI remains disabled per project preference; PR app review and local gates are retained.
