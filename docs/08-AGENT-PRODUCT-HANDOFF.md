# Copy-paste assignment: agent, product, dashboard and submission

You are implementing the agent/product part of **Mathguard**, repository `https://github.com/ljaniec/Mathguard`, for HackYeah 2026 Goldman Sachs AI Control Layer. Use the newest reviewed challenge-recovery branch/PR and inspect current commits before editing. Use PRs and read Prelint; do not push directly to main. Own `agent/`, `dashboard/`, presentation/demo assets and their tests. Coordinate shared API changes with the enforcement owner.

Read `docs/10-REQUIREMENTS-RECOVERY.md`, `docs/07-TEAM-INTEGRATION-CONTRACT.md`, `STATUS.md`, then `docs/03-AGENT-PRODUCT-VISUALIZATION.md`. The current repository already has a real compiled Lean worker, Python gateway, minimal dashboard and tests. Extend them; do not rebuild a second bank backend or duplicate the 55 baseline proofs.

## Product positioning and required deliverables

Mathguard is a hybrid control layer for AI model/tool interactions. The simulated personal-account ledger makes unauthorized actions and formal invariants concrete. The four explicit deliverables are working mediation, documented policy configuration, an interactive dashboard, and executable tests. Reporting is 20% in both scoring tables. Additional ledger visual polish cannot substitute for control-layer evidence.

## Priority P0: finish the judge experience

1. Run `bash scripts/demo.sh`; configure exact local model IDs and endpoint with the engine owner. Use separate operator, agent, and owner credentials. Never embed them in frontend source, browser storage, URLs, recordings, or exported logs.
2. Exercise a live harmless prompt, semantic injection attempt, deterministic secret redaction, valid transfer, missing approval, bound approval, exact retry, policy change, budget stop and audit export. Display `live` versus `fixture` visibly. Unknown model output is inert text. A model choosing not to attack is not proof that an attack was blocked.
3. Keep the current custom API contract. `agent/run.py` is a minimal one-proposal reference client: user instruction -> mediated proposer -> exact tool proposal -> enforced action. It has no owner credential or direct worker/provider access. Add a visible agent flow only through these same routes.
4. Dashboard cards should answer: What was stopped? Why? What did we allow? What resources remain? Which policy/feed is active? What is actually proved? Which checks are merely tested? Show model-call stage latency separately from total request latency and pure-kernel microbenchmarks.
5. Improve approval UX: display the canonical source/destination/amount/request ID/revision/epoch before issuing approval; require an explicit owner action. Show issuance separately from execution. Invalid/expired/stale requests do not become approval prompts. Exact retry cannot show a second payment.
6. Add a concise management report view/download: decision counts, major reasons, resource-accounting units, current configuration errors/quarantine, time window, dropped audit records, mode and evidence limitations. No fabricated risk percentage or “fully secure” badge.
7. Maintain the completed ten-slide submission PDF, editable deck and presenter tutorial against checked evidence. Use the actual registered title/team/member details once confirmed; do not infer them from GitHub contributors. The current artifacts are in `submission/`; presentation delivery does not establish platform upload or acceptance.

## Ten-slide plan

| Slide | Content | Required evidence |
|---|---|---|
| 1 | AI agents need controlled access to tools/data/resources | Three concrete failure examples, product one-liner |
| 2 | Control-layer architecture and integration | Diagram showing actual gateway/worker/provider boundaries |
| 3 | Hybrid defense and deterministic formal core | Real guard verdict; exact Lean guarantees and assumptions |
| 4 | Live centralized policies and feeds | Screenshot of activation and invalid-change retention |
| 5 | Resource/loop governance | Dispatch blocked before budget overrun; local tokens/time even at zero price |
| 6 | Financial tool and owner approval | Allowed action, bound approval, replay without duplicate debit |
| 7 | Historical/indirect attacks and artifact admission | Inert malicious fixtures and actual byte/hash checks; finite coverage stated |
| 8 | Automated tests and live adversarial evaluation | Counts, per-category outcomes/false positives/errors, exact model and SHA |
| 9 | Dashboard, management summary, sanitized export | Useful screens and sample metadata, no raw secrets |
| 10 | Setup, scaling boundary, licenses, next step | Single-owner volatile deployment; reproducible commands and limitations |

## Rehearsal, early deadline and claim discipline

Plan submission by **09:30 Europe/Warsaw on 4 October** to protect the earlier reported 11:00 schedule cutoff; confirm this with the organizer. The rules PDF's 23:00 conflicts with the secondary schedule report. Do not wait for that dispute to resolve to prepare materials. Prepare a 2-minute demo and a shorter 60-second version; actual finalist pitch duration is unconfirmed.

Sequence: normal request -> indirect injection/secret -> ledger action/approval/retry -> policy edit -> budget stop -> tests/export. Keep an offline fixture rehearsal available, clearly labeled, plus the real-model evidence. Avoid a staged “unguarded agent definitely leaks” claim unless that actual run was observed. A deterministic attack client against the same gateway is valid enforcement evidence.

## Acceptance checks and open work

- Screenshot test desktop and mobile; no console errors or clipped controls.
- Render every untrusted string using inert text, never HTML. Check a malicious HTML-looking prompt in the result/audit view.
- Credential roles enforced server-side; UI hiding is not access control.
- UI uses only authoritative receipts; policy reload errors and provider quarantine are conspicuous.
- Attach actual local-model smoke/evaluation report; fixture tests are not model-accuracy results.
- Record exact build/source/model versions and completed tests. Ensure the final PDF opens, contains <=10 slides and uses working judge-accessible links.
- Keep individual proposal/test prompts out of management exports unless a reviewed sanitization rule explicitly allows them.

P1 after P0: richer timeline, error recovery without silently resetting the ledger, recorded short demo, independent human-authored unseen test corpus. P2: persistent accounts, multi-user product, advanced visual effects. Do not spend the submission buffer on these.
