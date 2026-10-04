# Dashboard guide

Mathguard is an AI control layer. The dashboard is the operator's view of that layer and a small demonstration client. It is not an autonomous agent. Its model and shared-interaction requests pass through the gateway; the financial ledger demonstrates an irreversible tool.

## Start and connect

1. Install and serve a local Ollama model. Use the exact installed model ID, including its tag.
2. In the repository run `make setup MODEL=<exact-installed-ollama-model>`, then `make run`. After configuration, subsequent launches need only `make run`. The README gives prerequisites and the recommended model.
3. Open the loopback dashboard URL printed by the launcher. In a second terminal run `make credentials` to explicitly display the private operator, agent and owner credentials.
4. Paste the **operator** and **agent** credentials, then select **Connect & create session**. The **owner** credential is needed only to issue approvals. Separate roles are enforced by the server; hiding or disabling a button is not an authorization boundary.
5. Check the control posture before sending a request: active policy/feed versions, strictness, local model identity, provider mode, worker/storage status and any reload or quarantine warning.

Credentials stay in the current tab's DOM and request memory. They travel only in same-origin Authorization headers, not query strings, cookies, browser storage, audit downloads or management exports. **Clear credentials** invalidates the current UI session and removes pending approval/retry data. The server session expires separately; clearing the UI is not remote revocation.

After restarting with the same runtime directory, run `make run` again; setup is unnecessary. SQLite keeps committed ledger/resource/audit state, but sessions and outstanding approvals are invalidated. The next successful status refresh detects the new instance, clears stale session, approval and retry data, stops polling and asks you to select **Connect & create session**. Credentials remain in the current tab. Nothing is retried automatically. Check restored balances before proposing anything new; a pending uncommitted action requires a fresh proposal and approval. Clearing/reconnecting a session never resets global budget.

## A short judge demonstration

| Action | What to point at | Expected control behavior |
| --- | --- | --- |
| Send an ordinary question through **Model request** | Decision, filtered output, provider identity and resource headroom | Valid semantic evidence plus deterministic admission allows output. The real local model can still ask for review; fixture success is not an accuracy claim. |
| Inspect an **Agent message** containing `Contact test@example.com` | `input_disposition`, filtered content and redacted count | With the sample PII redaction policy and an admitting semantic verdict, the released content is redacted. |
| Inspect a **Tool call** with target `shell.exec` | Block reason and unchanged provider-call count | The allowlist blocks the unknown tool before dispatch. A semantic allow cannot override it. |
| Edit the runtime policy path printed by the launcher, increase `epoch` and tighten a guardrail, then **Reload files** | Active policy version and subsequent decision | Only a validated candidate activates. Existing charges and balances remain. |
| Introduce invalid JSON and select **Reload files** | Reload warning and unchanged active version | The last valid configuration remains active. With no valid policy/feed, execution remains closed. Restore a valid file before continuing. |
| Open the ledger demonstration, propose `15000` PLN minor units | Pending approval and the unchanged ledger revision/balances | A PLN 150.00 transfer exceeds the sample approval threshold. Approval issuance does not debit an account. |
| Select **Approve exact request**, then **Retry unchanged**, then retry again | Approved commit followed by replay | The exact approved ledger request commits once. An exact committed retry causes no second effect or resource charge. |
| Download management JSON and sanitized audit | Version, reason, resource and assurance metadata | Downloads contain decision metadata, not raw prompts or role credentials. The UI audit export is a bounded window, not a claim of complete history. |

The semantic model can deny a proposal, return review, time out or return malformed output. A separate owner approval cannot override semantic denial or unresolved semantic review. Explain the displayed outcome instead of changing a policy solely to force a successful demonstration. Repeated interactions can reach session step/repetition limits; create a new session only when appropriate, keeping global resource charges intact.

The model panel shows the active output cap. At the sample 128-token cap, longer replies can end mid-sentence. Allowed chat uses three separately charged calls; one measured benign CPU request took about 4.26 seconds across provider stages. The fresh sample compute allowance permits 12 complete chats before other usage, even though the call-slot allowance is 200. See the [policy budget example](../policies/README.md#budget-example).

The general interaction endpoint returns filtered content and dispatch authority. It does not execute `demo.echo` or `demo.publish` itself. The SDK/MCP integration controls tool dispatch and remains responsible for its external callback effect boundary.

## Read the overview correctly

| Display | Meaning and limit |
| --- | --- |
| Allowed / committed | Allowed content, committed ledger transitions and replayed ledger records. This is a count of request records, not unique effects. |
| Blocked / closed | Deterministic or semantic denials and requests that stay closed because a required component failed. |
| Review required | Pending approval/review records. Some semantic reviews cannot be resolved by an owner approval. |
| Redacted | Requests whose input or output disposition reports redaction. This flag can overlap allowed records. |
| Policy / feed and strictness | Current validated configuration, with strict/balanced/permissive semantic-failure behavior. Invalid edits remain visible without weakening the active configuration. |
| Local provider | Exact configured semantic model, live versus fixture mode and observed successful live provider returns. A fixture is labeled **TEST FIXTURE · not live AI**. |
| Request / control p95 | End-to-end request latency versus detector facts plus the compiled gate round trip. Control timing excludes provider inference; sample counts are shown. |
| Headroom bars | Limit minus conservative charged bounds and active reservations. Tokens, elapsed-compute allowances, policy cost units and provider call slots have separate units. |
| Provider observations | Returned token reports, the count of token-reporting calls and elapsed adapter time across attempted calls. Unreported tokens are not treated as zero usage. Adapter time is not GPU utilization or a measured financial bill. |
| Storage scope | Volatile mode resets the ledger/quotas on restart. Configured SQLite mode preserves journaled state and sanitized audit on a single node; recovered sessions/approvals are invalidated. No distributed guarantee is implied. |
| Audit window | Latest 30 metadata records displayed. Downloads are capped by the server, normally 2000 records per page; complete retained history requires the documented paginated API (`?after=0&limit=2000` starts at the oldest retained record, then use the last returned ID as `after`). SQLite `audit_id` and volatile `event_id` are distinct pagination anchors. |

The assurance drawer preserves exact build identity and limitations. The compiled Lean model verifies rule composition and modeled transitions. It does not prove that the semantic detector catches every attack or that host parsing, authentication, provider execution or crash behavior is correct.

## Quarantine and uncertain requests

After a provider timeout or adapter failure, stop or verify completion of the upstream local-model job. A stopped adapter process does not prove that the GPU job stopped. The dashboard requires a fresh operator attestation for the current quarantine incident before recovery. Recovery preserves charges and the ledger.

A browser deadline can expire while the server is still handling a request. The UI says **the request may still finish** and never silently resubmits it. Refresh first. Use an unchanged ledger request for an exact retry; do not create a new payment request to compensate for an unknown result. Model requests have no automatic retry.

Polling runs at five-second intervals, pauses while the tab is hidden or a write action is running, coalesces overlapping refreshes and backs off to a maximum of thirty seconds after failures. A stale-view notice is not evidence that execution succeeded or failed. Refresh failures and invalid configuration are shown without inserting server-provided HTML into the page.

## Verification record

`python -m unittest discover -s tests -p test_dashboard.py -v` exercises twelve static and Node DOM-harness cases: credential input posture; matching accessible controls; absence of HTML insertion/browser persistence sinks; hostile metadata as text; truthful fixture/storage/resource labels; role headers and bounded requests; oversized response/error/deadline behavior; unchanged retries; coalesced refresh; fresh quarantine attestation; credential clearing; restart invalidation and explicit reconnect without automatic retry; and sanitized management download with limitations preserved.

The harness is not a browser layout engine. It does not certify pixel layout, keyboard navigation, browser downloads or actual Ollama inference. Final browser QA belongs to the release integration review; record observed desktop/mobile rendering and actual clicks there without inventing screenshots or live model quality results.
