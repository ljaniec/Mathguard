# Mathguard

<img width="3344" height="1248" alt="project_logo" src="https://github.com/user-attachments/assets/47c7bbf7-8e97-408e-877c-0ed70a49a4d8" />


**LLMs propose actions. Mathguard checks which actions may change the ledger.**

Hybrid control-layer prototype for HackYeah 2026, Goldman Sachs **AI Control Layer**. The reference application is a simulated personal-account ledger; the assessed product is the AI control layer around agents, model calls, and ledger/MCP tools.

## Start here

1. [Source-checked challenge requirements and delivery gaps](docs/10-REQUIREMENTS-RECOVERY.md).
2. [Current runtime/API contract](docs/07-TEAM-INTEGRATION-CONTRACT.md).
3. [Product-agent assignment](docs/08-AGENT-PRODUCT-HANDOFF.md) and [engine-agent assignment](docs/09-ENFORCEMENT-HANDOFF.md).
4. [Updated submission description](docs/01-PRODUCT-AND-CHALLENGE.md).
5. [Codex bootstrap for Astra / Sol 6.1](docs/02-CODEX-BOOTSTRAP.md).
6. [Agent, product, and visualization specification](docs/03-AGENT-PRODUCT-VISUALIZATION.md).
7. [Enforcement-engine specification](docs/04-ENFORCEMENT-ENGINE.md).
8. [Detailed mathematical model and assurance boundaries](docs/05-FORMAL-MODEL.md).
9. [Aristotle instructions and theorem acceptance criteria](aristotle/README.md).
10. Checked Lean development: [definitions](Mathguard/Spec.lean), [ledger proofs](Mathguard/Ledger.lean), [budget proofs](Mathguard/Budget.lean), [flow proofs](Mathguard/Flow.lean), [runtime commit boundary](Mathguard/Runtime.lean). Original requests: [aristotle/](aristotle/README.md).
11. [Validation matrix, demo, and delivery gates](docs/06-VALIDATION-AND-DEMO.md).

## Status — 2026-10-03

The supplied Aristotle run reports all **55 model-v1 targets proved** under Lean 4.28.0 / Mathlib `8f9d9cff` (`v4.28.0`), with a warning-free build and native demo. The code, original statements, and supplied axiom report pass the static import audit: [IMPORT-AUDIT.md](docs/verification/IMPORT-AUDIT.md).

The performance-review work independently rebuilt all **55 baseline targets** with the pinned toolchain and checked **five additional reservation-refinement/snapshot targets**. The fresh axiom report, native regression tests, and measured results are in [PERFORMANCE-REVIEW.md](docs/verification/PERFORMANCE-REVIEW.md). The original supplied report remains separate evidence. The callable gateway now executes the actual Lean ledger/budget/flow functions. Its authentication, parsing, policy handling, provider adapter and composed runtime are tested code, not additional formal proofs. Live-model quality evidence and submission packaging remain open; see [STATUS.md](STATUS.md).

## Run the control layer

Prerequisites: Python 3.10+, the pinned Lean 4.28.0 toolchain, Mathlib dependencies/cache, and an available local OpenAI-compatible model server. No Python third-party package is required. First-time Lean/Mathlib setup needs network access; a warm checkout can run tests offline.

1. Set `MATHGUARD_MODEL_URL` to your local server's `/v1` endpoint (default `http://127.0.0.1:11434/v1`).
2. In `policies/demo.json`, replace **both** `allowed_models` and `semantic_model` with the exact installed model ID. For later reloads, increment `epoch`.
3. Run `bash scripts/demo.sh` and open `http://127.0.0.1:8787`.
4. Paste the separate random operator/agent/owner tokens from the local launcher into the corresponding dashboard fields. Keep them out of recordings and source control.
5. Connect a session, try a prompt, propose a 2500-minor-unit transfer, then exact retry. For 10000 or more, use the separate owner approval and resubmit the exact request.

```sh
bash scripts/check-local.sh       # proof, native, audit and gateway tests
# Use the launcher's AGENT token in this environment variable:
export MATHGUARD_AGENT_TOKEN='<local agent token>'
python3 agent/run.py --model '<exact model ID>' 'Pay Bob 25 PLN for lunch'
python3 scripts/evaluate-live.py --model '<exact model ID>' \
  --corpus tests/development-prompts.jsonl --label development \
  --output evidence/live-development.json
```

Edit the policy/signature files and use Reload to demonstrate activation. Invalid edits retain the last valid configuration; startup without one closes execution. Model failure/timeout retains budget charges and quarantines further calls. After stopping/verifying the upstream job, use explicit operator recovery to preserve the ledger and all charges. The deployment is **single-process and volatile**; restart creates a fresh ledger. Budget values are conservative accounted bounds, not actual provider bills. There is no bundled model or claimed live-model result from this development environment.

### Layout

| Path | Contents |
|---|---|
| `Mathguard/Spec.lean` | Reviewed model-v1 definitions (ledger, budget, flow) |
| `Mathguard/Ledger.lean` | Ledger targets plus helper lemmas (journal replay, admission unpacking, trace induction) |
| `Mathguard/Budget.lean` | Budget targets plus helper lemmas (unique-ticket removal, reservation/settlement characterisations) |
| `Mathguard/Flow.lean` | Information-flow targets plus helper lemmas (label preorder, trace monotonicity) |
| `Mathguard/Runtime.lean` | In-memory runtime boundary: `atomicLedgerStep` installs `(ledgerStep p s ctx q).state` in one `IO.Ref.modifyGet` |
| `Mathguard/OptimizedBudget.lean` | Allocation-reducing totals/reservation implementation with exact equality proofs against the unchanged model |
| `Mathguard/Worker.lean` | Private JSONL worker executing the reviewed functions; runtime adapter/composition is tested |
| `gateway/`, `agent/`, `dashboard/` | Callable control layer, reference agent and interactive operator UI |
| `policies/`, `feeds/`, `contracts/` | Versioned policy profiles, data-only signatures and inert artifact fixture |
| `tests/` | Native-worker integration and provider-protocol regressions |
| `Main.lean` | Demo executable running the reviewed kernels on the `n = 3` fixtures |
| `scripts/Axioms.lean` | `#print axioms` for 55 baseline and 5 additional targets |
| `Tests.lean`, `Bench.lean` | Native snapshot/budget regressions and ledger/budget size sweeps |
| `aristotle/` | The original proof-request pack (kept unchanged as the specification of record; not part of the build) |

### Build, check, run, generate C

```sh
lake exe cache get              # Mathlib cache
lake build                      # production library and executable; historical requests excluded
lake env lean scripts/Axioms.lean
lake exe mathguard              # runs the demo
```

`bash scripts/check-fast.sh` runs a static preflight without Lean. `bash scripts/check-lean.sh`
runs the incremental formal build/fresh audit/demo/native-test subgate. The canonical
`bash scripts/check-local.sh` is the full release entry point: it also requires the
gateway integration suite at `scripts/test-integration.sh` and fails if it is absent.
The gateway integration suite now exists and uses the real Lean worker with explicitly labeled classifier fixtures. Passing it does not establish live classifier accuracy or complete the hackathon submission.

`python3 scripts/profile-checks.py --lean-files --iterations 100` collects actual
build/frontend/audit timings, peak RSS, and native benchmark JSON/CSV. Returned runtime
snapshots come from `atomicLedgerStepResult`; the demo no longer renders balances read
independently after a commit. Neither API supplies durable or authenticated public receipts.


Every definition in `Mathguard/Spec.lean` is computable. `lake build` translates the kernel and runtime modules
to C in `.lake/build/ir/Mathguard/*.c` (e.g. `Spec.c` contains `ledgerStep`, `admission`, `budgetStep`,
`flowAllowed`), compiles them, and links `.lake/build/bin/mathguard` against the Lean runtime.

### Elaboration and metadata repairs (behavior unchanged)

1. `Mathguard/Spec.lean`: added the instance `usageLE.decidable` (`usageLE` is a bounded `∀` over `Fin 4`); without it the `if` in `settle` does not elaborate.
2. `demo_isolated_funds_rejection`: the continuation line `approvalThreshold := 200000` was indented one column less than the first structure-instance field, which is a parse error; it is now aligned. The statement is otherwise identical.
3. The root package name in `lake-manifest.json` is aligned with `lakefile.toml`; dependency SHAs are unchanged.

The three contributors have separate hackathon projects. Mathguard is Łukasz Janiec's project. The workstream documents describe roles for coding agents or optional helpers; they do not assume Przemek or Cezary is available to implement Mathguard.

The attached official brief requires a functional layer, centralized configurable policy, deterministic and semantic controls, budget governance, historical attack mitigation, reporting, and an executable positive/negative suite. Formal methods strengthen those deliverables; a standalone banking proof does not replace them.

## Reference material

The audit in [reference/SOURCE-NOTES.md](reference/SOURCE-NOTES.md) comes from reading both uploaded Goldman PDFs. The spelling of `CRIETRIA` follows the source filename. The detailed criteria and rules disagree on the last two weights; keep that discrepancy visible until the mentors resolve it. The full task archive is not redistributed here.

Aristotle contribution: run `d1f899d1-689d-42d3-ba08-41d4778ff40c`; supplied summary in [ARISTOTLE_SUMMARY.md](ARISTOTLE_SUMMARY.md).

No GitHub Actions workflows are introduced. Use reproducible local checks. Changes are submitted through PRs for review and Prelint feedback.
