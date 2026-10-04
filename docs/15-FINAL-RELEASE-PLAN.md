# Final release plan

The release is an AI control layer. Applications and agents call it before model delivery, MCP/tool execution, agent messages, artifact admission and content release. The reference agent and account ledger are demonstration clients. The kernel remains compiled Lean code in the live request path.

The target is a strong, usable single-node release with explicit evidence. The scope covers all four assessed deliverables and the startup/presentation workflow. It does not promise distributed quotas or universal attack detection.

## Assessment priorities

| Criterion | Rules weights | Details weights | Release evidence |
| --- | ---: | ---: | --- |
| Security resilience | 30% | 30% | Layered controls, adversarial boundary tests, fail-closed transitions |
| Architecture and performance | 20% | 20% | Shared interception path, bounded work, local provider deadlines, measured latency |
| Reporting | 20% | 20% | Interactive dashboard, current posture, sanitized audit and management export |
| Automated tests | 20% | 15% | One command for positive, block, modify, budget and exploit tests |
| Practical implementation | 10% | 15% | Judge startup, preflight, local models, reproducible configuration and recovery |

The two official sources disagree on the final two weights. Both remain recorded. The release prioritizes the shared 70% without omitting tests or practical setup. The first-stage 50% threshold is not a reason to accept a missing deliverable.

## Workstreams and ownership

| Workstream | Primary files | Acceptance |
| --- | --- | --- |
| Runtime hardening | `gateway/engine.py`, persistence module, runtime tests | Atomic state transitions, bounded resources/session state, safe approval/replay/reload behavior and recovery |
| Deterministic controls | `gateway/control.py`, detector tests | Strict schema, secrets/PII, encoded/Unicode/indirect inputs, inert artifacts and data-only signature feed |
| HTTP/provider/SDK boundaries | `gateway/server.py`, `provider.py`, `sdk.py`, boundary tests | Role isolation, bounded body/response sizes, loopback local models, deadlines, sanitized errors and shared mediation |
| Dashboard/reporting | `dashboard/`, dashboard tests | Clear interactive controls, accurate posture/resource units, safe exports and observable invalid-policy state |
| Judge operations | README, Makefile, launcher/preflight/docs and sample policy guidance | Simple copy-paste startup, explicit local model selection, useful failures, one test command |
| Formal assurance and independent review | Lean inspection, assurance matrix and Aristotle handoff | Exact theorem/runtime mapping, checked proof boundary, prioritized concrete proof tasks, independent final review |
| Integration and presentation | Release plan/evidence, deck, speaker tutorial and identity | All workstreams integrated, tests/rehearsal complete, concise slides and a comprehensible spoken story |

Each agent owns its files. Shared contract changes require coordination before edits. Agents report findings, test evidence and limitations. Integration owns final release claims and publication. No agent merges or publishes independently.

## Security acceptance checklist

1. **Interception:** prompt/model, tool call/result, agent message, artifact and release paths use the shared gate. The SDK documents trusted callbacks and shows application-to-agent, agent-to-agent and agent-to-MCP examples. No new agent framework is the assessed product.
2. **Hybrid defense:** deterministic denial cannot be relaxed by a semantic allow. Semantic verdict parsing accepts only the documented bounded schema. Strict/balanced/permissive failure modes remain explicit. Classifier prompts separate policy instructions from untrusted content.
3. **Authentication/access:** roles cannot use each other's endpoints. Sessions and approvals bind the principal. Credentials never reach the model, audit payloads or UI persistence. Requests have size, rate/work and timeout bounds.
4. **Policy/feed:** reads are bounded and strict. Reject unknown/duplicate/type-confused fields and invalid ranges. Activate validated candidates atomically. Invalid edits retain the last valid version. With no valid policy, deny execution. Policy changes preserve financial/resource state and invalidate stale approval context. File edits become observable during evaluation.
5. **Sensitive content:** inspect both ingress and egress and indirect history/tool content. Cover ordinary, encoded and Unicode variants with allowed/blocked/redacted cases. Preserve structured types when redacting. Refuse undecidable or malformed structured content where required by policy.
6. **Budget/time/loops:** reserve conservative bounds before dispatch. Enforce global/session caps, call count, token bounds, compute/deadline bounds and repetition limits. Record configured reservation and observed provider usage separately. Do not describe local compute counters as commercial bills. Timeouts retain charges and require explicit safe recovery.
7. **Approvals/replay:** approval issuance itself cannot execute an effect. Bind owner/session/content/policy/feed, expiry and single consumption. Retries do not repeat a committed effect or charge. Generic SDK callbacks have an explicit crash/side-effect boundary.
8. **Artifacts/signatures:** verify repository/hash/format/byte/header bounds without deserialization or code execution. Deny pickle/executable artifacts and unsafe archive/path inputs. Feed signatures are data, have provenance/version and cannot evaluate code. Historical examples remain labeled as finite coverage.
9. **State/audit:** persistent state must be atomic and authenticated by deployment ownership, bounded and sanitized. Corruption or uncertain recovery blocks execution. Audit history is append-only within the selected store and export pagination is bounded. A persistence feature is not accepted merely because SQLite exists.
10. **Concurrency:** no interleaving can overspend or double-consume an approval. Worker failures/malformed replies fail closed. A provider timeout cannot be interpreted as proof that remote compute stopped.
11. **Reporting:** show outcome counts, policy/feed versions, strictness, provider mode, health/quarantine, latency, reserved/observed resources, budget headroom and reload errors. Management language explains the limits. Logs contain metadata, not raw sensitive interaction content.
12. **Local models:** no paid/API-key provider dependency. Reject unapproved remote endpoints. Preflight checks the installed model ID and local service. Fixture mode is visibly identified and cannot generate a live-quality claim.

## Deliverable acceptance

| Deliverable | Required contents | Verification |
| --- | --- | --- |
| Control component | Working gateway/SDK and simple architecture diagram | Real compiled worker and public HTTP/SDK rehearsal |
| Policy | Documented sensitivity, allowlists, profiles, budgets and invalid-edit behavior | Valid/invalid reload, monotone hard restrictions and state-preservation cases |
| Dashboard | Interactive prompt/reload/approval/reporting flow, posture and costs/resources | DOM/browser review where available, API serving and reporting regression checks |
| Tests | Allowed, blocked and modified traffic, budgets, encoded/indirect attacks and historical artifact mitigations | Canonical local test command with source-linked evidence |

## Judge workflow

The README begins with the product description and a short startup recipe. The launcher checks Python, the pinned Lean worker and a local serving engine/model. It creates a private runtime policy with the selected exact model ID, offers a stable dashboard URL and gives actionable failures. The test workflow requires no paid service. The live demo requires an installed local model and never silently substitutes fixtures. A clean-start smoke test, policy edit, invalid edit, redaction, semantic verdict, blocked tool, approval/retry, budget stop and export form the rehearsal.

Startup and persistent recovery must be possible without a developer interpreting stack traces. Tokens retain separate roles. Recovery commands state exactly what is restored, preserved or reset. Documentation includes the normal path first and deeper setup only when needed.

## Presentation and speaker tutorial

Use at most ten slides with one idea each. Prefer a diagram, short example or a single evidence result over dense paragraphs. Move the technical detail and proof names into notes and the tutorial. Suggested sequence: product/problem, interception architecture, hybrid gate, live policy, data/attack controls, resource/approval protection, dashboard demonstration, evidence and limits, judge startup, closing. Adjust this sequence to final implementation evidence.

The tutorial gives the meaning of every slide in plain language, a short script, what to point at, demo actions, expected outcome, transition and likely judge questions. Provide Polish explanations with English presentation copy where useful to the presenter. Preserve the more familiar original identity direction rather than forcing the recently generated G mark.

## Formal verification handoff

Inspect current Lean 4.28.0 definitions and the 156-record audit before proposing new theorems. Preserve original target statements and do not claim host parsing, authentication, provider behavior or crash safety are already proved. Prepare prioritized Aristotle tasks for exact runtime refinement, atomic persistent commit/replay, approval binding, bounded wire/schema parsing, reload/state preservation and observation/resource reconciliation as justified by the implemented contracts. Each task names concrete definitions, invariants, hypotheses, target statements, counterexamples and acceptance checks. Unproved work belongs in the handoff, not as `sorry` in production.

## Integration and release gates

1. Inspect agents' patches and resolve shared contracts. Run targeted security tests while integrating.
2. Run the complete canonical local gate against the actual worker. Regenerate axiom evidence only if Lean changes require it.
3. Run isolated HTTP rehearsal, provider adversarial fixtures and concurrency/restart/recovery checks where implemented.
4. Run real local-model inference/evaluation if installation/network/hardware permit. Record the exact engine/model/version/license and results. If blocked, record the attempted setup and exact blocker, keeping the live acceptance step open.
5. Measure repeatable gateway latency with provider/model timing reported separately. No invented performance or accuracy percentages.
6. Inspect the dashboard and every exported slide. Verify startup instructions against a clean temporary runtime directory.
7. Refresh requirement mapping, current status, assurance boundaries and source-linked evidence. Independent review checks the release against this checklist.
8. Publish reviewed source and deliverables on a fresh hardening PR branch after the earlier integration PR merged. Keep main unmodified and preserve open external submission/registration decisions.

## Remaining external decisions

The team must confirm the earlier deadline discrepancy, registered member list, HackTribe entry and final submission acceptance. Actual installed weights need a recorded license/version. These are not solved by passing fixture tests or rendering the deck. The prepared release will clearly distinguish completed engineering evidence from external or live acceptance still needed.

## Release checkpoint

All engineering workstreams are implemented. The final canonical gate passed 189 runtime cases, 14 static regressions and the pinned Lean build/156-record audit, including the [Prelint follow-up](verification/PRELINT-FOLLOWUP.md). The fixture HTTP rehearsal passed 16 cases, and the actual local CPU/ledger/approval/restart rehearsal passed 10 cases. The selected 1.5B model with strict JSON schema and 128-token output cap passed all eight development-corpus outcomes, with no control errors. Source fingerprints match. Nine raw classifier probes (five selected development inputs and four supplementary inputs) returned valid verdicts; eight matched their expected labels, with a support-note/public-paste instruction falsely allowed. A later live gateway probe still allowed that input, but the proposer refused; a separate constructed harmful output was blocked. Failed earlier model, timeout and JSON-format runs remain preserved. None of these corpora is independently held out.

The ten-slide PDF was rendered and checked; its visible copy is 260 words. The presenter tutorial and seven Aristotle proof campaigns are complete as documents; the proposed campaigns are not new checked proofs. Browser visual/download acceptance remains blocked by the remote review browser. Independent unseen detector evaluation, human browser rehearsal and external submission decisions remain open.
