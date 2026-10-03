> **Status update after Aristotle return:** production modules and native demo now exist. All original 55 targets are proved according to the supplied pinned run; static import checks pass. Earlier statements below describing an uncompiled draft refer to the original request pack. Do not redo the completed 55 targets. Independent local rebuild remains required; see `verification/IMPORT-AUDIT.md`.

# Codex bootstrap — Astra / Sol 6.1

Copy the block below into Codex after opening `https://github.com/ljaniec/Mathguard`. It is self-contained; the repository documents supply the detailed contracts. Use high reasoning effort for implementation and the highest available effort for definition/theorem review. Delegation is explicitly authorized below when the harness supports it; it is optional and must not duplicate work.

---

You are implementing **Mathguard**, a HackYeah 2026 Goldman Sachs **AI Control Layer**. Repository: `ljaniec/Mathguard`. The owner is **Łukasz Janiec**, login `ljaniec`. He is the primary human on this project; his teammates have separate projects. Do not assume they will implement your frontend/backend.

The product is a functional hybrid control layer mediating agent/model/MCP/API interactions. The concrete application is a simulated personal-account ledger, not a blockchain or a real bank. An untrusted LLM proposes typed actions. A deterministic supervisor checks them before execution. Lean 4 formalizes the transition functions and proves exact safety properties. A semantic AI guard can veto or require review, but cannot override deterministic prohibitions. Centralized policy, resource accounting, historical signatures, a dashboard, and an executable positive/negative suite are mandatory.

## Read before implementation

Read `README.md`, all `docs/01` through `docs/06`, `aristotle/README.md`, `aristotle/Spec.lean`, and the three request files. Check repository state and applicable `AGENTS.md`. Record the actual official hackathon start/timezone: the supplied rules say 3 October 23:00 through 4 October 23:00. Honor the applicable competition schedule. This pack is a preparatory specification, not an already verified release.

Do not use old Aegis project naming, invent completed work, or silently weaken the definitions. Preserve the source audit. Resolve contradictions by documenting the choice and keeping invariant preservation intact. New evidence may require correcting the model; explain and version any semantic change.

## First 45–60 minutes of actual implementation

1. Create a work branch; inspect existing contributions before writing. If the repository is no longer empty, preserve work and avoid resetting others' changes.
2. Write `STATUS.md`: current SHA, toolchain, available local model, current modules, tests/proofs actually checked, and next blocking action. Update it at each meaningful checkpoint.
3. Pin a Lean/toolchain version supported by the current Aristotle environment. Prefer an available compatible version over speculative upgrades. If Aristotle targets 4.28.0, use that for its request workspace and explicitly port/recheck any production workspace using a different version. Record both. Never reuse `.olean` across incompatible toolchains.
4. Use the matching Mathlib cache. Do not start an uncached full Mathlib build during a hackathon. Keep core imports narrow; prove with `omega`, `simp`, finite sums, list induction. Run one proof build at a time and record memory/time.
5. Compile `Spec.lean` definitions separately from request files. Fix elaboration problems without changing intended semantics. Request files intentionally contain `sorry`; exclude them from release targets and verification badges.
6. Freeze typed JSON schemas and canonical account mapping; create fixtures for an allowed transfer and a blocked overspend.
7. Implement the narrow ledger kernel and a command-line end-to-end request before polishing UI.

## Suggested layout

```text
lean-toolchain
lakefile.toml
Mathguard/Spec.lean              reviewed definitions, no holes
Mathguard/LedgerProofs.lean      checked universal theorems
Mathguard/BudgetProofs.lean
Mathguard/FlowProofs.lean
Mathguard/Adapter.lean           canonical JSON → typed requests
Main.lean                       JSONL worker executable
gateway/                        small typed API/policy/provider adapter
agent/                          structured proposer, no executor credentials
dashboard/                      compact interactive demo
policies/demo.json
feeds/demo-signatures.json
fixtures/                       shared JSON vectors
tests/                          integration/races/negative cases
scripts/check-local.sh
scripts/demo.sh
evidence/                       measured reports and proof manifest
aristotle/                      requests excluded from production build
```

This is a recommendation, not a reason to replace an established working layout. Prefer a thin Python gateway (strict models, SQLite) and a small web dashboard or Streamlit if it saves integration time. Keep the reference transition in Lean. Use one public ingress and a private local worker. The reference agent must not have database credentials, mutation credentials, or a way to call downstream providers around the gateway.

## Formal/runtime strategy

Preferred: compile the reviewed Lean transition definition into a local JSONL worker. The gateway validates/authenticates, takes an atomic state snapshot under a transaction, obtains the worker's decision/next state, and atomically commits that exact result with revision comparison. No second independent implementation may recalculate money movements differently.

If a Lean runtime executable cannot be integrated in time, implement a runtime mirror, differential-test it against the Lean model, and label it **model verified; runtime mirror tested; refinement unproved**. Do not present tests as a refinement theorem. A broken worker or timeout must not fall back to an unverified permissive executor.

Precompile proofs. Do not ask an LLM or Aristotle to prove a theorem for each live request. Offline formalization proposals are untrusted inputs; review definitions and rerun the pinned proof checks before release. Never execute arbitrary Lean/plugin source supplied by a live user in the gateway process.

## Workstreams

If supported, you may delegate independent work to coding agents: (A) reviewed formal definitions/proofs; (B) enforcement engine; (C) agent/dashboard/tests. Freeze JSON contracts first and give each agent separate file ownership. Use cheaper agents only for mechanical documentation, fixtures, and UI tasks; semantic/theorem review requires the strongest available reasoning. One agent coordinates integration. Do not parallelize heavy Lean builds or let two agents change the same formal definitions.

Each workstream must read the formal model. No field such as `verified=true`, `approved=true`, `actor=Alice`, or `taint=public` supplied by the agent is trusted.

## Implementation order and gates

### Gate 0 — definitions and witnesses

Typecheck definitions; review the exact guards and updates. Demonstrate one accepted transfer, one rejected transfer, and a boundary case. Keep `Invariant` out of admission checks: the guard must check concrete operational preconditions, not assume the theorem's conclusion. Confirm arithmetic is integer minor units and `Nat` subtraction is guarded.

### Gate 1 — verified ledger core

Prove conservation of total funds, exact debit/credit, other-account frame, journal reconstruction, revision/journal relation, fresh-commit authorization, approval binding, duplicate nonmutation, and trace preservation. Include a nontrivial accepted witness so a deny-all implementation cannot pass. Inspect `#print axioms`; forbid `sorryAx`, arbitrary axioms, compiler-trust shortcuts, and declaration replacement tricks in claimed proofs. Standard Lean logical axioms must be disclosed if present.

### Gate 2 — actual mediation

Run real structured agent proposals through the gateway. Mediate model requests too; account for the semantic guard itself. Implement private executor, trusted approval resolution, exact duplicate handling, atomic compare-and-swap, and policy epoch revalidation. Prove/test the boundary cases before broader UI work.

### Gate 3 — budgets and data controls

Reserve tokens/time/cost/tool slots before calls; settle actual usage bounded by reservation; quarantine inconsistent provider reports. Local models still consume token/time/concurrency resources even when monetary price is zero. Propagate confidentiality and untrusted provenance independently; gate outputs to remote providers and UI destinations. Add real semantic assessment, reloadable data-only signatures, rate and loop termination.

### Gate 4 — dashboard and adversarial evidence

Implement scenario replay, live prompt mode, ledger before/after, reason traces, approval, policy reload, budget view, and proof-status panel. Make the suite runnable offline with deterministic fixtures. Run at least one real local-model semantic demo; fixtures must be labeled. Report measured overhead per stage and coverage counts.

### Gate 5 — submission

Package repository, reproducible local startup, policy, signature feed, automated suite, short demo recording if practical, and a maximum-ten-slide PDF. Acknowledge current proof/runtime boundaries. Freeze submission evidence at the deadline; no post-deadline changes to submitted material.

## What to cut if time runs short

Cut accounts beyond the three-account demo, multiple currencies, deposits/withdrawals, refunds, persistent agent memory, plug-in installation, advanced OAuth, multi-user SaaS, policy synthesis, and broad theorem search. Keep ledger commit safety, real hybrid controls, provider mediation, budgets, tests, and clear reporting. The brief scores those; it does not score an elaborate banking app.

## Local checks and reporting

No GitHub Actions unless the owner explicitly requests them. Build/test locally. Meaningful commands must return nonzero on failure. Record reproducible fixture inputs, seeds, environment, and stage timings. Use one script that performs production Lean build, axiom/status inspection, schemas, suite, differential vectors, race tests, and a smoke demo. Do not count the intentionally incomplete Aristotle request build as successful formal verification.

At every checkpoint report: implemented behavior; checked proof targets; tests run and failures; current trust boundary; next blocking work. Continue autonomously on authorized reversible implementation. Do not merge an unreviewed theorem set or claim completion based only on a green build that admits holes.

---

## This pack's current limits

No runtime or checked theorem is supplied as complete. The request files contain exact desired propositions but need typechecking and proofs in the selected workspace. The authoritative finite ledger is deliberately smaller than real-world banking. There is no claimed liveness, distributed-consensus, cryptographic, classifier-accuracy, or whole-stack theorem.

