# Mathguard — project description and submission fields

Updated 4 October 2026 against the release merged in PR #6, source commit `2539ac4911157483fb574f8c8c2071f05d98d5e8`. Runtime evidence remains attached to its measured source/binary fingerprints. This page replaces the earlier 70-case, live-evaluation-pending description. The three question headings below are retained from the existing submission template; the additional fields are ready for use if the platform requests them. Platform-specific character limits and registered team details require the actual form.

## Project name

Mathguard

## Challenge / category

HackYeah 2026 — Goldman Sachs: AI Control Layer

## One-line description

Mathguard applies live policy to AI interactions using deterministic rules, a local semantic model and a compiled Lean decision kernel.

## What problem are you solving with the idea?

Applications using AI can expose sensitive data, invoke unauthorized tools, follow hostile instructions in retrieved content or other agents' messages, and consume resources without clear limits. Organizations need a shared enforcement point that checks these interactions before releasing content or authorizing effects. Developers also need editable policies and an audit trail that explains decisions without copying sensitive prompts into reports.

## What is your solution?

Mathguard is a working HTTP gateway and Python SDK placed between existing applications and their AI interactions. A policy file controls strictness, sensitive-data handling, model/tool allowlists, approvals and resource limits. Deterministic checks and a local Ollama classifier feed a compiled Lean kernel: a semantic allow cannot override a hard denial. The layer allows, redacts, withholds for review or blocks traffic. It inspects model input and output, tool arguments and results, agent messages and bounded artifact admissions. A dashboard shows decisions, resource headroom and sanitized audit exports. A synthetic account ledger demonstrates exact owner approval and safe retries for an irreversible tool.

## What's done so far and what is the goal of your project?

All four deliverables are implemented: the control layer with an architecture diagram, documented policy samples, an interactive dashboard and automated tests. The latest canonical check passed 189 runtime tests, 14 static tests, the pinned Lean build and a fresh 156-record axiom audit. Actual local Ollama/Qwen2.5 1.5B evidence includes eight development cases and ten operational checks covering chat, approval/retry, live policy edits and same-journal restart. The ten-slide PDF, editable PowerPoint and presenter tutorial are complete. Next priorities are independent unseen attack evaluation, human browser rehearsal and further formalization of the host/worker and persistence contracts. Existing model proofs and runtime tests have explicitly different scopes.

## Thirty-second pitch

AI applications need rules that a model cannot talk its way around. Mathguard puts one policy gateway in front of local models, tools and agent messages. Deterministic checks and a local classifier inspect traffic; a compiled Lean kernel ensures that a semantic allow cannot remove a hard denial. Developers can edit policies live. Operators can see blocked threats and resource headroom. Our ledger demo shows exact approval and retry without a second debit. The system runs locally and requires no paid inference API.

## Target users and use cases

| Field | Submission text |
| --- | --- |
| Target users | Developers integrating AI applications or agents; security teams defining guardrails; operators reviewing decisions and resource use. |
| Main use cases | Inspect prompts and generated replies; sanitize sensitive data; gate tool arguments/results and agent messages; limit model resources; require approval for configured irreversible actions. |
| Product form | Local HTTP gateway and Python SDK for integrated clients. Calls routed outside that integration remain outside its perimeter. |
| Demonstrator | Synthetic PLN account ledger with Alice, Bob and Merchant accounts. No bank connection or real payment service. |
| Distinguishing design | A compiled, formally specified restriction-combination kernel in the request path, paired with empirical deterministic/semantic detection and explicit runtime trust boundaries. |

## Technology and resources

| Field | Checked value |
| --- | --- |
| Enforcement core | Lean 4.28.0; pinned Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`; long-lived compiled worker. |
| Gateway / SDK | Python 3.10+ standard library; authenticated loopback HTTP routes and a callback-based Python SDK. |
| Dashboard | Repository HTML, CSS and JavaScript; same-origin authenticated requests; no external UI CDN. |
| Durable state | Owner-private, single-owner SQLite command journal; committed ledger/resource state and audit restore after restart. Sessions and outstanding approvals are invalidated. |
| Local inference | Tested Ollama 0.35.1 with `qwen2.5:1.5b-instruct`, Q4_K_M, approximately 986 MB. Actual daemon started with `OLLAMA_NO_CLOUD=1`. No model weights are bundled. |
| Model identity | Digest `65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b`; installed-model Apache-2.0 license verified in [model-record.json](../submission/model-record.json). |
| Configuration | `mathguard-policy-3` JSON; strict/balanced/permissive profiles; versioned data-only signatures. Invalid candidates keep the last valid configuration; no valid configuration means execution stays closed. |
| Test resources | Repository-authored synthetic prompts, detector/transport fixtures and actual compiled-worker tests. Node.js is needed for the dashboard DOM harness; these fixtures are not live-model accuracy evidence. |
| Development assistance | Codex/ChatGPT for implementation, documentation and visual refinement; Aristotle for Lean proof development. Accepted proof artifacts are independently rebuilt and audited. These are development tools, not live inference dependencies. |
| Licenses | Lean/Mathlib and tested Qwen weights: Apache-2.0; tested Ollama release: MIT. Exact sources/notices are in [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md). The project owner's distribution-license choice remains unrecorded. |

The current HTTP API is a custom control-layer interface. The SDK integrates trusted MCP/tool callbacks; it does not implement a full MCP transport/OAuth server or a drop-in OpenAI chat proxy.

## Deliverables and links

| Form field | Value / destination |
| --- | --- |
| Repository | https://github.com/ljaniec/Mathguard |
| Component and architecture | [Gateway and SDK](../gateway/) and the [README diagram](../README.md#architecture). |
| Policy example | [demo.json](../policies/demo.json), [strict.json](../policies/strict.json), [permissive.json](../policies/permissive.json), [field documentation](../policies/README.md). |
| Interactive demo | `http://127.0.0.1:8787` after local startup; this is a local URL, not a publicly hosted service. |
| Automated suite | `make test`; [tests](../tests/) and [integration receipt](../evidence/integration.json). |
| Presentation upload | [Mathguard-HackYeah-2026.pdf](../submission/Mathguard-HackYeah-2026.pdf), ten slides. |
| Editable presentation | [Mathguard-HackYeah-2026.pptx](../submission/Mathguard-HackYeah-2026.pptx). |
| Presenter tutorial | [Polish slide explanations and English scripts](18-PRESENTATION-TUTORIAL.md), demo sequence and judge questions. |
| Judge instructions | [Quickstart](17-JUDGE-QUICKSTART.md); [dashboard guide](16-DASHBOARD-GUIDE.md). |
| Formal assurance | [Release assurance](verification/RELEASE-ASSURANCE.md), [axiom report](verification/axioms.txt), [next Aristotle tasks](../aristotle/FINAL-HARDENING-HANDOFF.md). |

## How judges run it

Install Python 3.10+, GNU Make, Lean/elan and Ollama. For the complete dashboard test coverage, also install Node.js. Start the Ollama daemon with cloud disabled:

```sh
OLLAMA_NO_CLOUD=1 ollama serve
```

In another terminal inside the checkout:

```sh
ollama pull qwen2.5:1.5b-instruct
make setup MODEL=qwen2.5:1.5b-instruct
make run
```

Open `http://127.0.0.1:8787`, use `make credentials` in a private terminal, and connect the separate roles. Run `make test` for the canonical checks. First setup downloads dependencies/weights; operation can stay local after preparation. Preserve the runtime directory on subsequent starts.

## Evidence, performance and limitations

| Field | Accurate submission statement |
| --- | --- |
| Test status | [189 runtime tests](../evidence/integration.json), zero failures/errors/skips, collected `2026-10-04T02:40:39.907793+00:00`; canonical Lean/native/14-static checks also passed. |
| Formal scope | 156 axiom-catalog records, not 156 independent requirements. Proofs cover typed model properties and restriction composition; authentication, raw JSON/HTTP, provider IO and SQLite host composition remain runtime-tested. |
| Live evaluation | [Eight development cases](../evidence/live-development-evaluation.json) passed expected outcomes; [ten operational checks](../evidence/live-local-rehearsal.json) passed. The development corpus informed the prompt and is not held out. |
| Known detection gap | The classifier missed a support-note instruction to publish private contacts. In the [full gateway follow-up](../evidence/prelint-indirect-live.json), the proposer refused and that harmless refusal was released. A separately constructed harmful output was blocked. This does not close the input detection gap. |
| Response cap / latency | Sample cap: 128 output tokens for every stage; long replies may end at the cap. Allowed chat uses input classification, generation and output classification. One measured benign CPU case took about 4.26 seconds across provider stages; each stage has a 15-second deadline. |
| Budget capacity | Each allowed chat charges three conservative bounds. The fresh sample compute allowance permits 12 complete chats before other usage; creating a session or restarting does not reset global charges. [Calculation](../policies/README.md#budget-example). |
| Deployment boundary | Trusted single node and filesystem, serialized processing and global quotas. No distributed quota guarantee, upstream GPU-cancellation proof or exactly-once guarantee for arbitrary SDK callback effects. |
| Artifact boundary | Pinned byte/hash checks and a bounded inert safetensors/GGUF subset; no pickle execution. This is admission, not a safety proof for arbitrary weight loaders. |
| Human acceptance | Independent unseen evaluation and browser visual/download/operator rehearsal remain open. The PDF was rendered and checked separately. |

## Fields requiring organizer / team confirmation

| Field | Required source |
| --- | --- |
| Registered team name | Exact current HackTribe team record; project name does not establish the registered team name. |
| Registered members / team leader / contact | Actual roster and designated contact. GitHub contributors and account names do not establish competition registration. |
| Project distribution license | Explicit owner decision; third-party notices do not license the project itself. |
| Organizer cutoff / submission ID / acceptance | Current platform or organizer confirmation. The supplied rules and secondary schedule disagree; no acceptance or upload is claimed here. |
| Video or public hosted demo | No checked video/public deployment link is recorded. Use the supplied PDF and local demo unless the team provides one. |

## Challenge alignment

The supplied scoring tables agree on security resilience 30%, architecture/performance 20% and reporting 20%. They differ on tests versus implementability: 15/15 in the detailed brief and 20/10 in the rules. All four deliverables have repository links above. The exact primary PDF links/hashes, requirement mapping and unresolved cutoff are in [10-REQUIREMENTS-RECOVERY.md](10-REQUIREMENTS-RECOVERY.md) and [reference/SOURCE-NOTES.md](../reference/SOURCE-NOTES.md).
