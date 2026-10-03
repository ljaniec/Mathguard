# Mathguard — challenge-recovery checkpoint

## Implemented and checked

- 55 baseline theorem targets plus five reservation/snapshot equality targets, pinned Lean 4.28.0 and Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`.
- Compiled private JSONL worker executing the actual ledger, budget and flow functions. The reference definitions and theorem statements are unchanged.
- Callable authenticated Python gateway; owner-bound approval; exact replay; strict parsing; live policy/feed reload with last-good retention; input/output pattern controls; local-model semantic/proposer adapter; conservative global resource accounting and session loop limits.
- Bounded inert artifact byte/hash/header checks; interactive dashboard; sanitized audit and management report; minimal reference agent client.
- Local gate passed at this checkpoint: pinned proof/native checks, 14 audit/parser regressions, and gateway/provider integration cases. See `docs/verification/CHALLENGE-RECOVERY.md` for exact current evidence.

## Open submission blockers and limitations

1. **Live local-model validation is not performed here.** Configure the exact installed model ID/endpoint; run the live evaluator and agent. The automated gateway suite uses labeled classifier fixtures; provider transport tests use a local HTTP fixture.
2. **Independent unseen prompt evaluation remains open.** The checked-in corpus is development data; no attack-resistance percentage is claimed.
3. **Browser visual/operator rehearsal remains open.** Static assets, JS syntax and HTTP serving are checked. Browser installation failed in this environment; no screenshot/render QA result is claimed.
4. **Final <=10-slide PDF and HackTribe entry remain open.** Product handoff contains the evidence-based slide plan. Confirm cutoff/pitch duration and protect the earlier reported 11:00 deadline with a 09:30 Warsaw submission target.
5. Actual model/weights license and version must be recorded; no weights are bundled.

## Deployment boundary

Single serialized volatile owner. No durable audit/store, distributed budget, generic MCP transport, or full artifact/memory security claim. Resource counters charge configured conservative bounds; they are not measured bills. Provider timeout quarantines further work but does not prove upstream GPU cancellation. The new worker adapter/composition/auth/provider/labeling path is integration-tested, not a new full-stack formal theorem. Pattern/classifier coverage remains finite.

## Team assignments

- Product/agent/dashboard/submission: [copy-paste assignment](docs/08-AGENT-PRODUCT-HANDOFF.md).
- Enforcement/model/evaluation: [copy-paste assignment](docs/09-ENFORCEMENT-HANDOFF.md).
- Shared implementation contract: [API and runtime semantics](docs/07-TEAM-INTEGRATION-CONTRACT.md).
- Priority and source traceability: [requirements recovery](docs/10-REQUIREMENTS-RECOVERY.md).

Use PRs and Prelint; no direct main writes or GitHub Actions. Keep independent runtime evidence separate from the 55+5 proof evidence. Earlier 35-target requests remain requests unless a later reviewed checked artifact establishes otherwise; inspect the planning/integration branch before duplicating work.
