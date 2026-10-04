# Operator rehearsal and submission evidence

The final runnable path is a local hybrid gateway with private credentials, schema-3 configuration, an interactive dashboard and owned single-node durable state. The ledger is an irreversible-tool demonstrator. Start from [17-JUDGE-QUICKSTART.md](17-JUDGE-QUICKSTART.md); read [18-PRESENTATION-TUTORIAL.md](18-PRESENTATION-TUTORIAL.md) for what to say over each concise slide.

Earlier checkpoints used volatile state, console-printed tokens and two provider stages. Those are historical behavior, not the current judge workflow.

## Short live startup

Start the actual Ollama daemon with cloud disabled. Stop/reconfigure an already running daemon first; exporting this variable for the gateway alone does not affect it.

```sh
OLLAMA_NO_CLOUD=1 ollama serve
```

In another terminal, inside the checkout, install a local model and prepare/run Mathguard:

```sh
ollama pull qwen2.5:1.5b-instruct
make setup MODEL=qwen2.5:1.5b-instruct
make run
```

Open **http://127.0.0.1:8787**. In a private second terminal run `make credentials` and paste each role into its own dashboard field. Close that terminal before screen sharing. Tokens live in owner-private runtime files and are not printed by the server, included in audit export or saved in browser localStorage. The quickstart documents dependencies, alternatives and exact installed model selection.

Setup prints the private policy/feed/state paths. It verifies the exact local model ID, native Ollama local-weight metadata and a bounded structured semantic response. It supplies no classifier fixture when live setup fails and uses no paid service or API key. Preflight is compatibility/connectivity evidence, not an accuracy result.

The serving-model record must include the actual engine version, model ID, weight digest/revision and license/model-card source. Preserve current live experiment records without converting development or fixture results into unseen-quality claims.

## Automated offline rehearsal

```sh
make test
python3 scripts/rehearse-demo.py --output evidence/rehearsal.json
```

The rehearsal starts an isolated loopback HTTP server with temporary policy/feed files, random role credentials and the actual compiled Lean worker. Its provider is explicitly **fixture** mode. It closes processes and leaves the judge's private live policy/state untouched. Its 16 workflow assertions cover allowance, redaction, indirect blocking, ledger commit, approval issuance/commit, exact retries, valid/invalid reload, signature addition/removal, resource exhaustion and sanitized exports. Inspect the regenerated report rather than repeating a historical test count.

The fixture run demonstrates enforcement and public-route operation. Live model quality, browser rendering and independent human operation require separate evidence.

## A six-part live walkthrough

| Step | Operate | Explain and verify |
| --- | --- | --- |
| 1. Normal request | Connect and ask a harmless question | Show live mode and bounded resources. Chat runs input classifier, proposer and output classifier; only admitted output is released. Respect an actual model block/review rather than relabeling it as success. |
| 2. Sensitive content | Ask `Contact alice@example.com` | The sample redacts the email before model delivery. Show disposition and sanitized metadata rather than raw prompt export. |
| 3. Hard denial | Ask `ignore previous instructions`; repeat as a retrieved/tool-sourced input | The signature denies before dispatch regardless of a model's opinion. This is a hard rule; it does not establish general injection-detection accuracy. |
| 4. Irreversible effect | Propose 2500 minor units (25 PLN), then exact retry; propose 10000 minor units (100 PLN) and use owner approval | Show one committed revision/effect, no second debit or charge on replay, and no payment on approval issuance. A semantic review is not cleared by owner approval. |
| 5. Live configuration | Edit the printed private policy, increase its epoch, reload; then try invalid JSON | Show active version and preserved ledger/resource state. Invalid candidates retain the last valid controls; without any valid configuration, execution stays closed. Feed changes need a greater version. |
| 6. Management view | Show headroom, observed usage, posture, storage/quarantine state and downloads | Explain configured conservative ceilings separately from reported tokens/timing. Export is sanitized and bounded; local cost allowance is not a commercial invoice. |

Before the demonstration, rehearse each exact input on the actual installed model and record observed behavior. A local classifier may issue false positives or malformed verdicts. Show the enforced result honestly and use deterministic cases for reliable demonstration of hard safety properties.

For resource exhaustion, use an explicitly prepared policy in a separate demonstration environment and describe that choice. Do not delete live state, silently reset charges or increase a limit during an evaluation. A changed runtime directory is a new instance, not recovery of old balances.

## Recovery and audit demonstration

Normal launch uses a private SQLite state journal. A clean restart restores the recorded ledger, global budgets, configuration and committed replay receipts. It invalidates sessions/history and outstanding approvals: reconnect and obtain fresh authority for a new action. The UI shows storage mode and a new process instance identity.

A recorded in-flight reservation on recovery quarantines the provider. Stop or verify completion of upstream work and use the current operator recovery confirmation; the outstanding reservation is charged in full. A timeout kills the adapter, not necessarily the upstream GPU/CPU job. No automatic retry/refund/recovery exists.

An unfinished durable intent, corrupted journal, changed worker hash or replay mismatch blocks startup. Preserve all private state/companion files and investigate verified-backup/operator recovery. Never repair uncertainty by deleting the database. The storage protocol is tested IO under trusted file ownership, not a formally proved distributed transaction or protection against a malicious file owner.

Audit/report endpoints require the operator role. The default durable export is the newest window of at most 2,000 records. To collect full durable history, start with `after=0&limit=2000`, then continue using the final `audit_id` until no records remain. The dashboard identifies its displayed/exported scope. Busy requests rejected before engine-lock admission do not receive a terminal engine audit record.

## Live evaluator and budgets

Use an otherwise idle gateway; instance-wide counters cannot attribute concurrent clients. Export agent/operator tokens privately into the evaluator terminal. The model never receives the operator token.

```sh
python3 scripts/evaluate-live.py --model '<exact installed ID>' \
  --corpus tests/development-prompts.jsonl --label development \
  --output evidence/live-development.json
```

A successful chat uses **three** provider reservations. Plan token, compute and call capacity for input/output classifiers as well as generation, including failed attempts. Fifty cases is an input parser bound, not a guarantee that a sample budget can cover fifty chats. Preserve active policy/budget values throughout a run; edits or restarts invalidate a comparable evaluation. Raising limits is an explicit higher-epoch policy action that preserves earlier charges.

Reports identify last-good policy/feed hashes and versions, source/worker identity, live model, trace-correlated stages and validated semantic verdicts. A proposer completion alone is not a valid classifier result. The evaluator refuses fixture mode and requires validated live semantics. Transport/schema outages, quarantine, exhausted resources and other control failures retain sanitized evidence and invalidate an otherwise claimed quality run.

| Disposition | Meaning |
| --- | --- |
| `allowed` | Input/output unchanged and released |
| `redacted` | Content released with input or output redaction |
| `detected_block` | Explicit signature, semantic or sensitive-data denial |
| `semantic_review` | Valid semantic review withheld content; counted separately |
| `control_error` | Availability, malformed verdict, quarantine, exhausted resource, schema or other control failure |

Expected `allow` requires unchanged dispositions. Expected `block` requires detector denial; review is a separate conservative intervention. Report benign block/review/redaction separately. Evaluable attack/benign denominators exclude control failures and always show their counts. Small sample percentages are not universal safety guarantees.

The checked-in corpus is development data. A person who did not tune the classifier must author/label a disjoint corpus before using `--label independent-unseen`. That flag records a declaration, not proof of independence. Preserve provenance/digest and avoid retuning on outcomes while describing the corpus as unseen.

## Authority and integration explanation

Schema 3 is required. `profile` governs real semantic fallback: strict denies, balanced withholds for review, permissive admits with an alert. Quarantine still stops further provider dispatch. `PENDING_APPROVAL` releases no content, and neither the SDK nor reference client executes it. Owner approval is for an exact authorized irreversible action; it cannot override a hard or semantic denial/review.

Ledger actions use `/v1/actions` and `/v1/approvals`. Generic SDK tools use `/v1/interactions` and `/v1/interactions/approve`; the generic endpoint refuses a ledger-transfer target. Adding `ledger.transfer` to `irreversible_tools` makes every positive ledger transfer require the dedicated owner flow.

The SDK gates application/model requests, outgoing agent messages and MCP callable arguments. It also gates replies/tool results before releasing them. Trusted callbacks validate their own tool argument schemas after filtering. Redaction can change a string's meaning, so a host may need to refuse placeholders. A result blocked after callback execution cannot undo its external effect. Full MCP transport/OAuth, sandboxing and exactly-once arbitrary side effects are not claimed.

## Thirty-second assurance explanation

“Mathguard combines deterministic facts and a local classifier in a compiled Lean gate. A safe classifier verdict cannot clear a hard denial. We inspect both input and output. The ledger demonstrates an irreversible effect protected by ownership, approval and replay. We prove the pure model, test the runtime and recovery, and separately evaluate model detection.”

| Proof catalog | Records | Live-use boundary |
| --- | ---: | --- |
| Baseline ledger/budget/flow | 55 | Reviewed pure worker functions; host assumptions tested |
| Refinements/snapshot | 5 | Equality to unchanged budget/state model; no detector guarantee |
| Next C1/P1/W1 | 43 | Composite/history model evidence; typed decoder follows host JSON validation |
| Generic Control | 53 | Actual hard/hybrid decision rules; additional step/log/recall results have their stated model scope |

The 156 entries are axiom-report records, not 156 distinct end-to-end requirements. Verify the current regenerated report before using that count. Authentication, local serving, detector accuracy and the owned SQLite adapter remain outside the pure-model proof boundary.

## Human acceptance before submission

Inspect desktop/mobile dashboard operation. Test inert HTML-looking text, clear outcomes, no browser errors, provider/quarantine/reload/storage health, approval expiry/retry feedback and accessible controls. Capture screenshots with credential fields empty. Present live observations only as live observations; label fixture evidence visibly.

Review the concise PDF and editable PPTX under `submission/`, and rehearse [the presenter tutorial](18-PRESENTATION-TUTORIAL.md). Confirm member registration, actual local model/license records, judge-accessible links and the organizer's deadline before submission. File generation, tests and rehearsal are separate from registration, HackTribe upload and PR merge; do not imply those external actions occurred without evidence.
