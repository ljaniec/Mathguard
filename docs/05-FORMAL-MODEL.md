> **Current checkpoint:** the 55 baseline targets and five additional equality targets have been independently checked with the pinned toolchain. The gateway/worker runtime is now integration-tested. Earlier request-pack descriptions below are historical; current scope and open work are in `07-TEAM-INTEGRATION-CONTRACT.md` and `10-REQUIREMENTS-RECOVERY.md`.

# Mathguard model-v1 — exact formal specification

## Purpose and assurance claim

Prove properties of **concrete executable transition functions**, then connect those functions to the gateway and atomic executor. The model must be small enough to review and prove during a hackathon and strong enough to distinguish a real action supervisor from an LLM filter.

No finite model is a “perfect” specification of an entire banking/security system. The goal is a precise, reviewed, machine-checked model with explicit assumptions, useful accepted behavior, and a visible runtime connection. Do not substitute a stronger marketing phrase for missing proofs.

`aristotle/Spec.lean` defines three independent kernels. The three request files state the desired propositions with proof holes. They are **uncompiled requests**, not verified code. Every request can be read without access to another repository. A compatible pinned Mathlib workspace is needed to check them.

## A. Closed ledger kernel

### A1. Universes and units

Let `n : Nat`; accounts are `Fin n`. All universal ledger theorems quantify over arbitrary `n`, including the degenerate empty/single-account cases. Nontrivial positive examples use `n = 3`.

Money is a natural-number count of **minor units in one fixed currency, PLN**. `2500` means 25 PLN. Natural numbers alone do not prove correctness: Lean's `Nat` subtraction truncates, so an unguarded oversized debit can destroy funds. Admission requires both sufficient balance and distinct source/destination; conservation must be proved from those preconditions.

Principals, request IDs, policy epochs, revisions, approval nonces, and times use `Nat` in the pure model. The runtime maps bounded canonical opaque identifiers injectively into those identifiers, or changes the formal types consistently before freezing. No floating-point money, exchange rate, overdraft, fee, interest, external deposit/withdrawal, partial settlement, chargeback, or distributed consensus is modeled.

### A2. State, genesis, and journal

`Ledger n` contains:

| Field | Meaning |
|---|---|
| `balances : Fin n → Nat` | Current spendable balances |
| `debited : Fin n → Nat` | Cumulative outgoing transferred amount per account since genesis |
| `revision : Nat` | Number of committed transfers |
| `journal : List (Commit n)` | Ordered append-only transfer receipts |
| `consumedApprovals : List Nat` | Used high-value approval nonces, in commit order |

Genesis supplies opening balances `g`. Initial journal, consumed approvals, counters, and revision are empty/zero. Total funds are

\[
  T(b)=\sum_{i\in\operatorname{Fin}(n)} b(i).
\]

A committed transfer is the canonical request plus authenticated principal plus optional approval nonce. Each receipt represents exactly two money postings, `−amount` at source and `+amount` at destination. Thus the paired posting sum is zero. The implementation may store explicit debit/credit rows, but must preserve this exact pairing and atomicity. The current source file represents pairing through one transfer receipt and its update function; it does not yet define a general-purpose double-entry accounting chart.

`replayBalances g journal` folds the same `applyTransfer` definition over journal requests. `replayDebits journal` folds outgoing amounts by source. It is not permissible to prove conservation for one update function and use a different function for journal reconstruction.

### A3. Request and trusted context

`Request n` = `(id, source, destination, amount, expectedRevision, policyEpoch)`.

`Context n` = `(principal, now, approval?)`. Context is **constructed by trusted adapters**: principal comes from authenticated credentials; time from the trusted gateway clock; approval from the protected approval store. The LLM cannot create effective approvals merely by constructing a Lean value or JSON object. The pure model proves what the supplied context implies; authenticity of the supplying component is an assumption until separately formalized.

`Approval n` = `(nonce, principal, boundRequest, expires)`. `boundRequest` is the **entire typed request**, including ID, amount, account endpoints, revision, and epoch. Model equality is structural exact equality, not hash equality or an agent's explanation.

Owner approval is valid when:

\[
\begin{aligned}
  &a.\text{boundRequest}=q,\\
  &a.\text{principal}=ctx.\text{principal}=p.\text{owner}(q.\text{source}),\\
  &ctx.\text{now}\le a.\text{expires},\\
  &a.\text{nonce}\notin s.\text{consumedApprovals}.
\end{aligned}
\]

Expiry is inclusive in model-v1. Use the same boundary at runtime. The threshold rule is also inclusive: amount **at or above** threshold requires approval. Lower-value supplied approvals are ignored and not consumed by this ledger kernel. Optional semantic review on lower-value actions belongs to the outer gate, described separately; do not silently conflate it with the ledger's threshold theorem.

### A4. Policy

`Policy n` contains epoch, account owner function, transfer-enabled predicate by principal, beneficiary predicate by principal/destination, per-transfer maximum, cumulative debit cap per source, and approval threshold.

These functions are trusted catalog interpretations. Authorization means enforcement of the configured predicate, not independent verification that the operator chose a good policy. Ownership does not change merely because an agent claims to be Alice. Demo caps do not reset by calendar date.

Policy changes are external inputs at step boundaries. Every fresh commit checks its request epoch against the active policy. Accounting invariants do not depend on a fixed policy, so their one-step preservation theorem applies across arbitrary policy changes. The supplied `ledgerRun` uses a **fixed** policy for simplicity; a variable-policy trace can be added by folding tuples `(policy, context, request)` and applying the same one-step lemma. Do not describe the fixed-policy source definition as a variable-policy theorem until that extension is proved.

### A5. Admission predicate — explicit operational preconditions

For a request whose ID has no prior committed receipt:

1. `q.policyEpoch = p.epoch`.
2. `q.expectedRevision = s.revision`.
3. `p.transferEnabled ctx.principal = true`.
4. `p.owner q.source = ctx.principal`.
5. `p.beneficiaryAllowed ctx.principal q.destination = true`.
6. `q.source ≠ q.destination`.
7. `0 < q.amount`.
8. `q.amount ≤ p.maxTransfer`.
9. `q.amount ≤ s.balances q.source`.
10. `s.debited q.source + q.amount ≤ p.debitCap q.source`.
11. `q.amount < p.approvalThreshold` OR `approvalOK = true`.

**The guard does not contain `LedgerInvariant nextState`.** Including the desired conclusion as a precondition would make a preservation theorem uninformative and usually provide no independently implemented operational decision.

### A6. Pure transition function

`ledgerStep p s ctx q` first searches for a committed receipt with the same ID.

- Existing ID, exact same request **and** same principal: outcome `replayed`, state unchanged. Return only the permitted minimal old receipt; do not expose another principal's data.
- Existing ID but a different request or principal: `blocked`, state unchanged.
- Fresh ID with admission true: `committed`; update balances/counters, append one receipt, increment revision by one, append used high-value approval nonce if needed.
- Fresh ID with admission false: `blocked`, state unchanged.

Exact retries may replay even after the current epoch/revision changes. They do not execute a new transfer and do not establish current-policy authorization to commit. The API must distinguish replay from commitment. A caller whose real authentication has expired fails before this pure transition.

For distinct source `a`, destination `b`, and amount `m`:

\[
 b'(i)=\begin{cases}
 b(i)-m & i=a,\\
 b(i)+m & i=b,\\
 b(i) & \text{otherwise.}
 \end{cases}
\]

`debited'(a)=debited(a)+m`; other debit counters unchanged. Financial balances have no separate pending reservation: a pending approval is not a promise that funds will remain available. Hard predicates are rechecked at commitment.

### A7. Ledger invariant

`LedgerInvariant g s` is the conjunction:

1. `total s.balances = total g`.
2. `replayBalances g s.journal = s.balances`.
3. Journal request IDs have no duplicates.
4. `s.revision = s.journal.length`.
5. `replayDebits s.journal = s.debited`.
6. `s.consumedApprovals = s.journal.filterMap approvalNonce`.
7. Consumed approval nonces have no duplicates.

Natural-number representation ensures balances are nonnegative, but the important nontrivial property is **exact debit plus conservation**, not merely `0 ≤ balance`. Current policy caps are fresh-commit obligations rather than global state invariants: lowering a cap can make historical usage exceed the new cap without invalidating old accounting history.

### A8. Theorem targets and proof structure

| Target | Why it matters |
|---|---|
| `applyTransfer_frame` | Other accounts are unchanged |
| `applyTransfer_exact` | No truncated/incorrect source debit; exact beneficiary credit |
| `applyTransfer_conserves` | Internal transfer cannot create/destroy total funds |
| `ledger_initial_invariant` | The genesis is actually valid |
| `fresh_commit_preconditions` | Commit implies real guard checks and fresh ID |
| `fresh_commit_authorized` | Debit source owner, capability, beneficiary enforced |
| `fresh_commit_versions` | Fresh effects require exact revision/epoch |
| `fresh_commit_caps` | Per-transfer and cumulative debit restrictions enforced |
| `high_value_exact_approval` | Approval cannot be transplanted to changed transfer |
| `noncommit_no_mutation` | Rejection/replay cannot secretly change financial state |
| `duplicate_no_mutation` / exact/conflict variants | At-most-once financial effect for committed IDs |
| `ledger_step_invariant` | Universal one-step preservation from any invariant state |
| `ledger_trace_invariant` | Arbitrary finite proposal sequences preserve accounting |
| `ledger_trace_authorized` | Every receipt reachable from genesis enforces the fixed policy's owner/capability/beneficiary/epoch |
| `stale_revision_not_committed` | Stale snapshots cannot authorize new effects |
| `reused_high_value_approval_not_committed` | Used nonce cannot authorize a fresh high-value commit |
| `serial_same_revision_not_both_committed` | After one commit, another request at the old revision cannot commit |
| Positive/rejection/retry witnesses | Exclude deny-all/vacuous “safety” |

Proof route: isolate source/destination in finite sums; use sufficient-funds arithmetic for `Nat.sub_add_cancel`; prove lookup failure implies fresh mapped ID; use append/fold lemmas for journal reconstruction; derive used-nonce freshness from admission; use list induction for trace preservation. `simp`, `omega`, and finite-sum lemmas should suffice. Extra helpers are allowed; semantic weakening is not.

The serial-revision theorem is a property of the sequential atomic transition model. It is **not** a theorem about arbitrary database interleavings. The adapter must serialize/revalidate real commits. Failed candidates may later become valid with a new request/context; rejected IDs are not permanent commit records.

### A9. Concrete example

Genesis Alice/Bob/Merchant: `(100000, 20000, 0)`. Owner IDs `(1,2,3)`. Epoch `7`, revision `0`, max transfer `50000`, Alice debit cap `75000`, threshold `10000`, now `100`.

Request `17`: Alice → Bob, `2500`, revision `0`, epoch `7`, principal `1`, no approval. It must commit to `(97500, 22500, 0)`, revision `1`, one receipt. Exact retry replays without mutation. Overspend `100001` blocks. Additional runtime fixtures isolate each guard so an overspend test does not pass merely because it also violates the per-transfer cap.

For a high-value witness, use a new request at the correct revision, amount `10000`, and a trusted approval binding the complete request with an unused nonce and expiry above now. Add both positive and boundary tests for this path during implementation.

## B. Resource-budget kernel

### B1. Quantities and state

Resources are a four-component vector indexed by `Fin 4`:

`0 = external API cost micros`, `1 = tokens`, `2 = compute milliseconds`, `3 = tool-call units`.

`Usage = Resource → Nat`. Componentwise order is `a ≤ b` iff `∀ r, a(r) ≤ b(r)`.

`Budget` contains `limit`, `spent`, pending tickets, and all previously admitted ticket IDs (`seen`). A ticket has a unique ID and conservative resource upper-bound vector. Reserved usage is the componentwise sum of all pending bounds. `seen` never shrinks, even when a ticket settles, so a settled ID cannot be reused.

Invariant:

\[
  \forall r,\quad spent(r)+reserved(r)\le limit(r),
\]

plus unique pending IDs, unique seen IDs, and every pending ID belonging to `seen`.

### B2. Events

- **Reserve:** reject seen ID or any component that would exceed `spent + reserved + bound ≤ limit`; otherwise append ticket and its ID. Reserve before dispatch, atomically.
- **Settle:** find pending ticket; reject missing ID or actual usage above its bound; otherwise remove that unique ticket and add actual usage to spent. Seen IDs remain.
- **Charge full bound:** cancellation/unknown usage settles conservatively at its reserved bound. This is the default unknown-billing behavior; no unconditional “refund all” event exists.
- **Reconfigure:** accept new limits only when current spent plus reserved fits each new limit. Preserve all usage and IDs.
- Rejected event returns old state in `budgetStep`.

In runtime, a call also needs a positive call slot, an allowed model/tool, a queue/concurrency limit, and a conservative bound derived by the gateway. The mathematical budget kernel proves accounting; it does not authenticate bounds supplied by a caller. Never allow the agent to reserve zero and then make an unbounded call.

### B3. Theorems

Initial validity; reserve preservation and exact reservation delta; reserve denial above any component limit; seen-ID denial; settle preservation and exact removal/charge; no second settlement; full-bound charge preservation; safe reload preservation; event and finite-trace preservation; one accepted reservation plus oversubscription witness.

Concurrent calls are represented as a serial sequence of atomic admissions. Two calls each reserving six units under limit ten cannot both be admitted. Runtime atomic reservation tests must establish that the database adapter realizes this sequence. Across session and global buckets, use one atomic all-or-none reservation transaction or a checked equivalent; the current formal kernel is one bucket.

Provider actual usage **must not exceed** the conservative bound for a strict real-consumption guarantee. If that assumption fails, `settle` rejects but cannot undo an external bill. Show the distinction between accounted bounds and real provider compliance. Process timeouts require actual termination/cancellation, not only an abandoned await. Prices, tokenizers, remote provider contract, and host clock are trusted deployment inputs.

## C. Information-flow and hybrid-composition kernel

### C1. Two-dimensional label lattice

Confidentiality = `Fin 3`: `0 public`, `1 confidential`, `2 secret`.

Trust/provenance = `Fin 2`: `0 trusted`, `1 external_untrusted`.

`Label = (confidentiality, trust)` with componentwise order and componentwise `max` join. External untrusted text can be public; an internally trusted statement can be confidential. Do not collapse the two axes.

Context joins all observed labels. Whole-context conservative propagation means generated output retains the maximum confidentiality/taint of every input available to the model. This can overblock; that is preferable to falsely claiming fine-grained token provenance in a hackathon.

### C2. Output gate

A sink has confidentiality clearance and a Boolean permission to accept untrusted data. `flowAllowed label sink` iff confidentiality does not exceed clearance and either trust is trusted or the sink accepts untrusted data.

Examples: secret/untrusted → public sink is denied; public/trusted → public sink is allowed; secret/untrusted → internal secret-clearance sink accepting untrusted is allowed. The latter is not permission to execute instructions from the data. Execution capabilities remain separate.

Model inputs, exports, log endpoints, UI audiences, and tool arguments are sinks. Label the **entire generated context/output**, including tool arguments; otherwise a secret could flow through an LLM-generated string with a freshly assigned public label. A new session must not receive sensitive memory with public labels.

There is no formal declassification operation in model-v1. Regex removal of obvious strings does not prove the rest of a generated sentence is public. A separately reviewed structured projection may be added with an explicit release policy; the base proofs do not include it.

### C3. Semantic composition

For a fixed proposed effect `e`, hard and semantic permissions are predicates. Final allowed effects:

\[
   Allowed(e) = Hard(e)\land Semantic(e).
\]

This proves `Allowed ⊆ Hard`. If a semantic policy tightens (`NewSemantic ⊆ OldSemantic`), final effects also tighten. The Boolean special case is conjunction and proves hard false cannot be overridden by semantic true.

Do not impose a severity chain `ALLOW < ASK < REDACT < BLOCK`: approval adds a prerequisite; redaction creates a different output; refusal prevents an effect. Model them as separate gateway branches whose eventual executed effect must pass the same hard gate.

### C4. Claim limits

These are label-gate and composition proofs, **not full noninterference**. They assume trustworthy source labels and propagation. They do not address covert channels via timing, errors, call counts, destination choice, or statistical correlations. Nor do they prove prompt-injection detection accuracy. A semantic false negative still cannot authorize an effect the hard policy forbids; it may permit a harmful effect inside an overly broad hard permission set. Restrict capabilities accordingly.

## D. Connection to deployed software

### D1. Refinement contract

Preferred execution chain:

1. Trusted strict parser maps accepted canonical bytes to exactly one typed request/context/policy/state.
2. Compiled Lean function returns a typed result from the reviewed definitions.
3. Private executor commits precisely that next state at the revision that was checked.
4. Complete mediation prevents all alternative financial writers available to the agent.

The model proves pure functions. Runtime confidence additionally relies on parser correctness, Lean compiler/runtime, process boundary, store atomicity, access restrictions, policy/approval provenance, and matching release versions. Differential tests exercise these assumptions but do not prove them. A separately implemented Python ledger is **not automatically formally verified** because a corresponding Lean model exists.

### D2. Deployment assumptions registry

| Assumption | Runtime mechanism | Evidence / remaining limit |
|---|---|---|
| Authenticated principal is genuine | Gateway verifies credential on every action | Positive/negative identity tests; auth implementation unproved |
| Approval context is authentic | Protected owner-only issuance/resolution | Forge/substitution/expiry/reuse tests; crypto/auth unproved |
| Policy/labels are trusted | Operator-only catalog, schema, snapshots | Unauthorized update and reload tests |
| Full mediation | Agent lacks raw executor/provider/store access | Direct-bypass tests and deployment inspection |
| Atomic linearized commits | Transaction + revision CAS + unique IDs | Concurrency/crash tests; database unproved |
| Exact serialization | Canonical integer/account/ID mapping | Boundary and differential vectors; parser unproved |
| Same transition semantics | Lean worker from recorded source hash | Build manifest + worker vectors; compiler/runtime trusted |
| Resource upper bounds valid | Token limits/deadline/price schedule | Provider-bounded tests; external compliance assumed |
| No declassification bypass | Conservative whole-context joins | Generated-argument and memory-flow tests |
| Model environment trusted | Pinned toolchain/imports, proof audit | Axiom and definition review; fresh checking |

### D3. Proof verification rules

No release proof may use `sorry`, `admit`, arbitrary new axioms, `unsafe` loopholes, declaration replacement, kernel-skip settings, or native-evaluation shortcuts that enlarge trust unnoticed. In particular, do not use `native_decide`/`decide +native` for headline theorems. Axiom outputs and source/import manifests must be inspected, not just an exit code. Standard logical axioms such as `propext`, `Quot.sound`, and `Classical.choice` can be accepted only when disclosed; `sorryAx` and compiler-trust evidence are rejected for the kernel-only proof lane.

Review theorem **meaning** independently of proof elaboration. Lean checking proves the actual formal statement, not an intended English claim. Keep proof-generation plugins and imports pinned; do not run arbitrary untrusted metaprograms in the production service. Additional independent checking can strengthen trust when available, but no claim of independent verification is made here.

## E. Countermodels and mutation requirements

Use these to catch specification mistakes before celebrating proofs:

| Weakened mechanism | Counterexample |
|---|---|
| Remove sufficient-funds guard | Balance 3; debit 5; credit 5: truncated source 0, total becomes 5 instead of 3 |
| Permit same source/destination with current update | Source balance 10, transfer 2 to itself: first branch yields 8 and destroys 2 |
| Trust caller principal | Attacker claims Alice and debits her account |
| Bind approval only to amount | Change beneficiary while reusing legitimate receipt |
| Remove revision guard | Two plans from old balance commit after another action, against stale intent |
| Execute duplicate ID again | Response loss and retry cause a second debit |
| Ignore pending reservations | Two calls reserve 6 each against limit 10 |
| Release unknown call at zero cost | Timed-out remote call continues consuming resources while local budget appears free |
| Check only outgoing literal secret patterns | LLM paraphrases a confidential statement; no literal secret match but sensitive output leaves |
| Use public label on generated tool args | Confidential model context produces exfiltration arguments marked public |
| Let semantic safe override hard deny | Classifier mistake authorizes forbidden payment/export |
| Reject every operation | Safety true but no usable application; positive witnesses fail |

The source invariants are independent specifications; do not repair a failed theorem by weakening the invariant until a broken implementation satisfies it. When a goal is genuinely false, return the smallest counterexample, explain the intended semantic repair, and require a reviewed model-version change.

## F. Extensions after the hackathon

Possible later work: variable-policy trace theorem; history-level authorization under policy snapshots; verified serialization/refinement; structured declassification/noninterference; bounded liveness for authorized workflows; hierarchical session/global budget transaction proof; deposits/withdrawals via explicitly balanced external accounts; temporal caps; more general supervisory-control synthesis. None is required to make the model-v1 PoC useful, and none may be claimed before definition, proof, and runtime integration.

