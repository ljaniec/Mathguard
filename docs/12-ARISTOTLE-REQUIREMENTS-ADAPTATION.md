> **Imported Aristotle proposal, run `ee5d328d-e8bc-4314-adc1-393b7ff9b6b7`.** This is the archive's design analysis, preserved for provenance. It predates the runnable gateway already merged in PR #4. Its DESIGN/MEASURED wording is not current runtime evidence; no holdout result exists here. The archive's old filename `07-REQUIREMENTS-ADAPTATION.md` has been renumbered to preserve the existing API contract. [Current implementation and assurance mapping](13-GENERAL-CONTROL-LAYER.md) and [source-checked requirements](10-REQUIREMENTS-RECOVERY.md) take precedence. The official brief allows gateway, middleware or SDK alternatives; it does not mandate every protocol. The 11:00 cutoff is secondary schedule evidence, not an independently confirmed amendment.

# Adapting Mathguard to the AI Control Layer requirements

Inputs: the Goldman Sachs task brief and rules (`reference/`) and the Polish compendium
`HackYeah_2026_Goldman_Sachs_ kompendium.pdf`. This note lists what those sources require that
the current design does not yet cover, and how to change the design to cover it. Each change is
tagged with its evidence state (see `06-VALIDATION-AND-DEMO.md`). **PROVED** means a
`sorry`-free Lean theorem that builds in this repository. **DESIGN** means it is specified here
but neither implemented nor tested.

## 1. The main gap: the layer is ledger-centric, the judging is not

The current design does most of its work on a single protected tool, the ledger. The brief and
compendium score a **general gateway** that intercepts *every* AI interaction: prompts, model
calls, agent→MCP tool calls, agent→agent messages and model-artifact loads. On each one it must
**block, redact or pass in real time**, driven by a central policy file that judges edit live.
The compendium is explicit about three more points:

* regexes alone or an LLM classifier alone do not meet the description; it must be hybrid;
* the policy file is edited during evaluation. It must be validated, the last valid version
  must be kept when an edit is bad, and with no valid version everything is blocked;
* judges use prompts you have not seen, so a guard tuned to your own corpus is not evidence.

**Adaptation.** Keep the ledger as the showcase *irreversible tool*. Make the formally specified
core a **generic decision kernel** that every interaction goes through, with the ledger kernels
as the deeper check behind one tool. This repository now contains that kernel:
`Mathguard/Control.lean` (G1).

## 2. G1: generic control-layer decision kernel (new, PROVED)

`Mathguard/Control.lean` is pure, computable Lean. `lake build` compiles it to C
(`.lake/build/ir/Mathguard/Control.c`) and links it into `lake exe mathguard`.

| Requirement (brief / compendium) | G1 definition | Proved theorem(s) |
|---|---|---|
| Hybrid defence; semantic cannot weaken deterministic | `Decision` = independent flags `deny`/`ask`/`redact`; `gate = hardDecision ⊔ semanticDecision` | `Decision.combine_executes`, `gate_executes_imp_hard`, `gate_executes_imp_semantic`, `hard_atMost_gate`, `semantic_atMost_gate` |
| Block vs Redact thresholds | `piiRedactAt`, `piiBlockAt` | `pii_block_denied`, `pii_redact_flagged` |
| Strictness levels; local model too slow → "strict blocks, loose passes with alert" | `Strictness`, `fallbackDecision` | `strict_timeout_denies`, `strict_malformed_denies`, `balanced_timeout_not_executed`, `permissive_timeout_alerts` |
| Live policy edits by judges | `Stricter q p` (narrower allowlists, lower thresholds, more signatures, stricter mode) | `gate_mono`, `gate_mono_executes`: tightening any knob can only add restrictions |
| Validated reload, keep last good, fail closed | `PolicyStore.reload`, `ControlPolicy.valid` | `reload_invalid_keeps`, `reload_valid_activates`, `reload_epoch_mono`, `reloadAll_active_valid`, `no_policy_fail_closed` |
| Authentication / access checks | `authenticated`, model and tool allowlists | `unauthenticated_denied`, `model_not_allowed_denied`, `tool_not_allowed_denied` |
| Irreversible actions need approval (Excessive Agency) | `irreversibleTools`, trusted `approved` record | `irreversible_requires_approval` |
| Externally fed attack signatures | `signatures`, `signatureHit` (contiguous token match) | `signature_denied`: any content containing a feed signature is denied, whatever the classifier says |
| Supply chain: model repositories, unsafe deserialization | `artifactLoad hash format`, `pinnedArtifacts`, `ArtifactFormat.safe` (pickle/unknown never safe) | `artifact_admitted_pinned_safe` |
| Runaway loops; "step limit, not only token limit" | `maxSteps`, dispatch counter in `Session` | `sessionStep_steps_le`, `sessionRun_steps_le` |
| Exportable audit log; dashboard metrics | `Event`, append-only `Session.log`, `blockedCount` | `sessionStep_log`, `sessionRun_log` (one event per interaction, earlier events preserved), `blockedCount_step` |
| Memory isolation between users | `MemoryEntry`, `recall` | `recall_owned` |

Concrete fixtures are checked by `decide`: `demo_benign_prompt_executes`,
`demo_feed_signature_blocks`, `demo_pii_redacted_not_blocked`, `demo_pickle_artifact_blocked`,
`demo_transfer_waits_for_approval`, `demo_invalid_reload_keeps_last_good`. `lake exe mathguard`
prints the same cases at runtime (that output is a runtime test, not a proof).

**What G1 does not claim.** The detectors behind `piiScore` and the semantic `risk`, the
tokenisation of `content`, and the authenticity of `authenticated`/`approved` are trusted adapter
inputs. G1 proves how their outputs are *combined and enforced*, not that they detect attacks.

## 3. Target architecture

```
          app / agent / IDE / other agent
                       │  OpenAI-compatible HTTP  (change one base URL)
                       ▼
 ┌──────────────── Mathguard gateway (Python FastAPI or Go) ────────────────┐
 │ ingress: authN, schema, size limits, canonical IDs, tokenisation         │
 │ deterministic detectors: PII/secret regex+checksums, signature feed,     │
 │   artifact scanner (hash, format, pickle opcode scan, repo allowlist)    │
 │ semantic guard: local model via Ollama, typed JSON result, timeout,      │
 │   called only when the rules leave the decision open                     │
 │                       │ Interaction + SemanticResult                     │
 │                       ▼                                                  │
 │   Lean decision worker (compiled C binary of Mathguard.Control,          │
 │   Mathguard.Spec): gate / sessionStep / ledgerStep / budgetStep          │
 │                       │ Decision (+ reasons)                             │
 │ enforcement: pass │ redact (re-gate the redacted text) │ ask │ block     │
 │ budget manager (reserve before dispatch, settle after) — budgetStep      │
 │ policy watcher: file change → validate → PolicyStore.reload              │
 │ audit: JSONL event per interaction → dashboard + export                  │
 └───────┬───────────────┬────────────────────┬─────────────────────────────┘
         ▼               ▼                    ▼
   Ollama models    MCP / tool proxy     ledger executor (SQLite, one
   (local, budgeted) (allowlist, args,    transaction per ledgerStep commit)
                     approvals)
```

* **One integration point.** An OpenAI-compatible proxy in front of Ollama lets any agent framework
  route through the layer by changing a single address. That gives the compendium's "agent
  without the layer vs. with the layer" demo. Add an MCP proxy for tool calls (agent→MCP), and
  route agent→agent messages through the same `/v1/chat/completions` path as `prompt`
  interactions.
* **Running the Lean kernel in the request path.** Three options, in order of preference for the
  hackathon:
  1. *Long-lived Lean worker process.* Add a `mathguard-worker` executable that reads one JSON
     `Interaction` per line on stdin and writes the `Decision` on stdout. It holds the
     `PolicyStore` and the `Session`s in memory. No FFI is needed, and the decision code that
     runs is the compiled form of the definitions that were proved. The JSON decoding around it
     is not proved; reuse the W1 projection pattern and test it. Measure the latency rather than
     assuming it.
  2. *In-process C library.* Mark scalar entry points `@[export mathguard_gate]` and call the
     generated C through `ctypes` or `cgo`. This is faster, but the Lean runtime must be
     initialised and object marshalling has to be written.
  3. *Mirror implementation* in Python with differential tests against the Lean binary. This is
     weaker: it has to be labelled "model verified; runtime tested".
* **Atomic commit (unchanged requirement).** For the ledger, the worker computes
  `ledgerStep p s ctx q`. The executor installs the result in **one SQLite transaction**, checks
  the expected revision after taking the lock, and writes the journal, consumed approval,
  idempotency record and audit outbox together. In the single-process variant `atomicLedgerStep`
  (`Mathguard/Runtime.lean`) already installs the state with one `IO.Ref.modifyGet`. Neither
  variant has a proof about crashes or concurrency; that stays tested, not proved.

## 4. Requirement-by-requirement changes

### 4.1 Centralized policy engine, live edits (Formal requirement 1)
* One `policy.yaml` (safe loader) or JSON file. It holds strictness level (`permissive`/`balanced`/
  `strict`), PII redact/block thresholds, semantic review/block thresholds, allowed models,
  allowed and irreversible tools, pinned artifact hashes and allowed repos, signature-feed URL or
  path, budgets (tokens, cost, compute ms, tool calls, `max_steps`) and ledger policy.
* The file watcher calls validate → `PolicyStore.reload`. Bad edits keep the last good epoch,
  raise a red dashboard alarm and increment `rejectedReloads`. With no valid policy every request
  is blocked. **PROVED** in the model (`reloadAll_active_valid`, `no_policy_fail_closed`). The
  watcher itself is DESIGN.
* Ship three sample profiles (`dev`, `default`, `regulated`) that differ only in thresholds and
  strictness. `gate_mono` then guarantees that `regulated` blocks at least everything `default`
  blocks, and `default` at least everything `dev` blocks. That is a slide-worthy, checkable claim.

### 4.2 Deterministic and semantic controls (Formal requirement 2)
* Deterministic (DESIGN, fast path): PII (PESEL, IBAN, card numbers with Luhn, e-mail, phone),
  secrets (AWS/GitHub/JWT/private-key patterns plus an entropy check), canary tokens for system
  prompt leakage, signature feed, tool argument schemas, model allowlist, artifact rules.
* Semantic (DESIGN): a local model via Ollama, for example a small guard-style or instruction
  model prompted to return `{"risk": 0-100, "category": ...}`. It runs only when the
  deterministic layer has not already denied, with a hard deadline. A timeout or malformed
  output becomes `SemanticResult.timeout`/`.malformed` and goes through the **proved** fallback.
* Scan both directions: prompts *and* tool results / retrieved documents (indirect injection),
  and model outputs before delivery (Improper Output Handling). A redacted output is re-gated
  before delivery, never delivered as is.

### 4.3 Budget and resource governance (Formal requirement 3)
* The existing budget kernel (`Mathguard/Budget.lean`, PROVED) covers reserve-before-call and
  settle for cost, tokens, compute ms and tool calls, for both local (price 0, nonzero
  tokens/time) and commercial providers.
* G1 adds the **step limit** per session (PROVED: at most `maxSteps` dispatches). Loop detection
  on repeated identical tool calls (same fingerprint N times) is DESIGN and is an easy next G1
  extension.
* Add per-session and global buckets so that opening new sessions does not bypass the cap.

### 4.4 Historical attack mitigation (Formal requirement 4)
* Signature feed: versioned JSON with id, source, pattern and action, fetched from an external
  path or URL and validated like the policy. Blocking is **PROVED** (`signature_denied`) once the
  pattern is in the active policy.
* Model artifacts: allowlisted repositories, SHA-256 pinning, and refusal of pickle-based formats
  (`.pkl`, `.pt`, `.bin` without safetensors). Static opcode scanning of pickles (scan only, never
  load) feeds the detector. Admission is **PROVED** to require a pinned hash and a safe format
  (`artifact_admitted_pinned_safe`).
* Tool calls such as `exec`, `shell`, `eval`, `pip install` or URL-fetch-to-execute are not in
  the allowlist and are therefore denied (`tool_not_allowed_denied`).
* Build test artifacts as harmless files that are only scanned (compendium safety rule).

### 4.5 Reporting and audit (Formal requirement 5)
* Every interaction produces exactly one event (PROVED: `sessionRun_log`). Each event carries
  the epoch, decision flags, reason codes, latency per stage, budget deltas and hashed or redacted
  snippets.
* Dashboard (DESIGN): blocked/redacted/asked counts per reason (`blockedCount`), budget burn-down,
  policy epoch and reload alarms, p50/p95 latency of the deterministic path vs. the semantic
  path, and a management summary view. Export as JSONL and CSV.
* An "assurance" panel lists the exact theorem names and the commit hash. It says "model
  verified; runtime tested" until option 1 or 2 of §3 is in place.

### 4.6 Self-testing suite (Formal requirement 6)
* Three tiers: (a) Lean `decide` fixtures and theorems (`lake build`); (b) a pytest suite through
  the real HTTP path, with allowed, blocked, redacted, asked, budget-exhaustion, loop, artifact,
  feed-update and live-reload cases (reuse the L/B/F/H/S/A matrix in
  `06-VALIDATION-AND-DEMO.md`); (c) a **held-out** prompt set that was not used for tuning,
  with honest detection and false-positive rates.
* Variants the compendium asks for: encoded attacks (base64, leetspeak), Polish-language
  attacks, attacks split over several messages, and attacks hidden in tool output.
* One command: `docker compose up` to run everything and `make test` for the suite.

## 5. OWASP Top 10 for LLM Applications (2025) coverage

| Risk | Control | Type | Evidence |
|---|---|---|---|
| LLM01 Prompt injection (incl. indirect) | signature feed + semantic guard on prompts and tool results | both | blocking/combination PROVED; detection rate MEASURED on the held-out set |
| LLM02 Sensitive information disclosure | PII/secret redact/block thresholds; label flow gate (`Flow.lean`) | deterministic | enforcement PROVED |
| LLM03 Supply chain | artifact hash pinning, safe formats, repo allowlist | deterministic | PROVED (admission rule) |
| LLM04 Data/model poisoning | gate memory writes like outputs; provenance labels | both | DESIGN |
| LLM05 Improper output handling | output gate, re-gate after redaction, inert rendering | deterministic | DESIGN |
| LLM06 Excessive agency | tool allowlist, irreversible-tool approval, ledger kernels | deterministic | PROVED |
| LLM07 System prompt leakage | canary tokens as feed signatures on outputs | both | blocking PROVED once configured |
| LLM08 Vector/embedding weaknesses | owner-filtered retrieval | deterministic | `recall_owned` PROVED |
| LLM09 Misinformation | out of scope; roadmap | semantic | — |
| LLM10 Unbounded consumption | budget kernel + step limit | deterministic | PROVED |

## 6. Priorities by score weight

Robustness (30%) and architecture/performance + reporting (20% + 20%) dominate. Tests plus
implementability are 30% under both weightings. Suggested order of work:

1. Proxy skeleton, policy loading and the JSONL audit log, using the Lean worker (option 1).
2. Deterministic detectors, budgets and the step limit, plus the first allowed/blocked tests.
3. Semantic guard with timeout and fallback, the tool/MCP gate and approvals.
4. Dashboard and export, with p95 latency.
5. Artifact scanning, signature feed and the held-out set.
6. Slides (max 10), README, `docker compose`, and a rehearsal with unseen prompts and live policy
   edits.

Deadline: the compendium follows the HackTribe schedule (**4 Oct, 11:00**) rather than the 23:00
in the rules. Plan for 11:00 and submit by about 9:30.

## 7. Open questions for organizers
* Which weighting applies (rules 20/10 vs. details 15/15)?
* What is the format and length of the live test and pitch?
* Is the closing time 11:00 or 23:00?
