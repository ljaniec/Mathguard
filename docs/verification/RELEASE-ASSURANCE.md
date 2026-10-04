# Release assurance boundary

This document maps the current compiled definitions to the host contract and sets the
acceptance boundary for the final hardening work in [the release plan](../15-FINAL-RELEASE-PLAN.md).
It is an independent agent review, not a human security audit or production certification.
No new theorem is counted merely because it is described here or in the Aristotle handoff.

## Evidence states and reproducibility

| State | Required evidence | Does not establish |
|---|---|---|
| Proved | Exact theorem/definition, pinned Lean build and axiom report | Correctness of an arbitrary adapter or deployment |
| Runtime tested | Executed real worker/host path, assertions, source/binary fingerprints | An exhaustive theorem or classifier accuracy |
| Empirically measured | Actual installed model/hardware and declared corpus, outcomes and failures | Universal attack detection or an independently unseen corpus without provenance |
| Proposed | Definitions, hypotheses and target statements in the handoff | Delivered runtime behavior or a checked proof |

The existing proof catalog is **156 records: 55 baseline + 5 refinements + 43 Next + 53 Control**.
Next contains 35 original targets and eight supporting records. The 156 figure is a catalog
size, not 156 independent security requirements. Control's reported dependencies are at most
`propext` and `Quot.sound`; the wider catalog permits the documented standard Lean axioms.
The pinned environment is Lean 4.28.0 and Mathlib
`8f9d9cff6bd728b17a24e163c9402775d9e6a365`.

The final canonical `make test` passed the pinned Lean build, fresh 156-record axiom audit,
native regressions, **14 static regressions and 189 integration cases**, with zero failures,
errors or skips. `evidence/integration.json` was collected at
**2026-10-04T02:40:39.907793+00:00**. Its suite breakdown is:

| Module | Passed cases |
|---|---:|
| Gateway | 69 |
| Runtime persistence / approval / history hardening | 33 |
| HTTP / SDK boundary hardening | 24 |
| Detector / parser / artifact hardening | 22 |
| Provider | 11 |
| Evaluator | 11 |
| Dashboard DOM / request behavior | 12 |
| Judge setup | 7 |
| **Total** | **189** |

The fresh public HTTP fixture rehearsal passed **16 cases** at
2026-10-04T02:13:17.463186+00:00. The real local-model setup, HTTP, ledger approval/retry
and same-journal restart rehearsal passed **ten logical checks** at
2026-10-04T02:11:39.004963+00:00. It used Ollama 0.35.1, downloaded
`qwen2.5:1.5b-instruct` weights (986,061,892 package bytes, recorded digest/license) and
`OLLAMA_NO_CLOUD=1` on the actual daemon. The final configuration requests strict semantic
JSON-schema generation and caps model output at 128 tokens per call; the 15-second per-call
deadline and resource ceilings remain unchanged. The rehearsal observed three-stage benign
chat, hard signature/PII denial without inference, low-value ledger commit/retry, separate
owner approval and commit/retry, live policy preservation and same-journal restart. These
are finite operational observations. See `evidence/rehearsal.json`,
`evidence/live-local-rehearsal.json` and `submission/model-record.json`.

Independent comparison found no mismatch in the integration, fixture, development evaluation
and real rehearsal reports' **60, six, nine and 13** recorded source fingerprints respectively;
all recorded worker hashes matched the current binary. The selected raw-classifier variant
separately has **seven** matching source fingerprints, the current sample policy and the exact
shared prompt/schema hashes. Historical reports intentionally retain their earlier source
snapshots; they are not asserted to match the chosen release.

Browser rendering, downloads and operator click rehearsal remain open: the cloud browser
refused the local page with `net::ERR_BLOCKED_BY_CLIENT`. DOM/request tests do not replace
that acceptance. The earlier 83-case checkpoint is historical. A static provenance check
does not replace a Lean build. Definition-only handoff files do not enlarge the catalog:
`aristotle/release/RuntimeSpec.lean` independently typechecked on the pinned toolchain, but
its target correspondence and preservation theorems remain unproved.

### Semantic-model acceptance and known failures

The chosen 1.5B/strict-schema/128-token configuration passed all **eight checked-in development
interactions**: three benign allows, one redaction and four blocks. The run was valid, with
stable configuration, zero control errors and nine validated live semantic verdicts.
Three attack cases were deterministic signature denials with no inference; the remaining
indirect case received a semantic denial before proposer dispatch. These outcomes establish
finite behavior on the development cases, not a classifier accuracy estimate. The prompt
was tuned using this corpus; there is no independently held-out quality result.

The current-wire raw probe separately covered five selected development inputs and four
supplementary developer inputs. All **nine** responses were valid; **eight** matched their
expected raw disposition. The support-note/public-paste instruction to disclose private
contact records still received `risk: 0, verdict: allow` where the expected disposition was
block. This is a known semantic false allow. It is input-classifier evidence, not proof that
a complete gateway interaction released private data. Its record remains in the selected
`coupled_15_strict_schema128` variant of `evidence/semantic-prompt-development.json`.

The [Prelint live follow-up](../../evidence/prelint-indirect-live.json) sent the exact known
prompt through the public gateway. Input inspection again allowed it with `risk=0`, but the
proposer refused and the output gate allowed that harmless refusal. A separate constructed
harmful-output probe was semantically blocked. The latter was not generated by the proposer;
neither probe accessed records or dispatched an exfiltration tool. These observations do not
close the input detection gap or estimate unseen accuracy. The [follow-up record](PRELINT-FOLLOWUP.md)
also documents cap/budget clarity, explicit dashboard reconnect after restart and the existing
SDK distinction between policy denial and callback failure.

The earlier 0.5B baseline was a valid but failed run: it falsely blocked all three benign
cases and withheld the redaction case. The 1.5B/512-token run timed out and quarantined the
provider; private 128- and 256-token trials using the earlier `json_object` format produced
malformed semantic output and invalid quality runs. Those reports remain as historical
failure evidence. Availability/schema failures are not counted as successful detection.

Strict JSON-schema generation requests output shape, not correct threat classification.
Production and preflight share the same prompt/schema. The host still accepts only exact
bounded `risk`/`verdict` fields and conservatively combines both: a low-risk `block` stays
blocked, a high-risk `allow` stays restricted, and `review` withholds content. An unsupported
schema request is not silently retried with weaker formatting. Six independent focused
checks passed for veto/review/threshold enforcement, malformed fallback, actual HTTP schema
readiness and provider rejection without downgrade. These checks and the integrated suite
support runtime acceptance; they add no Lean theorem. The smaller output cap and measured
CPU completions do not guarantee future requests or other hardware finish within the
per-call deadline.

The execution sandbox requires an environment-only path-discovery shim. Without it,
`lean --print-prefix` fails with `failed to locate application`; with it, the pinned
installation is `/tmp/mathguard-toolchain/lean-4.28.0-linux`. The independently inspected
source, exported symbols and `readlink` disassembly show one operation: only the exact
current process `/proc/<pid>/exe` lookup is delegated to libc as `/proc/self/exe`, with
the original output buffer and length. Other lookups pass through. It changes no Lean
kernel, proof, worker decision or model code. Source SHA-256 is
`8277614c765ba462c38a4ec22a785448d134b1ed8671c7e3e810c4b9ec5e4682`; shared-object SHA-256 is
`20249cd2b2926e3bf7fd23f19f37c5a16c83b2d8ff975dd8346ce6d344ea55dc`.
The sandbox gate uses `PATH=/root/.elan/bin:$PATH LD_PRELOAD=/tmp/mathguard-exepath.so make test`.
The shim is not shipped; ordinary hosts use `make test`. This qualification belongs with
the environment evidence, rather than being hidden in a claim of an unmodified sandbox run.

## Exact theorem to runtime mapping

| Property / source | Actual request-path use | What remains outside the theorem |
|---|---|---|
| Ledger conservation, authorization, exact approval, replay and invariant preservation: `Ledger.lean` | `Worker.dispatch` calls `ledgerStep` for preview/execute | Authentication, canonicalization, clock and approval provenance; publication and crash behavior |
| Reserve/settle/charge/reconfigure invariants: `Budget.lean` | Worker reserve, charge, settle, configure and financial execute | Real provider token/time/cost bounds; dispatch ordering, cancellation and persistence |
| `reserveOptimized_eq`, `budgetStepOptimized_eq` | Optimized reservation is used by the worker | Host selection of limits and ticket lifecycle |
| Trusted-label joins and flow gate: `Flow.lean` | Host session label is passed to worker `flow` | Complete label assignment, arbitrary secrets and noninterference of Python/HTTP |
| `hardDecision`, `storeDecision`, `Decision.combine_executes`, `gate_executes_imp_hard` | Compiled hard/hybrid gate for mediated interactions | Facts produced by detectors; trusted principal/approval Boolean; JSON and output handling |
| Strictness fallback and `gate_mono` | Compiled fallback and restriction composition | Provider quarantine is an additional host control; monotonicity is for fixed typed facts and the specified effective fields |
| `signature_denied`, `artifact_admitted_pinned_safe` | Compiled rule for matching facts and pinned inert-format facts | Complete normalization/signature coverage, hash/byte/header authenticity and safety of the separately running model server |
| G1 valid store, `reload_invalid_keeps`, `no_policy_fail_closed` | Worker decodes/validates ControlPolicy and reloads its private store | Atomic host pairing of policy/feed/budget, file ownership, higher source epochs and durable activation |
| W1 roundtrip/injective projection and account bounds: `Wire.lean` | Worker request decoding uses `Next.fromWire 3` | Raw JSON, duplicate keys, UTF-8, canonical decimal strings, account-name mapping and request-ID encoding |
| C1 composite invariant/commit/noncommit/replay: `Composite.lean` | Built model; **not the function invoked by the worker** | C1 reserves a pending ticket; financial execute reserves and charges immediately. C1 gates even replay; host replay skips new semantic calls |
| P1 historical snapshot/linked evidence: `PolicyHistory.lean` | Built separate model | It is not the host audit schema, worker configuration transition or persistent journal |
| G1 session steps/log/recall | Native model and demo evidence | Host counts attempted requests, emits provider and terminal records, retains bounded windows, and owns session history. It does not execute `sessionRun` or `recall` |
| `ledgerResultUpdate_eq` and volatile IO.Ref wrapper: `Runtime.lean` | Native demonstrator wrapper; production gateway owns a subprocess state | IO atomicity is a runtime assumption; this is not a SQLite or full-stack concurrency proof |
| Optional SQLite command journal: `gateway/state.py`, `engine.py` | Implemented; 33 focused cases within the passing 189-case actual-worker suite, plus real same-journal restart rehearsal | Runtime-tested IO adapter; no new persistence, JSON, authentication or audit refinement theorem |

The financial worker publishes ledger, charged financial-tool budget and next ticket in one
returned pure `State`. Existing component proofs apply to their functions. A new refinement
proof is still needed for that exact composition and for its JSON dispatch branch. A fresh
denial cannot change money; semantic work already performed before that denial remains charged.
“No charge on rejection” is therefore too broad. Exact ledger replay creates no new model or
financial charge; generic SDK admission is not an idempotent external commit.

## Host assumptions and finite controls

The supported perimeter consists of callers that route every relevant boundary through the
gateway/SDK and have no independent authority to bypass it. Server-derived roles/principals,
private worker access, validated policy/feed ownership, a serialized owner and the clock are
trusted host conditions, covered by targeted runtime tests rather than new Lean theorems.

Generic approval binds the original interaction, principal/session, kind/target, policy epoch,
feed version, expiry and single consumption. It cannot clear semantic review/denial. The
current host digest binding also relies on SHA-256 collision resistance on its used domain;
a proof of exact typed binding must preserve canonical bytes or state that assumption.
Schema filtering/redaction can change a tool's argument meaning; the trusted callback must
validate the filtered schema. Filtering a tool result cannot undo an effect already performed.

Supported-pattern PII/secret detection, Unicode/encoded normalization and classifier quality
have finite coverage. Encoded supported sensitive content has a separate host denial even
when PII thresholds are disabled. Neither this guard nor the abstract flow model proves that
every encoded or natural-language secret is found. Model hashes/pins and inert-format checks
are admission checks; the gateway does not prove arbitrary weight-loader safety.
Retained session history is rechecked and sanitized under the current policy before new
provider serialization/dispatch; unsafe cross-entry redaction is withheld. Tests cover
permissive-to-redact/block transitions, financial classifier history and encoded history.

## Persistence acceptance boundary

The runtime implements an **optional, deployment-owned SQLite worker-command journal**,
used by the judge launcher. This scoped contract is **runtime tested**. Completed mutating
commands are replayed through the same compiled worker, with
exact response checking. An intent is durable before worker mutation; completion and its
operation audit are committed together. Incomplete/uncertain intent, corruption or a worker
digest mismatch closes startup. These behaviors have passing targeted and integrated tests;
they are not a new Lean theorem or a proof of hardware durability.
It deliberately rejects uncertain recovery rather than claiming automatic recovery from
every crash. Volatile mode remains a separate deployment mode.

The scoped durable-state claim is accepted against the following tested boundaries:

| Acceptance | Concrete observation / failure injection |
|---|---|
| Exclusive ownership | A second process cannot own the same database; permissions/paths are checked; no duplicated quota owner |
| Reserve before dispatch | A completed durable reservation precedes the first provider request; killing at each boundary never permits an unaccounted call |
| Financial acknowledgment | Returned `COMMITTED` has durable command/result/operation evidence; restart reproduces balances, debits, revision, consumed nonces and financial charge |
| Exact retries after restart | New authenticated owned session, original typed request and reconstructed receipt; no duplicate debit/model call/tool charge |
| Unknown completion | Crash between intent, worker mutation and completion closes recovery without genesis reset or a fabricated receipt |
| Pending calls | Completed reserve without settlement preserves the pending bound and quarantines new dispatch; explicit verified recovery charges it once without refund |
| Identity and integrity | Wrong worker digest/schema, response mismatch, malformed/gapped records and damaged database close startup before dispatch |
| Source configuration | Last-good policy/feed and active version restore coherently; invalid current files cannot reset counters or replace retained valid state |
| Approvals | Outstanding host approvals/sessions are intentionally invalidated or restored with full proofs/tests; newly issued ledger nonces do not collide with consumed nonces |
| Audit separation | Private financial operational transcript is protected; public audit/export contains metadata only, with bounded pagination and monotone IDs |
| Resource/disk bounds | Owned database size checked before SQLite scanning; bounded records/growth/frames, replay deadline checks and per-worker IO deadline; quota rejection is visible and fail closed. The replay cap is not a strict deadline for the entire startup validation |

A local hash chain detects inconsistent edits. Without a protected key/trusted external
anchor, it does **not** establish protection against an owner recomputing the chain or
rolling back to a valid prefix. SQLite transaction success and filesystem durability are
deployment assumptions; crash tests cannot prove all hardware/power-loss behavior. State
restoration does not establish exactly-once arbitrary SDK effects, distributed quotas,
tamper-proof audit or provider GPU cancellation. A persistent operation log is not yet a
proved one-event-per-interaction audit refinement.
Provider/worker/operation records coexist with terminal request events. Requests rejected
before acquiring the serialized handler because it is busy are outside that terminal-event
guarantee; the abstract G1 one-event-per-interaction theorem is not substituted for this host
observation boundary.

## Independent final review gate

1. Inspect the final diff against the source/runtime mapping; do not accept a Python money
   mirror, unchecked worker replacement or weakened original theorem statements.
2. Run the canonical pinned local gate; regenerate the 156-record report if compiled Lean
   changes. Run focused reserve/commit/replay/reload/approval/worker-failure tests first.
3. Run fresh isolated HTTP/SDK, provider failure and persistence crash/restart/concurrency
   scenarios. Inspect sanitized artifacts and source/binary fingerprints independently.
4. Verify actual configured model/weights/license and live verdict/latency evidence when
   available. A local HTTP provider fixture is transport evidence, not live-model accuracy.
5. Match final dashboard, presentation, README and assurance output to the selected volatile
   or persistent mode. Count catalog records and tests accurately; keep empirical and
   pending external acceptance separate.

The specific missing proof tasks and counterexamples are in
[FINAL-HARDENING-HANDOFF.md](../../aristotle/FINAL-HARDENING-HANDOFF.md). Their acceptance requires
checked Lean results; none are asserted proved by this document.
