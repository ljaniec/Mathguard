# Mathguard

<img width="3344" height="1248" alt="project_logo" src="https://github.com/user-attachments/assets/47c7bbf7-8e97-408e-877c-0ed70a49a4d8" />


**LLMs propose actions. Mathguard checks which actions may change the ledger.**

Bootstrapping and formal-model pack for HackYeah 2026, Goldman Sachs **AI Control Layer**. The reference application is a simulated personal-account ledger; the assessed product is the AI control layer around agents, model calls, and ledger/MCP tools.

## Start here

1. [Updated submission description](docs/01-PRODUCT-AND-CHALLENGE.md).
2. [Codex bootstrap for Astra / Sol 6.1](docs/02-CODEX-BOOTSTRAP.md).
3. [Agent, product, and visualization specification](docs/03-AGENT-PRODUCT-VISUALIZATION.md).
4. [Enforcement-engine specification](docs/04-ENFORCEMENT-ENGINE.md).
5. [Detailed mathematical model and assurance boundaries](docs/05-FORMAL-MODEL.md).
6. [Aristotle instructions and theorem acceptance criteria](aristotle/README.md).
7. Checked Lean development: [definitions](Mathguard/Spec.lean), [ledger proofs](Mathguard/Ledger.lean), [budget proofs](Mathguard/Budget.lean), [flow proofs](Mathguard/Flow.lean), [runtime commit boundary](Mathguard/Runtime.lean). Original requests: [aristotle/](aristotle/README.md).
8. [Validation matrix, demo, and delivery gates](docs/06-VALIDATION-AND-DEMO.md).

## Team-agent handoffs and next formal work

- [Shared integration contract](docs/07-TEAM-INTEGRATION-CONTRACT.md)
- [Agent/product/visualization AI-agent specification](docs/08-AGENT-PRODUCT-HANDOFF.md)
- [Enforcement-engine AI-agent specification](docs/09-ENFORCEMENT-HANDOFF.md)
- [Next Aristotle campaign: 35 new targets](aristotle/next/README.md)
- [Current status and open deployment boundaries](STATUS.md)

The next requests reuse the completed baseline and add composite gating, policy-history evidence,
and typed wire projection. They are uncompiled requests, excluded from production targets.

## Status — 2026-10-03

The supplied Aristotle run reports all **55 model-v1 targets proved** under Lean 4.28.0 / Mathlib `8f9d9cff` (`v4.28.0`), with a warning-free build and native demo. The code, original statements, and supplied axiom report pass the static import audit: [IMPORT-AUDIT.md](docs/verification/IMPORT-AUDIT.md).

**Independent local Lean rebuild is still required:** this integration environment has no Lean toolchain. The supplied report is retained as external build evidence, not a newly performed kernel check. Run `bash scripts/check-lean.sh` on a machine with the pinned toolchain/cache. Model safety and the runtime boundary remain distinct; authentication, persistence, parser, policy, and combined-control integration are open.

### Layout

| Path | Contents |
|---|---|
| `Mathguard/Spec.lean` | Reviewed model-v1 definitions (ledger, budget, flow) |
| `Mathguard/Ledger.lean` | Ledger targets plus helper lemmas (journal replay, admission unpacking, trace induction) |
| `Mathguard/Budget.lean` | Budget targets plus helper lemmas (unique-ticket removal, reservation/settlement characterisations) |
| `Mathguard/Flow.lean` | Information-flow targets plus helper lemmas (label preorder, trace monotonicity) |
| `Mathguard/Runtime.lean` | In-memory runtime boundary: `atomicLedgerStep` installs `(ledgerStep p s ctx q).state` in one `IO.Ref.modifyGet` |
| `Main.lean` | Demo executable running the reviewed kernels on the `n = 3` fixtures |
| `scripts/Axioms.lean` | `#print axioms` for all 55 targets |
| `aristotle/` | The original proof-request pack (kept unchanged as the specification of record; not part of the build) |

### Build, check, run, generate C

```sh
lake exe cache get              # Mathlib cache
lake build                      # production library and executable; historical requests excluded
lake env lean scripts/Axioms.lean
lake exe mathguard              # runs the demo
```

`bash scripts/check-lean.sh` runs the formal build/audit/demo subgate. The canonical
`bash scripts/check-local.sh` is the full release entry point: it also requires the
gateway integration suite at `scripts/test-integration.sh` and fails if it is absent.
That suite is a next implementation deliverable, so the full release gate is not yet complete.

Every definition in `Mathguard/Spec.lean` is computable. `lake build` translates the kernel and runtime modules
to C in `.lake/build/ir/Mathguard/*.c` (e.g. `Spec.c` contains `ledgerStep`, `admission`, `budgetStep`,
`flowAllowed`), compiles them, and links `.lake/build/bin/mathguard` against the Lean runtime.

### Elaboration and metadata repairs (behavior unchanged)

1. `Mathguard/Spec.lean`: added the instance `usageLE.decidable` (`usageLE` is a bounded `∀` over `Fin 4`); without it the `if` in `settle` does not elaborate.
2. `demo_isolated_funds_rejection`: the continuation line `approvalThreshold := 200000` was indented one column less than the first structure-instance field, which is a parse error; it is now aligned. The statement is otherwise identical.
3. The root package name in `lake-manifest.json` is aligned with `lakefile.toml`; dependency SHAs are unchanged.

Mathguard is coordinated by Łukasz Janiec. The agent/product and enforcement workstreams are now assigned to AI agents run by team members; the shared contract defines ownership and dependencies. Their separate human hackathon projects remain distinct.

The attached official brief requires a functional layer, centralized configurable policy, deterministic and semantic controls, budget governance, historical attack mitigation, reporting, and an executable positive/negative suite. Formal methods strengthen those deliverables; a standalone banking proof does not replace them.

## Reference material

The audit in [reference/SOURCE-NOTES.md](reference/SOURCE-NOTES.md) comes from reading both uploaded Goldman PDFs. The spelling of `CRIETRIA` follows the source filename. The detailed criteria and rules disagree on the last two weights; keep that discrepancy visible until the mentors resolve it. The full task archive is not redistributed here.

Aristotle contribution: run `d1f899d1-689d-42d3-ba08-41d4778ff40c`; supplied summary in [ARISTOTLE_SUMMARY.md](ARISTOTLE_SUMMARY.md).

No GitHub Actions workflows are introduced. Use reproducible local checks. Changes are submitted through PRs for review and Prelint feedback.
