# Mathguard

**LLMs propose actions. Mathguard checks which actions may change the ledger.**

Bootstrapping and formal-model pack for HackYeah 2026, Goldman Sachs **AI Control Layer**. The reference application is a simulated personal-account ledger; the assessed product is the AI control layer around agents, model calls, and ledger/MCP tools.

## Start here

1. [Updated submission description](docs/01-PRODUCT-AND-CHALLENGE.md).
2. [Codex bootstrap for Astra / Sol 6.1](docs/02-CODEX-BOOTSTRAP.md).
3. [Agent, product, and visualization specification](docs/03-AGENT-PRODUCT-VISUALIZATION.md).
4. [Enforcement-engine specification](docs/04-ENFORCEMENT-ENGINE.md).
5. [Detailed mathematical model and assurance boundaries](docs/05-FORMAL-MODEL.md).
6. [Aristotle instructions and theorem acceptance criteria](aristotle/README.md).
7. [Executable model definitions](aristotle/Spec.lean), [ledger proof request](aristotle/LedgerRequest.lean), [budget proof request](aristotle/BudgetRequest.lean), [flow proof request](aristotle/FlowRequest.lean).
8. [Validation matrix, demo, and delivery gates](docs/06-VALIDATION-AND-DEMO.md).

## Status — 2026-10-03

This repository contains **specifications and proof requests**, not a completed control layer or a verified release. No Lean toolchain is available in the authoring environment, so the supplied Lean files have **not been compiled**. `sorry` occurs deliberately in the three Aristotle request files as proof obligations; it is prohibited in release modules. Definitions, theorem statements, and runtime integration must pass the gates in the bootstrap before any verified-product claim is made.

The three contributors have separate hackathon projects. Mathguard is Łukasz Janiec's project. The workstream documents describe roles for coding agents or optional helpers; they do not assume Przemek or Cezary is available to implement Mathguard.

The attached official brief requires a functional layer, centralized configurable policy, deterministic and semantic controls, budget governance, historical attack mitigation, reporting, and an executable positive/negative suite. Formal methods strengthen those deliverables; a standalone banking proof does not replace them.

## Reference material

The audit in [reference/SOURCE-NOTES.md](reference/SOURCE-NOTES.md) comes from reading both uploaded Goldman PDFs. The spelling of `CRIETRIA` follows the source filename. The detailed criteria and rules disagree on the last two weights; keep that discrepancy visible until the mentors resolve it. The full task archive is not redistributed here.

No GitHub Actions workflows are introduced. Use reproducible local checks.
