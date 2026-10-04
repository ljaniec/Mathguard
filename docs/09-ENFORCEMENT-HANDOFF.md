# Enforcement implementation handoff and release acceptance

Mathguard's implemented product is the authenticated **gateway and interception SDK**, not the reference agent. The four deliverables are the component/architecture, schema-3 policy examples, interactive dashboard and automated security suite. Use [04-ENFORCEMENT-ENGINE.md](04-ENFORCEMENT-ENGINE.md) for the current contract and [17-JUDGE-QUICKSTART.md](17-JUDGE-QUICKSTART.md) for unattended judge startup. Older nested-policy/catalog, volatile-only and two-stage-chat proposals are historical.

## Current ownership map

| Layer | Source | Responsibility and boundary |
| --- | --- | --- |
| Deterministic facts/schema | `gateway/control.py`, `policies/`, `feeds/` | Bounded strict JSON and validated policy/feed; PII/secret/encoded/structured-context facts; inert artifact admission |
| Verified decision/state | `Mathguard/Control.lean`, `Mathguard/Worker.lean` and reviewed model modules | Compiled hard/hybrid restriction combination, ledger, global budgets and trusted-label flow rules |
| Runtime composition | `gateway/engine.py` | Role/principal construction, sessions, exact approvals/replay, reload, three-stage chat, reservations, quarantine and sanitized events |
| Durable adapter | `gateway/state.py` | Private single-node intent/result journal, exact worker replay, operation audit and fail-closed uncertain recovery |
| Local transport | `gateway/provider.py`, `gateway/server.py` | Loopback-only model endpoint, bounded process calls and ingress, framing/Host/Origin checks, sanitized errors |
| Interception integration | `gateway/sdk.py` | Application-to-model, agent-to-agent and agent-to-MCP callable mediation; filtered replies/results; trusted host callbacks |
| Reporting | `dashboard/` | Interactive outcomes, policy/feed versions, resource headroom, observations, quarantine/reload/storage health and sanitized exports |
| Judge operation | `scripts/judge.py`, `scripts/demo.sh`, `Makefile` | Private credentials/state, exact installed Ollama model preflight, simple startup and tests |

Do not implement a parallel Python ledger/gate, privileged frontend money path or silently permissive provider fallback. Changes to Lean model semantics need the formal owner and a fresh build/axiom report.

## Normal operation and release gate

1. Follow the quickstart to start the actual Ollama daemon with cloud disabled and download licensed local weights. Run `make setup MODEL=<exact-installed-ID>`, `make run`, then use `make credentials` in a private second terminal. No paid API/account/key is needed.
2. Run `make test`. Preserve exact source and worker digests in fresh evidence. Fixtures and protocol tests verify enforcement/transport under declared verdicts; they do not establish live classifier accuracy.
3. Rehearse the public HTTP workflow with `python3 scripts/rehearse-demo.py --output evidence/rehearsal.json`. It uses a temporary, explicitly labeled fixture instance, not the judge's durable live state.
4. Inspect dashboard operation and accessibility on desktop/mobile. Verify the new mark, clear control statuses, inert user-text rendering, credential handling and useful management/export outputs.
5. Run the live evaluator against development data and independently authored unseen data on an otherwise idle, capacity-planned live instance. Record engine/model/digest/license, valid semantic verdicts, attack/benign outcomes and control failures separately.
6. Verify the submission PDF/tutorial and registered member details. Use current checked evidence rather than hard-coded historical test totals or an assumed model result.

`make setup` preserves existing private edits/tokens/state. A deliberately different runtime directory creates a different demonstration environment; it does not recover the original state. Never delete a database to erase spent resources or avoid uncertain effects.

## Contracts to preserve

- **Hybrid controls:** the compiled hard denial survives a safe classifier verdict. Semantic block and review withhold output; owner approval cannot bypass them. `profile` controls actual classifier-failure behavior (strict deny, balanced review, permissive alert/pass), while provider quarantine prevents later model dispatch.
- **Three-stage chat:** `/v1/models/chat` performs input classification, local generation and output classification. Deterministic checks/redaction surround generation. A successful chat charges three provider reservations; the output stage can withhold the whole answer. Classifier calls are allowlisted/budgeted and do not recursively classify themselves.
- **Configured ceilings:** every provider call reserves a conservative four-resource bound through Lean and charges it in full, including failures. Observed token totals and elapsed times are reported separately. No usage-based refund or measured invoice is implied. Unknown usage is not permission to drop the configured charge.
- **Concurrency and capacity:** one engine lock serializes work; admission waits at most five seconds. HTTP admits at most eight active connections and bounds ingress bytes/time. Busy requests that never acquire the engine lock have no terminal engine audit event; do not claim one complete durable record for every TCP attempt.
- **Approvals:** ledger and generic irreversible-tool approvals bind the exact request, principal/session, relevant configuration and expiry. They cause no effect when issued. Recheck expiry after semantic work. Consume successful authority once; exact committed replay adds no debit/provider/tool charge. Sessions and outstanding approvals are invalidated on restart.
- **Policy reload:** strict schema 3 and monotonic epoch/feed versions; reject unknown/duplicate/invalid fields and unsafe reductions. Preserve counters and the last valid pair. Without a valid pair, execution is closed. An explicit increased limit is a reviewed policy change, not reset/refund.
- **Local serving:** accept loopback endpoints only; no redirects/ambient proxies or cloud model IDs. Judge preflight additionally verifies local native Ollama weight metadata/digest. Actual daemon cloud disabling is a deployment requirement; loopback alone is not an offline-inference proof.
- **Timeout and quarantine:** bounded adapter cleanup cannot prove upstream GPU/CPU cancellation. Retain charges, quarantine subsequent calls and require an explicit current operator confirmation after stopping/verifying upstream work. No silent retry or automatic recovery.
- **Persistence:** an owned single-node SQLite journal records intent before mutating worker IO, then response and operation audit atomically. Restore via the same worker with exact response matching, not a Python mirror. Unknown tails, corruption, changed worker identity or inconsistent journals close startup. Preserve files for verified-backup/operator investigation.
- **Recovery:** clean state restores ledger/global budgets, last-good controls, nonces and committed exact-replay receipts. Recorded outstanding reservations quarantine and are fully charged on explicit safe recovery. Session/history and outstanding approval invalidation is intentional. Durable state has hard capacity bounds and assumes trusted local file ownership; its hashes are not malicious-administrator rollback protection.
- **Sensitive/structured data:** inspection covers input/output and indirect history/tool content, including documented encoded/Unicode/split variants. Redaction may change a tool string's meaning; host callbacks must validate their own schemas and placeholder semantics. Never forward malformed sanitized JSON.
- **SDK effects:** arguments are admitted before a trusted callback; results/replies are admitted before release. A blocked result cannot undo an external callback effect. Full MCP/OAuth, sandboxing and exactly-once crash-atomic arbitrary tools are outside the implementation.
- **Artifacts:** only bounded pinned inert bytes/provenance/headers are admitted. No unsafe deserialization, remote code loading or claim of complete malware/model-behavior verification.
- **Reporting:** public logs are sanitized metadata; the private state journal may contain financial request/context records and must remain private. Export windows/pagination are explicit. Dashboard readiness, quarantine, provider mode, reload errors and storage mode must remain visible.

## Evidence and remaining acceptance

| Evidence area | Required interpretation |
| --- | --- |
| Lean build and axiom report | Statements proved for the compiled model under explicit assumptions; catalog records are not distinct end-to-end requirements |
| Security/runtime/transport tests | Checked enforcement, adversarial parsing/roles/resources, provider/SDK bounds and durable recovery scenarios |
| Public-route rehearsal | Reproducible fixture workflow; no claim of live semantic quality |
| Live local-model preflight | Real transport, exact local model identity and structured verdict compatibility; no general detector-accuracy claim |
| Development evaluation | Transparent tuned/development sample outcomes, false positives, semantic review and availability failures |
| Independent unseen evaluation | Separately authored/labeled provenance, no retuning on outcomes before reporting it as unseen |
| Browser/human rehearsal | Observed clarity and operation; no fabricated screenshot or claimed behavior |

Detection success, valid structured-classifier availability and hard-action safety are separate questions. A hostile proposer cannot override Lean ownership/funds/replay guards even when the classifier errs. A few literal matches or a small local model do not justify universal prompt-injection resistance.

## Formalization handoff

Read the current formal handoff and implementation before proposing theorems. Preserve existing target statements and do not expand a proved-model claim to authentication, parsing, clocks, provider IO or SQLite automatically. Prioritize exact runtime refinement; the durable intent/result/replay/uncertain-tail protocol; approval principal/session/configuration binding; bounded schema parsing; last-good reload preservation; and conservative/observed resource reconciliation.

Each Aristotle task should name the actual definitions and hypotheses, state the intended invariant, provide a counterexample or attack the theorem excludes, and specify compilation/axiom acceptance checks. Keep unproved work in the handoff rather than adding production `sorry`. Exact-once arbitrary SDK side effects require an external tool protocol and cannot be obtained from the current callback interface alone.

Future distributed quotas, per-session resource vectors, full MCP transport, generalized ownership catalogs and complete artifact provenance can extend the product after release. They are not substitutes for the four working deliverables or honest live-quality evidence.
