# Aristotle final-hardening handoff

Status: **proposed proof tasks; no new theorem result**. Target Lean 4.28.0 with pinned
Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`. Work from the final reviewed release
commit and preserve the existing original definitions/target statements. Record its SHA
and each relevant source fingerprint in the submission to Aristotle.

Read `docs/15-FINAL-RELEASE-PLAN.md`,
`docs/verification/RELEASE-ASSURANCE.md`, `Mathguard/Worker.lean`, `Spec.lean`,
`OptimizedBudget.lean`, `Control.lean`, `Wire.lean`, `Composite.lean` and
`PolicyHistory.lean`, together with the final host persistence/approval contract.
The current 156-record catalog remains unchanged. Do not repeat the 35 C1/P1/W1 original
targets, G1 restriction-union/monotonicity, ledger replay, budget preservation or optimized
budget equality merely to inflate the count.

`aristotle/release/RuntimeSpec.lean` supplies concrete, definition-only starting points
outside the production build: `FinancialInvariant`, `financialTicket`, `executeCore`,
typed request/context JSON encoders, `workerFrame`/`Completed`/`replayCompleted`, and full typed generic
approval binding. It has no proof holes and is not substituted into the live worker.
It typechecked independently with `lake env lean aristotle/release/RuntimeSpec.lean` on
the pinned Lean 4.28.0 environment during this handoff. That is a definition typecheck,
not a proof of any target below or evidence that the host executes these new definitions.
The spec-to-runtime correspondence is the first proof obligation, not an assumption that
the model already implements the host. The targets below are deliberately unproved text,
not `sorry` declarations in production. Freeze these definitions only after reviewing
their correspondence to the final runtime.

The release's shared classifier prompt and strict JSON-schema generation request are
empirical/runtime controls, not theorem premises guaranteeing truthful threat detection.
Preserve strict host parsing and conservative fusion of `risk` and `verdict`; a grammar
constraint cannot justify trusting a model's `allow`. The selected development probes
retain a semantic false allow. None of H1–H7 should claim detector completeness, unseen
model quality or a completion-time guarantee from the sample 128-token output cap.

## H1 — exact financial worker transition (first priority)

**Gap.** C1 `compositeStep` leaves a reserved ticket pending and puts gates before replay.
`Worker.dispatch` computes `ledgerStep`, reserves exactly one financial-tool slot, charges
it immediately, and publishes the resulting ledger/budget/next-ticket fields together.
Host semantic/proposer charges have already happened. Prove this exact branch instead of
claiming C1 is a direct refinement.

**Definitions.** Use `Release.executeCore`, `financialTicket`, `FinancialInvariant` and
`executeJson`. Account count is 3. For a future generic account count, first make that
change explicitly reviewed; do not alter the current interface in a proof repair.

**Hypotheses.** `s.initialized = true`, `FinancialInvariant s`; exact typed `Context` and
`Request`. Authentication/clock/semantic provenance are external hypotheses. A valid
worker result is parsed with its declared schema; private worker entry points are not
accessible to agents. For ticket freshness, either derive it from a stronger reachable
state invariant or state `s.nextTicket ∉ s.budget.seen` explicitly.

**Targets.** With `r := executeCore s ctx q`:

1. `FinancialInvariant r.state`.
2. `r.outcome = .committed` iff `ledgerStep s.policy s.ledger ctx q` commits and the
   exact `financialTicket s` reserves and charges successfully.
3. Commit implies `r.state.ledger = (ledgerStep s.policy s.ledger ctx q).state`,
   `r.state.budget.spent 3 = s.budget.spent 3 + 1`, unchanged spent dimensions 0–2,
   unchanged existing pending tickets, and next-ticket increment exactly one.
4. Noncommit implies ledger/budget/next-ticket unchanged by **this financial step**.
   Replay implies no new reservation or charge, independent of new policy/approval expiry.
5. If `Worker.dispatch s (executeJson ctx q) = .ok (s', reply)`, then
   `s' = r.state`; reply reports commit exactly on the committed branch. Map pending
   approval/blocked responses to the nonmutating branch rather than erasing their reason.
6. `Worker.request (requestJson q) = .ok q` and `Worker.context (contextJson ctx) = .ok ctx`.

**Counterexamples to reject.** Publishing ledger before a failed tool reservation;
incrementing next ticket on preview/replay; refunding prior model charges on financial
denial; charging two tool slots; charging zero slots; equating all C1 states to runtime.

**Acceptance.** Prove against the actual worker encoders/dispatch; derive from existing
ledger/budget lemmas and `reserveOptimized_eq`. Export the new pure transition into the
worker only under coordinated review, or retain a proved equality to its exact current
branch. Require native cases for capacity denial, preview, fresh commit, expired exact
replay and conflict, plus an axiom report without new arbitrary axioms.

## H2 — durable command-prefix, financial acknowledgment and restart replay

**Gap.** Current component invariants do not prove a SQLite journal, its durable intent
ordering or restoration. The implemented, runtime-tested contract uses deployment-owned completed worker
commands, exact response replay, atomic command completion/operation audit, and startup
refusal on unresolved intents. This does not automatically recover every crash.

**Definitions.** Extend `Completed` with sequence, version/worker binding and a receipt
projection. `workerFrame` maps actual `Worker.dispatch` errors to the fixed nonmutating
error response used by `Worker.loop`; `replayCompleted` rejects response mismatch.
Define `DurableState` with completed prefix, optional pending intent, fail-closed flag and
the live worker projection. Specify `begin`, `complete`, `crash`, `recover`, and
`acknowledge` transitions. A durable entry must carry the exact command needed for replay;
do not replace exact requests by an unproved hash equality. Keep private financial state
distinct from sanitized audit metadata.

**Hypotheses.** Single exclusive owner; `begin` is durable before mutation/dispatch;
completion/result/operation audit is one atomic store transaction; acknowledged writes
survive the assumed crash model; checked prefix is intact; worker executable/schema match.
Treat SQLite/fsync/OS locking and serialization correctness as explicit implementation
assumptions until a refinement covers them. Cryptographic authenticity/rollback protection
requires an external trusted anchor/key if claimed; a recomputable chain is insufficient.

**Targets.**

1. Successful replay of the empty prefix returns its specified genesis/initial worker;
   replay of concatenated completed prefixes equals sequential replay, when both succeed.
2. Successful replay produces exactly the state obtained by the original accepted worker
   transitions, preserving H1/component invariants and all budget tickets/charges.
3. `acknowledgedCommit id` implies a complete durable entry whose exact principal/request
   and replay-correlated receipt produce the same ledger commit after successful recovery.
4. Exact retry of an acknowledged request after recovery has `.replayed`, no new debit,
   no new financial charge and the original receipt projection; changed fields/principal
   block. The host must use a newly authenticated owned session if sessions are invalidated.
5. An unresolved intent, incompatible worker, malformed/gapped prefix or response mismatch
   yields no recovered execution permit. Failure never returns a fresh genesis as recovery.
6. Recovery of a completed reserve without charge preserves its resource obligation and
   blocks provider dispatch until explicit reconciliation; it does not release uncertainty.

**Counterexamples.** HTTP success before durable completion; only balances restored but
not journal/nonces/quota; silently dropping the final completed entry; transcript replay
using a changed worker; replaying provider HTTP calls instead of private worker commands;
accepting a partially written receipt; restarting at genesis on database parse failure.
Rejecting the entire replay solely because a previously recorded nonmutating command
was rejected, or forgetting its pending reservation after a rejected settlement, are
additional counterexamples.

**Acceptance.** A finite crash model must enumerate each persistence boundary. Tests kill
before/after intent, worker mutation, completion and acknowledgment, and exercise corrupt
records, second owner and digest mismatch. The formal theorem establishes the abstract
transaction contract; separate host tests must connect it to SQLite. Do not advertise
exactly-once external SDK effects or tamper-proof rollback resistance from this theorem.

## H3 — exact generic approval binding and restart nonce safety

**Gap.** G1 receives an `approved : Bool`; it does not prove where that fact came from.
Ledger approval lemmas already bind typed financial requests but do not prove generic
session/content/feed binding or fresh host issuance after restart.

**Definitions.** Use `BoundInteraction`, `GenericApproval`, `genericApprovalValid` and
`consumeGenericApproval`. Define issuance as an owner-authenticated transition with
`executed = false`; admission combines the independently computed gate with approval
validation and budget admission. Preserve all original content fields before redaction.
Extend the ledger host issuance model with a monotone nonce allocator above every consumed
or outstanding nonce. Explicitly invalidate outstanding host sessions/approval references
on restart if they are not persisted.

**Hypotheses.** Server-derived principal/session ownership, trusted owner role, consistent
clock, serialized consumption, exact canonical binding. For the current digest-only host
binding, either retain canonical bytes and prove equality directly or state the explicit
collision-resistance assumption on used values; do not prove SHA-256 globally injective.

**Targets.**

1. `genericApprovalValid a b now = true` implies exact equality of all binding fields,
   `now ≤ a.expires` and `a.used = false`.
2. Changing any field of a valid bound interaction rejects consumption.
3. Successful consume marks the approval used; a second consume fails, including at the
   same timestamp. Expiry is rechecked at final admission after semantic work.
4. Issue leaves effect/ledger/budget-for-effect unchanged; semantic deny/review still
   prevents dispatch regardless of a valid approval.
5. New ledger approval nonce is absent from consumed and outstanding nonces even after
   replay recovery; host sessions/refs declared invalid cannot authorize fresh effects.

**Counterexamples.** Reusing a approval after feed/policy change; approving sanitized text
but executing different original bytes; nonce `len(host approvals)+1` colliding with a
restored consumed nonce; considering balanced model unavailability an owner-overridable
request; marking an external callback complete merely because admission succeeded.

**Acceptance.** Exact-key/provenance refinement to the final host record and targeted
swap/reuse/expiry/race/restart tests. Keep generic tool and ledger approval routes distinct.

## H4 — bounded host-to-worker wire/schema refinement

**Gap.** W1 starts with parsed naturals. It does not prove raw JSON/canonical decimal
strings, unique fields, Unicode normalization, injective string-to-ID encoding or bounded
work. A successful W1 roundtrip does not authenticate a request.

**Definitions.** Specify a bounded UTF-8 byte envelope, unique-key object representation,
canonical decimal grammar (`0` or a nonzero digit followed by digits), exact schema keys,
fixed account catalog, bounded ID alphabet/length and the length-tagged ID encoding.
Define a total `decodeEnvelope : ByteArray → Except DecodeError TypedEnvelope` and its
projection into `Next.WireTransfer`/`Context`. Freeze actual byte/depth/node/item/number
bounds from the final detector/server implementation; do not assume Python JSON is total.

**Hypotheses.** Correct bounded UTF-8/JSON parser refinement or an explicit trusted parser
interface. The formal decoder must actually reject duplicates before information is lost.
An abstract parsed-object proof does not establish raw duplicate-key rejection.

**Targets.** Accepted bytes satisfy every grammar/length/schema bound; decode preserves
all request fields; serialization roundtrip holds on the accepted canonical domain;
distinct valid request IDs produce distinct typed IDs; unknown accounts never clamp;
booleans/floats/exponents/negative/noncanonical numbers fail; work and recursive depth are
bounded by declared limits. Use W1 for the final account-index step, not duplicate it.

**Counterexamples.** `true` accepted as integer 1; duplicated `principal`/amount key;
`01`, `1e3`, surrogates, gigantic integers or deeply nested payloads; dropping an unknown
field; a hash used as exact equality; altered account mapping between approval/execution.

**Acceptance.** Compiled/host decoder correspondence or clearly labeled trusted-parser
boundary, plus adversarial byte-level tests. Distinguish structural acceptance from PII or
attack detection. Proving a model parser alone must not be labeled a verified JSON API.

## H5 — joint policy/feed reload with financial and resource preservation

**Gap.** G1 store generations, source policy epochs, feed versions and ledger policy are
different values. G1/P1 reload theorems do not prove the worker's joint configure branch
or the host's last-good two-file snapshot and persistence envelope.

**Definitions.** `ActiveConfig` contains typed ledger policy, G1 store, budget limit,
source epoch, feed version, effective PII/semantic clamps and snapshot identity. Specify
prepare/validate/activate; no publication before all parsing, G1 validity and budget
reconfiguration succeed. Feed-only activation updates the G1 snapshot without resetting
ledger/budget/ticket counter. Durable recovery restores that same active configuration.
Include retained session content and its checked fact/sanitization projection: changing
policy cannot exempt older messages when they are submitted in a new model request.

**Hypotheses.** Authenticated configuration owner, exact parser/projection, serialized
activation, integrity of persisted accepted config and consistent candidate epoch/version.

**Targets.** Rejected reload leaves active config, ledger, budget and counters unchanged;
accepted reload preserves ledger, spent/pending/seen tickets and next ticket; budget limit
cannot fall below spent+reserved; source epoch/feed version obey their intended strict
ordering; every valid active snapshot passes G1 validity; no initial valid pair means no
execution; approval context becomes stale on relevant config change. Effective-policy
tightening yields `gate_mono` under fixed facts, without claiming arbitrary file edits are
monotone or detector scores stay fixed. Every outbound history item must satisfy the
current typed gate and carry its current permitted sanitized projection; ambiguous
encoded reconstruction rejects dispatch. This target assumes the declared detector facts
and establishes enforcement, not detection completeness.

**Counterexamples.** Publishing a policy before its budget check; reloading to zero spend;
feed update not reaching compiled controls; conflating G1 generation with source epoch;
restoring new policy with old budget/approval records; deleting a signature advertised as
a tightening. Feed invalidity must not silently reset to an empty feed.
Retaining a raw email under thresholds 101/101, tightening to 60/100, then transmitting
that unchanged history to the classifier is a concrete host counterexample.

**Acceptance.** Equality/refinement to actual `Worker.dispatch configure/control_configure`
and host activation ordering; mixed valid/invalid, reduced budget, stale version, feed-only
and restart tests; permissive-to-redact history must be sanitized before new provider
dispatch. Reuse `reconfigure_preserves` and existing G1/P1 facts.

## H6 — provider reservation, observed usage and uncertainty reconciliation

**Gap.** Budget invariants model trusted bounds. They do not establish that a provider is
called only after durable reservation, uses that bound, stops on adapter termination or
reports authentic observed tokens. A timeout must not be treated as successful detection.

**Definitions.** `CallState` with not-dispatched/reserved/dispatched/completed/uncertain/
reconciled stages, exact ticket, configured bound, optional observed usage and quarantine.
Define permitted transitions; dispatch requires an accounted durable ticket; completion
charges full configured bound; unverified cancellation remains uncertain. Explicit
operator recovery confirms upstream stop and charges each unresolved pending ticket once.

**Hypotheses.** Correct caller/serialization, trusted calibrated resource envelope,
operator attestation of upstream stop and clocks. GPU cancellation is an external provider
contract/observation, not a consequence of the Lean budget transition.

**Targets.** Every dispatched call has a unique prior reservation; accounted spent plus
pending never exceeds limits; charge cannot occur twice; unknown completion preserves
the obligation; recovery transfers its full bound from pending to spent without reducing
accounted use; quarantine prevents new provider dispatch even in permissive semantic
fallback; reported over-bound usage triggers closed error/quarantine rather than refund.

**Counterexamples.** Dispatch then reserve; release pending on timeout; retry quarantined
provider automatically; zero-price local call consuming zero tokens/time; inaccurate
reported usage mistaken for a proved bill; double charge on recovery.

**Acceptance.** Trace refinement to the real model-call/finally and recovery path, provider
failure/race/restart tests, independent fields for configured charge and observed usage.
Use existing budget lemmas; actual bound calibration remains measured evidence.

## H7 — sanitized audit projection and real session counter

**Gap.** G1 logs one abstract event per interaction and counts executed steps. Host counts
attempts and emits provider-stage plus terminal events; persisted operation records may
also occur per mutating worker command. Prove that schema instead of asserting equality
to `sessionRun`. P1 stores full model evidence, not a sanitized public export.

**Definitions.** A `Trace` has a bounded attempt ID, trusted principal, config identity,
stage events and exactly one terminal decision. Define metadata-only audit projection,
monotone global event IDs, append operation, bounded/paginated export and attempted-step/
repeat transition. Session history is separately owned by a principal. Model append-only
store and in-memory bounded window as distinct structures.

**Hypotheses.** Instrument every request completion/error path; unique trace/event IDs,
serialized writer, accepted durable transaction abstraction and correctly classified
sanitization inputs. Avoid defining “no secrets” as an arbitrary output predicate supplied
by the caller.

**Targets.** One terminal event per attempt admitted to the serialized handler
(provider/operation records do not violate this); pre-admission busy responses need a
separately stated observation boundary. Every record carries the config used for its stage;
prefixes remain intact
under append; export pages are ordered/bounded with explicit retention/drop metadata;
export fields cannot include raw prompt/output/credentials/approval refs by construction;
request attempt count never decreases and no session dispatch exceeds its attempt cap;
history lookup checks owner and cannot return another principal's entries.

**Counterexamples.** Logging raw exception/user URL/content; falsely labeling the bounded
2000-event window durable append-only; replaying audit as requests; a denied attempt not
counting toward host repetition/attempt limits; proving ownership for `recall` but using
an unrelated host dict without a refinement.

**Acceptance.** Typed metadata schema/projection, host append/terminal-flow correspondence,
parser/auth rejection and late provider-error cases, bounded export/concurrency tests.
Do not claim a malicious-store-resistant forensic log without its trust assumptions.

## Submission and proof acceptance protocol

1. Send H1 first; it has concrete compiled definitions and closes the most direct
   model/runtime composition gap. Freeze H2–H7 against the final implemented host contract.
2. Provide definitions, exact target statements, relevant existing lemmas and counterexample
   tests. Returned “proofs” must preserve statements/semantics; a weaker hypothesis that
   simply assumes the desired property is not a solution.
3. Build independently on the pinned environment. No `sorry`, `admit`, arbitrary axiom,
   `native_decide`, skipped kernel checking or hidden unsafe proof shortcut in production.
   Inspect a fresh `#print axioms` for every admitted result.
4. Update the catalog only for separately checked admitted results; report definition-only
   typechecks and native examples separately. Keep authentication/parser/clock/SQLite/provider
   assumptions visible in the assurance mapping and final presentation.
5. A proof of restriction composition cannot establish detector completeness. Actual local
   model quality, unseen corpus provenance and latency remain empirical/external work.

The full-stack release still requires targeted host/crash/concurrency tests and the independent
acceptance gate in `RELEASE-ASSURANCE.md`. This handoff does not authorize a production
semantic change, infer completed Aristotle work or replace the final team review.
