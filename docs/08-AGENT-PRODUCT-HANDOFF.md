# Mathguard — specification for the agent, product, and visualization AI agent

## Copy-paste assignment

Implement the visible reference workflow for **Mathguard**, Goldman Sachs' HackYeah AI Control Layer, in `https://github.com/ljaniec/Mathguard`. You are one of the team members' AI coding agents. Coordinate with the enforcement agent through `docs/07-TEAM-INTEGRATION-CONTRACT.md`. Łukasz owns the formal modules. Your work is `agent/`, `dashboard/`, frontend tests, demo fixtures, and product presentation. Use PRs for every milestone so Prelint can review progress and scope. Do not merge or overwrite another agent's work.

Start from the imported Lake foundation, PR #1 / branch `integration/aristotle-model-v1`, or its merged successor. Fetch current state before editing. There is a native **demo executable**, not yet a JSON gateway/worker or finished UI. The supplied Aristotle run proves the original 55 model targets; local rebuild status must remain explicit. There are 35 new requested targets, which are not complete. Do not ask Aristotle to repeat the original work or put requested targets in a verified badge.

Read this document, the shared contract, `docs/03-AGENT-PRODUCT-VISUALIZATION.md`, `docs/06-VALIDATION-AND-DEMO.md`, and `docs/verification/IMPORT-AUDIT.md`. The older documents provide detailed scenarios; this assignment and the shared contract control current ownership and integration.

## Product outcome

Deliver a compact, coherent live product showing a real agent proposal passing through Mathguard before any effect. A legitimate payment should work. Hostile or invalid proposals should fail with intelligible reasons. Approval, replay, policy versioning, resources, and formal evidence should be visible from one screen. The reference application is a simulated personal-account ledger; the product is the control layer.

Do not build a generic bank dashboard that hides the control decisions. Do not make a client-side fake ledger look like the protected executor. Financial outcomes come exclusively from the engine. Existing logo and Łukasz's wording should be preserved unless a specific change is needed.

## Deliverables

1. Structured proposer with bounded orchestration and two clearly marked modes: `live` local/provider model and `fixture` deterministic candidate stream.
2. One usable dashboard with prompt/scenario selection, proposal and approval card, decision timeline, ledger delta, budget/policy panel, and assurance/evidence panel.
3. Engine-client layer consuming the shared typed schema and events; no independent financial arithmetic/executor.
4. Scenarios and meaningful frontend/integration checks for allowed payment, approval substitution, retry, stale action, confidential export, and resource exhaustion.
5. Operator-facing policy/feed changes through authorized backend endpoints, sanitized audit download, and measured stage timings.
6. Demo script and presentation content for at most ten slides; do not generate final result claims before the checks exist.

Choose a small familiar stack. A React/TypeScript frontend is fine; Streamlit is acceptable if it reaches the real workflow sooner. Use decimal **strings** for wire money/counters. UI formatting may show PLN, but never turn a string into a JavaScript number and back for execution.

## Agent behavior and authority

The model is a proposal generator with only the tools the gateway exposes. It never has database, raw ledger-worker, approval-issuance, policy-admin, or downstream-provider credentials. Every model/semantic/tool call goes through the engine's budgeted adapters; no hidden direct model route for the product agent.

For a request such as “Pay Bob 25 PLN for lunch,” the proposer emits only the supported candidate vocabulary and validated arguments. Supported first actions:

- scoped ledger summary;
- transfer proposal;
- retrieval of a synthetic untrusted invoice;
- structured report export to a configured named sink.

The gateway constructs canonical request identity/version/context and returns the exact proposed transfer for display. The agent cannot choose an effective principal, owner, policy epoch override, public taint label, or `approved=true` flag. Do not silently repair negative/fractional amounts, unknown accounts, or unsupported currencies into executed operations. Show a new candidate if a user clarifies the request.

Bound the loop with maximum iterations, calls, deadlines, and output tokens. Retries consume resources. A model's “safe” text is not an executable permit. The semantic guard is separate from the financial proposer. Prefer a provided OpenAI-compatible local model endpoint; if unavailable, keep an honest fixture mode and record the missing live dependency. Do not imply a scripted proposal is a real LLM run.

## Required screens and event rendering

| Surface | Information | Acceptance |
|---|---|---|
| Scenario/prompt | Persona, mode, provider, prompt | Visible live vs fixture; no identity override through request fields |
| Candidate card | Exact source/destination/minor units formatted as PLN, ID, epoch/revision | Shows gateway canonical proposal; not agent HTML |
| Timeline | Hard checks, semantic result, resource reservation, commit/replay/rejection | Ordered backend events; reason text is sanitized |
| Ledger | Authorized before/after balances, total, revision, paired receipt | Only authoritative commit updates animation |
| Approval | Bound action, owner, expiry, version | Separate owner session; exact unchanged execution |
| Policy/budget | Active epoch, selected rules, spent/reserved/limits, inflight | Validated activation; existing counters preserved |
| Assurance | 55 original target status, new requested target status, toolchain, evidence origin, runtime limits | No false whole-stack verification claim |

Display `COMMITTED`, `REPLAYED`, `PENDING_APPROVAL`, `BLOCKED`, `ERROR_CLOSED` as distinct financial outcomes. `REDACTED_OUTPUT` is a separate output disposition. A `PENDING_APPROVAL` card has no financial effect. A replay does not increment the journal or show a second payment animation. Timeout/error is not a semantic safe verdict.

The current in-memory native demo reads balances after a transition; production event/receipt rendering must instead use the receipt returned by the same authoritative transition/transaction. A later balance read could show another action's result under concurrency.

Subscribe to sanitized SSE or poll with bounded interval. Deduplicate event IDs after reconnect. Never infer success from HTTP timing or an optimistic frontend counter. Render documents, purpose strings, and model explanations as inert text. Do not export raw tokens, approval secrets, full account statements, or injected secret values.

## Six integrated scenarios

1. **Legitimate transfer:** canonical fixture Alice → Bob 2500 minor units from revision 0, epoch 7; balances 97500/22500/0, total 120000, journal length 1.
2. **Exact owner approval:** amount at threshold 10000 requires authenticated owner approval. Changing beneficiary/amount/ID/epoch/revision rejects the receipt. The UI must not manufacture approval contents.
3. **Duplicate delivery:** execute one approved/ordinary request then repeat its exact canonical payload; get prior receipt and no second debit. Changed payload under same ID conflicts.
4. **Live policy/revision change:** operator activates higher epoch; old pending request fails as fresh action. Re-propose at new version. Show that an already committed request can still replay without a new effect.
5. **Untrusted invoice and sensitive flow:** display separate provenance/confidentiality labels; attempt disallowed external export after a sensitive read. Hard flow gate blocks even with semantic permit. Also show an authorized internal destination so the system is useful.
6. **Runaway resources:** repeated budgeted model/tool calls stop before the next dispatch exceeds the limit. Include classifier cost, local tokens/time, and reserved amounts; zero external price is not zero compute demand.

Do not depend on a live model choosing an injection every time. For deterministic security validation, send the attack candidate through a clearly labeled test client to the same engine. Include at least one real live-model/semantic call if available and report actual timings.

## Milestone PRs

| PR | Deliverable | Evidence |
|---|---|---|
| A1 | UI shell, shared-schema client, labeled fixture flow | Fixture screenshot and schema checks; mocks explicit |
| A2 | Real agent/model mediation and positive/negative ledger path | Engine trace IDs; one successful and one blocked action |
| A3 | Owner approval, exact replay, stale versions, policy/budget panels | Backend receipts and unchanged state on negative cases |
| A4 | Semantic/flow/signature scenarios, evidence panel, demo assets | Real vs fixture status; sanitized export; integrated report |

Read Prelint comments/checks on each PR. Fix correctness/scope findings; document why an inapplicable suggestion is deferred. Update `STATUS.md` with completed behavior, tests actually run, unresolved dependency on the engine/formal owner, and next work. Do not report a fixture-only screen as an implemented enforcement path.

## Dependencies to request concretely

Need the engine's canonical proposal/snapshot/decision endpoints, approval issuance flow, event stream, policy activation response, budget state, and assurance manifest. Agree exact JSON fixtures early. If an endpoint is missing, implement a **clearly marked** client stub and track its replacement. Do not open a parallel bypass to the database, Lean worker, model provider, or approval store.

## Definition of done

The dashboard can demonstrate all six scenarios through the real engine, clearly labels any fixture/live limitation, shows correct state changes/replays, and exposes useful policy/resource/evidence information. Automated checks cover contract mismatches and unsafe rendering; end-to-end tests use authoritative backend state. Scope and unfinished guarantees are accurately stated. The interface helps judges assess the control layer within two minutes.
