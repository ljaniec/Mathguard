# Codex bootstrap — Mathguard challenge delivery

Copy this assignment into Astra/Sol Codex on `https://github.com/ljaniec/Mathguard`.
Use the highest reasoning effort for model semantics and security-boundary review.

You are completing **Mathguard**, Łukasz Janiec's HackYeah 2026 Goldman Sachs AI Control Layer. Keep the LLM-plus-Lean design: LLMs propose/classify; deterministic functions control effects. The simulated ledger is the reference application. The deliverable is a hybrid control layer with configurable policies, dashboard and executable tests.

Start by reading current branches/PRs, `STATUS.md`, `docs/10-REQUIREMENTS-RECOVERY.md` and `docs/07-TEAM-INTEGRATION-CONTRACT.md`. The challenge-recovery implementation already supplies a Python gateway, private compiled Lean worker, local-model adapter, dashboard, policy/signature examples and integration tests. Work from its latest reviewed commit; preserve other agents' changes. Do not redo the 55 original proofs, replace the pinned toolchain, implement a Python banking mirror, or assume old preparatory notes describe current code.

Own one workstream per PR. Product/agent work follows `docs/08-AGENT-PRODUCT-HANDOFF.md`; engine work follows `docs/09-ENFORCEMENT-HANDOFF.md`. Coordinate contract changes before editing both sides. Use PRs, inspect Prelint, and run relevant local gates; do not add GitHub Actions.

Immediate goal: configure the actual available local model, prove the complete live positive/negative path works by observation, collect honest evaluation evidence, rehearse editable policy/feed controls and reporting, and finish the <=10-slide submission PDF. No model weights or cloud subscription are bundled. Preserve the distinction between classifier fixtures, local HTTP protocol fixtures, live model observations, kernel microbenchmarks, end-to-end measurements, and checked mathematical statements.

Run `bash scripts/check-local.sh` on the pinned Lean 4.28.0 / Mathlib workspace. Its suite includes the actual worker; fixture verdicts test enforcement, not model accuracy. Run `scripts/evaluate-live.py` separately with exact model ID and a labeled development corpus; obtain a genuinely independent unseen corpus from a teammate or mentor. Never count outages or budget exhaustion as successful attack detection.

The worker executes the reviewed pure ledger/budget/flow functions. The new adapter, configuration interpretation, authentication, labels, provider contract, composed operation and IO behavior are tested, not fully proved. The deployment is serialized and volatile; there is no durable crash recovery or distributed allowance service. Do not launch multiple independent owners and claim a global budget. No semantic verdict or human approval can override an invalid hard financial precondition.

Existing theorem-request extensions live on the earlier planning/integration branch. Inspect them before adding Aristotle work. If further formalization is useful before submission, focus narrowly on the composed function actually executed by the worker and preserve the original definitions. Do not increase proof counts for uncompiled requests.

Use the earlier reported deadline operationally: target submission by **09:30 Europe/Warsaw on 4 October**, protecting the compendium's reported 11:00 cutoff while confirming with organizers. The written rules say 23:00; the authenticated schedule could not be independently checked. Finish the runnable deliverables and submission buffer before optional durable storage, generalized finance, full MCP transport, or more elaborate visuals.

At each checkpoint record implemented behavior, actual test/proof results, live model evidence, unresolved limitations and next concrete task. Continue authorized implementation without repeatedly requesting permission; do not merge unreviewed changes or submit/publish external materials without the owner's instruction.
