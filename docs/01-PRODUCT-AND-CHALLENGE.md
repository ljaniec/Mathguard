# Mathguard — product definition and challenge alignment

## Replacement text for the submission website

### What problem are you solving with the idea?

AI agents can expose sensitive data, misuse tools, send unsafe instructions between agents, and consume uncontrolled model/API resources. Organizations need a control layer that checks actions before execution and provides evidence explaining why each action was allowed or blocked.

### What is your solution?

Mathguard is a hybrid AI control layer for agents, LLMs, and MCP/API tools. A compiled generic Lean 4 kernel combines deterministic controls with local AI verdicts before releasing prompts, model calls, tool interactions, agent messages and artifacts. Central policy files govern strictness, thresholds, allowlists, approvals and resource limits. The ledger adapter adds verified authorization, replay protection and financial invariants. A semantic AI guard detects suspicious instructions and can restrict actions without overriding hard safety checks. A dashboard displays decisions, ledger changes, budgets, and verification evidence.

### What's done so far and what is the goal of your project?

We have rebuilt a 156-record axiom catalog (55 baseline, 5 refinements, 43 Next and 53 Control) and connected the generic kernel to the running gateway. The shared interception API and SDK extend coverage to tool results and agent messages, with exact approvals and live policy/feed updates. The local automated gate checks native proofs/regressions, 14 static-audit cases and 70 gateway/provider/SDK cases. Our proof of concept uses a simulated personal-account ledger to make action safety visible. Live local-model quality evaluation and final submission packaging remain in progress; fixture tests are reported separately from live-model evidence.

**Status editing rule:** replace the first sentence with actual checked accomplishments as they become available. Do not say the gateway or proofs already work merely because this pack exists.

### One-line pitch

**Mathguard controls AI interactions with configurable guardrails and a compiled, formally specified decision kernel.**

### Thirty-second pitch

An AI assistant should not get to move money simply because it generated a plausible tool call. Mathguard sits between the assistant and its models and tools. It checks authority, approval, ledger consistency, replay attempts, sensitive-data flows, and budgets before execution. Lean 4 supplies machine-checked proofs for the exact state transitions; a semantic guard adds contextual detection. Our simulated bank account makes the result visible: legitimate transfers work, hostile proposals fail, and every decision comes with an audit trace.

## Product scope

- **Control-layer product:** gateway plus policy catalog, enforcement core, model/tool adapters, semantic guard, audit stream, dashboard, test runner.
- **Reference application:** simulated closed ledger in one currency, with seeded Alice, Bob, and Merchant accounts. No connection to real banking systems.
- **Agent:** untrusted proposal generator. The LLM is neither a source of identity nor a proof checker.
- **Formal artifact:** reviewed definitions, preservation theorems, trace theorems, witnesses, and an explicit deployment contract.
- **Optional development assistant:** LLM drafts Lean specifications/proofs offline; only reviewed and checked artifacts become part of a release. This is separate from the live financial agent.

The main user is a developer integrating an agent. The operator reviews security events and changes policy. The account owner approves a specific transfer through a separate authenticated UI. The security team exports sanitized evidence.

## Why a ledger is a good demonstrator

A ledger has precise properties: money must not be created by a transfer; an account cannot spend more than its balance; duplicate delivery cannot debit twice; the person who controls the account must authorize debits; approval of one amount must not authorize a different amount. Those properties can be stated and checked independently of the LLM's wording. A live ledger also exposes the gap between text classification and action enforcement.

Use the phrase **formally verified model and transition core** only after the corresponding gates pass. Do not claim that arbitrary banks, cryptography, all prompt injections, all software, or the whole deployed stack are formally verified.

## Official requirement mapping

| Brief requirement | Mathguard implementation | Evidence for judges |
|---|---|---|
| Functional gateway/proxy/middleware/SDK | Gateway plus SDK mediates model, tool/result and agent-message boundaries; ledger mutation stays private | Run benign and adversarial requests through public gateway |
| Centralized configurable policy | Versioned catalog with capabilities, account ownership, model allowlist, thresholds, budgets, destinations, signatures | Edit catalog, activate new epoch, rerun a scenario |
| Deterministic controls | Typed request checks, authorization, ledger preconditions, approval, replay, secret patterns, output gating | Decision reasons and positive/negative tests |
| Semantic AI controls | Local/OpenAI-compatible model produces bounded structured suspicion assessment | Real semantic call, model identity, time and tokens, timeout test |
| External and local model budgets | Reserve before provider calls; settle bounded usage; tool-call and local wall-time limits | Boundary and concurrent-reservation tests; budget display |
| Historical attack mitigation | Reloadable, data-only signatures with provenance and version; examples for instruction injection, dangerous deserialization, model-loader configurations | Modify feed, demonstrate new match; no exploit code executed |
| Security reporting | Sanitized event trace, counters, resources, reason codes, export | Dashboard and JSONL export |
| Executable self-tests | One local command; integration, race, model-reference, policy-change, and red-team tests | Judge can execute tests without an API subscription |
| Performance and scalability | Measured stage latency, concurrency bounds, serialized commit scope, timeout behavior | Exported measured p50/p95 and environment, no invented numbers |

## Weights and dates from the uploaded PDFs

| Criterion | Detailed criteria PDF | Rules PDF |
|---|---:|---:|
| Robustness / guardrails | 30% | 30% |
| Architecture / performance | 20% | 20% |
| Security reporting | 20% | 20% |
| Self-testing | 15% | 20% |
| Implementability / scalability | 15% | 10% |

Ask the mentor which final weighting applies. Both versions make a strong test suite and useful reporting essential.

The written rules give 23:00 on 3–4 October; the attached secondary schedule review reports an earlier 11:00 finish on 4 October. Plan to submit by **09:30 Europe/Warsaw on 4 October**, while confirming the actual cutoff and pitch duration with organizers. This conservative target is not a verified correction of the source. See the fresh [source audit and delivery matrix](10-REQUIREMENTS-RECOVERY.md).

## Priorities for a single primary developer

1. Run the existing gateway with the actual local model and record live positive/negative evidence.
2. Rehearse policy/feed changes, approvals/replay, resource exhaustion, and sanitized exports.
3. Measure model quality and full-request/stage latency; keep fixture/native benchmarks separate.
4. Complete the maximum-ten-slide PDF, source/model/license inventory, and accessible submission links.
5. Preserve the checked formal core; extend proofs only where a deployment-critical semantic gap requires it.

Do not make the demo wait on generalized finance, blockchain consensus, full OAuth deployment, arbitrary plugins, full theorem synthesis, or a large React product. An in-process control layer with a small UI satisfies the architectural form allowed by the brief if it really mediates the calls.

## Sources

- Primary task files: `CRIETRIA AI Control Layer.pdf` and `RULES AI Control Layer.pdf` in the uploaded Goldman directory; audit in `reference/SOURCE-NOTES.md`.
- Event page: https://hackyeah.pl/tasks-prizes
- Lean proof validation: https://lean-lang.org/doc/reference/latest/ValidatingProofs/
- OWASP prompt injection: https://genai.owasp.org/llmrisk/llm01-prompt-injection/
- MCP security guidance: https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices

Retrieved/read 3 October 2026. External references inform the threat model; the uploaded Goldman brief controls this project specification.
