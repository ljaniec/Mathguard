# Mathguard — general-control integration checkpoint

## Implemented and checked

- Fresh 156-record axiom catalog: 55 baseline, five refinement/snapshot, 43 Next (35 targets + eight supporting records), and 53 generic Control records; pinned Lean 4.28.0 / Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`.
- Compiled private JSONL worker executing the actual generic hard/hybrid gate, ledger/budget/flow functions and W1 typed decoder. The original baseline and imported production modules are unchanged. C1/P1 history/composition proofs remain separate model evidence.
- Shared interception API and SDK for prompts, tool calls/results, agent messages and model outputs; exact generic owner approvals; schema-3 live tools/thresholds/profiles. Strictness now controls actual compiled semantic fallback.
- Callable authenticated Python gateway; owner-bound approval; exact replay; strict parsing; live policy/feed reload with last-good retention; input/output pattern controls; local-model semantic/proposer adapter; conservative global resource accounting and session loop limits.
- Bounded inert artifact byte/hash/header checks; interactive dashboard; sanitized audit and management report; minimal reference agent client.
- Local gate passed: pinned proof/native checks, 14 audit/parser regressions and 70 actual-worker gateway/provider/SDK cases. Fresh evidence: [GENERAL-CONTROL-INTEGRATION.md](docs/verification/GENERAL-CONTROL-INTEGRATION.md). Dashboard exposes redactions/reviews and detector-plus-gate p95 alongside request latency.

## Open submission blockers and limitations

1. **Live local-model validation is not performed here.** Configure the exact installed model ID/endpoint; run the live evaluator and agent. The automated gateway suite uses labeled classifier fixtures; provider transport tests use a local HTTP fixture.
2. **Independent unseen prompt evaluation remains open.** The checked-in corpus is development data; no attack-resistance percentage is claimed.
3. **Browser visual/operator rehearsal remains open.** Static assets, JS syntax and HTTP serving are checked. Browser download returned truncated archives in this environment; no screenshot/render QA result is claimed.
4. **Final <=10-slide PDF and HackTribe entry remain open.** Product handoff contains the evidence-based slide plan. Confirm cutoff/pitch duration and protect the earlier reported 11:00 deadline with a 09:30 Warsaw submission target.
5. Actual model/weights license and version must be recorded; no weights are bundled.

## Deployment boundary

Single serialized volatile owner. SDK mediation is implemented; no durable audit/store, distributed budget, full MCP transport/OAuth, or full artifact/memory security claim. Resource counters charge configured conservative bounds; they are not measured bills. Provider timeout quarantines further work but does not prove upstream GPU cancellation. The new worker adapter/composition/auth/provider/labeling path is integration-tested, not a new full-stack formal theorem. Pattern/classifier coverage remains finite.

## Team assignments

- Product/agent/dashboard/submission: [copy-paste assignment](docs/08-AGENT-PRODUCT-HANDOFF.md).
- Enforcement/model/evaluation: [copy-paste assignment](docs/09-ENFORCEMENT-HANDOFF.md).
- Shared implementation contract: [API and runtime semantics](docs/07-TEAM-INTEGRATION-CONTRACT.md).
- Priority and source traceability: [requirements recovery](docs/10-REQUIREMENTS-RECOVERY.md).

Use PRs and Prelint; no direct main writes or GitHub Actions. Keep runtime evidence separate from model theorems. The earlier 35 C1/P1/W1 targets are now imported and freshly checked; do not duplicate that proof campaign. Current architecture/contract: [13-GENERAL-CONTROL-LAYER.md](docs/13-GENERAL-CONTROL-LAYER.md).
