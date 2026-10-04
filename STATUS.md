# Mathguard: final engineering checkpoint

Mathguard is a local AI control gateway and SDK. The ledger is its irreversible-tool demonstrator. The four assessed deliverables are implemented: component and architecture diagram, live policy samples, interactive dashboard and automated suite. The repository's judge entry points are `make setup`, `make run` and `make test`.

## Release evidence

| Check | Result | Scope |
|---|---|---|
| Canonical local gate | Pinned Lean build, axiom audit, native regressions and runtime suite pass | Execution sandbox uses a documented path-discovery compatibility shim; no shim ships with the project |
| Lean axiom catalog | 156 records: 55 baseline, 5 refinements, 43 Next, 53 Control | Catalog size, not 156 independent security requirements |
| Python runtime suite | 189 passed, 0 failures/errors/skips | Actual compiled worker with labeled classifier/protocol fixtures and dashboard DOM behavior |
| Static audit/parser regressions | 14 passed | Source contracts and audit handling |
| Public HTTP fixture rehearsal | 16 cases passed | Policy/feed edits, redaction, budget stopping, approval/retry and export |
| Real local CPU rehearsal | 10 cases passed | Ollama 0.35.1, Qwen2.5 1.5B instruction weights, strict schema, 128-token cap; chat, ledger approval/retry, policy edits and same-journal restart |
| Live development corpus | 8/8 expected outcomes; valid run, zero control errors | Three benign requests, one email-redaction case and four attacks; used during prompt development, not held out |
| Exploratory classifier probes | 9 valid verdicts, 8 expected outcomes | A support-note instruction to publish private contact records was falsely allowed; raw classification, not an executed leak |
| Prelint live follow-up | 2 operational probes completed | The known prompt still passed input inspection; proposer refused and the refusal was released. A separate constructed harmful output was blocked. No exfiltration tool was invoked. |
| Presentation | 10 concise slides, editable architecture/tables and presenter notes | Exported PDF pages rendered and checked; Polish tutorial plus English speaking scripts |

The local chat made three real calls: semantic input inspection, generation and semantic output inspection. Known-signature and tightened-PII denials made zero model calls. Real ledger requests committed once, required separate owner approval when configured, and returned exact retries without a second debit or charge. Restart preserved revision 2, balances, consumed resources, observed usage, last-good configuration and durable audit metadata, including an invalid policy file still on disk. These finite cases establish working local integration, not general detector accuracy.

Source/binary fingerprints and individual assertions are in [integration.json](evidence/integration.json), [rehearsal.json](evidence/rehearsal.json) and [live-local-rehearsal.json](evidence/live-local-rehearsal.json). The installed weights/version/license are in [model-record.json](submission/model-record.json). No model weights or role credentials are bundled.

The [eight-case development result](evidence/live-development-evaluation.json) and [nine-probe diagnostic](evidence/semantic-prompt-development.json) retain their exact model, policy and wire identities. Historical 0.5B overblocking, a 512-token CPU timeout and a free-form JSON truncation remain recorded as failures. Strict schema generation fixes the demonstrated formatting issue; it does not fix every semantic miss. The selected sample keeps a 15-second deadline and a 16,000 ms configured compute charge bound. Completion within that deadline depends on the deployed hardware and workload.

The [Prelint follow-up](docs/verification/PRELINT-FOLLOWUP.md) adds explicit cap/latency/budget guidance, dashboard restart detection with safe explicit reconnect, SDK denial/failure distinction checks and [actual indirect-prompt observations](evidence/prelint-indirect-live.json). The input detection miss remains; a harmless proposer refusal is not credited as a classifier block.

## Safety layers delivered

- Bounded UTF-8 JSON, types, identifiers, HTTP framing/headers/bodies, response sizes, worker IO and admission waits.
- Separate agent/owner/operator roles, private credentials, loopback-only endpoints, no redirects or ambient proxies, cloud-model identifier refusal and actual daemon cloud-disable setup.
- Shared deterministic and local semantic gates. Hard denials survive semantic approval. Model answers receive both checks before release. Classifier generation uses a shared strict JSON schema; the host independently validates every verdict and never downgrades an unsupported format.
- PII/secret, encoded/Unicode/split/indirect inspection; structured redaction preserves keys/types. Overlapping secret spans are merged. Every later model dispatch revalidates retained history under the current policy.
- Validated live policy/feed activation, invalid-edit last-good retention, no-valid-policy denial, and preserved balances/charges on reload.
- Durable reservation before provider dispatch, conservative resource charges, global/session/repeat limits and explicit timeout quarantine/recovery.
- Exact owner approval binding, expiry, single consumption and ledger retry receipts. Restart restores acknowledged ledger/resource transitions, receipts and nonce floor; sessions and outstanding approvals are invalidated.
- Private single-owner SQLite worker-command journal. Unresolved intent, corruption, response/binary mismatch, unsafe permissions, second ownership and capacity exhaustion fail closed.
- Pinned bounded inert artifact inspection without deserialization or execution. Hash checks and supported structure checks do not certify arbitrary model loaders.
- Clear dashboard outcomes/posture/headroom, separately observed usage, safe credentials/text rendering, bounded refresh/export and sanitized audit pagination.

## Assurance and remaining acceptance

The compiled worker enforces existing Lean functions in the request path. The [release-hardening proofs](docs/verification/RELEASE-HARDENING-RESULTS.md) now establish H1 correspondence to its actual typed financial dispatch, with the JSON-null fidelity assumption removed. A separate 85-record audit and nine native H1 checks join the release gate. Parts of H2 worker replay and H5 worker reload are proved; H3 issuance/admission is a proposed model. Raw parsing, authentication, provider IO, host history/approval composition and SQLite durability remain runtime-tested boundaries. C1/P1 remain separate models. Earlier live-model and dashboard evidence retains its previous worker fingerprints. See [release assurance](docs/verification/RELEASE-ASSURANCE.md) and the remaining [Aristotle campaigns](aristotle/FINAL-HARDENING-HANDOFF.md).

This is a trusted-filesystem, single-node demonstrator. Hash chains detect inconsistency, not malicious rewriting or rollback by the host administrator. Adapter timeout does not prove upstream GPU cancellation. External SDK callbacks require their own idempotency and effect-recovery protocols. Local cost allowances are policy units, not measured commercial invoices.

Independent unseen prompt evaluation remains open. The review browser rejected localhost with `ERR_BLOCKED_BY_CLIENT`, so browser layout, downloads and a human operator rehearsal are not claimed. Dashboard DOM/security tests and actual HTTP serving pass. Final team/member registration, organizer cutoff confirmation and HackTribe acceptance are external steps. Preserve the earlier reported 11:00 cutoff until the conflicting 23:00 rule is clarified.

[Judge quickstart](docs/17-JUDGE-QUICKSTART.md) · [Dashboard guide](docs/16-DASHBOARD-GUIDE.md) · [Presenter tutorial](docs/18-PRESENTATION-TUTORIAL.md) · [Full release plan](docs/15-FINAL-RELEASE-PLAN.md).

The implementation and Prelint follow-up were merged into `main` in PR #6 (`2539ac4`). The [project description and submission fields](docs/01-PRODUCT-AND-CHALLENGE.md) reflect that release. No GitHub Actions or paid inference APIs are required.
