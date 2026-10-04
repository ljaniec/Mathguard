import RuntimeSpec
import Mathguard.Ledger
import Mathguard.Budget

/-!
# H1 — exact financial worker transition

Checked proofs for target H1 of `aristotle/FINAL-HARDENING-HANDOFF.md`, stated against the
unchanged definition-only model `aristotle/release/RuntimeSpec.lean` (`executeCore`,
`financialTicket`, `FinancialInvariant`, `requestJson`, `contextJson`, `executeJson`) and the
production adapter `Mathguard/Worker.lean` (`Worker.dispatch`, `Worker.request`,
`Worker.context`, `Worker.result`).

## Null handling

`Worker.context` recognizes an absent approval by a structural pattern match on
`Json.null` (`Worker.approvalOpt`), so the decoder/dispatch correspondence results need no
JSON-null-test fidelity assumption. The stated invariant hypotheses still apply. (An earlier
version used the `partial` `BEq Json` test, which is opaque to the logic and forced an
explicit runtime hypothesis.)

Nothing here covers authentication, clock provenance, semantic/provider charges made by
the host before the worker call, the host's persistence, or the bytes-to-`Json` parser.
-/

namespace Mathguard.Release
open Lean Mathguard

/-! ## Reply classification -/

/-- Reply tags emitted by `Worker.dispatch` for each `executeCore` outcome. A blocked step
is reported either as `BLOCKED` or as `PENDING_APPROVAL`; both are nonmutating, and the
reason string is kept in the reply rather than erased. -/
def ExecuteReplyTag : LedgerOutcome → String → Prop
  | .committed, tag => tag = "COMMITTED"
  | .replayed, tag => tag = "REPLAYED"
  | .blocked, tag => tag = "BLOCKED" ∨ tag = "PENDING_APPROVAL"

/-- A reply tag is `COMMITTED` exactly for the committed outcome. -/
theorem executeReplyTag_committed_iff {o : LedgerOutcome} {tag : String}
    (h : ExecuteReplyTag o tag) : tag = "COMMITTED" ↔ o = .committed := by
  cases o with
  | committed => simpa [ExecuteReplyTag] using h
  | replayed => simp only [ExecuteReplyTag] at h; subst h; simp
  | blocked => rcases h with rfl | rfl <;> simp

/-- The worker command for a dry-run of the same request; not part of `RuntimeSpec`. -/
def previewJson (ctx : Context 3) (q : Request 3) : Json := Json.mkObj [
  ("op", toJson ("preview" : String)), ("context", contextJson ctx),
  ("request", requestJson q)]

/-! ## Budget helpers -/

/-- After a successful reservation, charging the same ticket at its bound always succeeds. -/
theorem chargeBound_after_reserve_isSome {b b₁ : Budget} {t : Ticket}
    (h : reserve b t = some b₁) : (chargeBound b₁ t.id).isSome := by
  obtain ⟨-, rfl⟩ := (reserve_eq_some_iff b b₁ t).1 h
  obtain ⟨t', ht'⟩ : ∃ t', (b.pending ++ [t]).find? (fun x => x.id == t.id) = some t' := by
    rw [← Option.isSome_iff_exists, List.find?_isSome]
    exact ⟨t, by simp⟩
  simp [chargeBound, settle, ht', usageLE]

/-- Exact effect of reserve-then-charge on an invariant budget: the ticket is recorded as
seen, its full bound is added to `spent`, and the pending list returns to what it was. -/
theorem reserve_then_charge {b b₁ : Budget} {t : Ticket} (hb : BudgetInvariant b)
    (h : reserve b t = some b₁) :
    chargeBound b₁ t.id =
      some { b with spent := fun r => b.spent r + t.bound r, seen := b.seen ++ [t.id] } := by
  obtain ⟨⟨hfresh, -⟩, rfl⟩ := (reserve_eq_some_iff b b₁ t).1 h
  have hne : ∀ x ∈ b.pending, x.id ≠ t.id := fun x hx he => hfresh (he ▸ hb.2.2.2 x hx)
  have hfind : (b.pending ++ [t]).find? (fun x => x.id == t.id) = some t := by
    rw [List.find?_append, List.find?_eq_none.2 (by simpa using hne)]
    simp
  have hfilter : (b.pending ++ [t]).filter (fun x => x.id != t.id) = b.pending := by
    rw [List.filter_append, List.filter_eq_self.2 (by simpa using hne)]
    simp
  simp [chargeBound, settle, hfind, usageLE, hfilter]

/-! ## `executeCore` case lemmas -/

section Core

variable (s : Worker.State) (ctx : Context 3) (q : Request 3)

/-- `executeCore` on a noncommitting ledger step. -/
theorem executeCore_of_not_committed
    (h : (ledgerStep s.policy s.ledger ctx q).outcome ≠ .committed) :
    executeCore s ctx q = { state := s, outcome := (ledgerStep s.policy s.ledger ctx q).outcome } := by
  simp [executeCore, h]

/-- `executeCore` when the ledger commits but the financial ticket cannot be reserved. -/
theorem executeCore_of_reserve_none
    (h : (ledgerStep s.policy s.ledger ctx q).outcome = .committed)
    (hr : reserveOptimized s.budget (financialTicket s) = none) :
    executeCore s ctx q = { state := s, outcome := .blocked } := by
  simp [executeCore, h, hr]

/-- `executeCore` when the ledger commits and the ticket reserves and charges. -/
theorem executeCore_of_reserve_charge {b₁ b₂ : Budget}
    (h : (ledgerStep s.policy s.ledger ctx q).outcome = .committed)
    (hr : reserveOptimized s.budget (financialTicket s) = some b₁)
    (hc : chargeBound b₁ (financialTicket s).id = some b₂) :
    executeCore s ctx q =
      { state := { s with ledger := (ledgerStep s.policy s.ledger ctx q).state, budget := b₂,
                          nextTicket := s.nextTicket + 1 },
        outcome := .committed } := by
  simp only [financialTicket] at hr hc
  simp [executeCore, h, hr, hc, financialTicket]

/-- The charged budget on the committing branch, written out explicitly. -/
def chargedBudget (s : Worker.State) : Budget :=
  { s.budget with spent := fun r => s.budget.spent r + (financialTicket s).bound r,
                  seen := s.budget.seen ++ [s.nextTicket] }

/-! ## H1 targets 2–4: outcome and state of `executeCore` -/

/-- **H1.2.** `executeCore` commits exactly when the ledger step commits and the exact
financial ticket both reserves and charges. No invariant is needed. -/
theorem executeCore_committed_iff :
    (executeCore s ctx q).outcome = .committed ↔
      (ledgerStep s.policy s.ledger ctx q).outcome = .committed ∧
        ∃ reservedBudget chargedBudget,
          reserveOptimized s.budget (financialTicket s) = some reservedBudget ∧
          chargeBound reservedBudget (financialTicket s).id = some chargedBudget := by
  by_cases h : (ledgerStep s.policy s.ledger ctx q).outcome = .committed
  · cases hr : reserveOptimized s.budget (financialTicket s) with
    | none => simp [executeCore_of_reserve_none s ctx q h hr]
    | some b₁ =>
        cases hc : chargeBound b₁ (financialTicket s).id with
        | none =>
            rw [reserveOptimized_eq] at hr
            have := chargeBound_after_reserve_isSome hr
            simp [hc] at this
        | some b₂ => simp [executeCore_of_reserve_charge s ctx q h hr hc, h, hc]
  · rw [executeCore_of_not_committed s ctx q h]
    simp [h]

/-- **H1.2, capacity form.** For an invariant budget and a fresh next ticket, the
financial reservation succeeds exactly when one more tool-call slot fits. -/
theorem executeCore_committed_iff_capacity (hb : BudgetInvariant s.budget)
    (hfresh : s.nextTicket ∉ s.budget.seen) :
    (executeCore s ctx q).outcome = .committed ↔
      (ledgerStep s.policy s.ledger ctx q).outcome = .committed ∧
        s.budget.spent 3 + reserved s.budget 3 + 1 ≤ s.budget.limit 3 := by
  rw [executeCore_committed_iff]
  refine and_congr_right fun _ => ?_
  constructor
  · rintro ⟨b₁, -, hr, -⟩
    rw [reserveOptimized_eq] at hr
    have := ((reserve_eq_some_iff _ _ _).1 hr).1.2 3
    simpa [financialTicket] using this
  · intro hcap
    have hres : reserve s.budget (financialTicket s) =
        some { s.budget with pending := s.budget.pending ++ [financialTicket s],
                             seen := s.budget.seen ++ [(financialTicket s).id] } := by
      refine (reserve_eq_some_iff _ _ _).2 ⟨⟨hfresh, fun r => ?_⟩, rfl⟩
      by_cases h3 : r = 3
      · subst h3; simpa [financialTicket] using hcap
      · simpa [financialTicket, h3] using hb.1 r
    obtain ⟨b₂, hc⟩ := Option.isSome_iff_exists.1 (chargeBound_after_reserve_isSome hres)
    exact ⟨_, b₂, by rw [reserveOptimized_eq, hres], hc⟩

/-- **H1.3, exact state.** On commit (and an invariant budget) the published state is the
ledger step's state, the budget with exactly the financial ticket charged, and the next
ticket incremented by one; policy, controls and the initialization flag are unchanged. -/
theorem executeCore_commit_state (hb : BudgetInvariant s.budget)
    (h : (executeCore s ctx q).outcome = .committed) :
    (executeCore s ctx q).state =
      { s with ledger := (ledgerStep s.policy s.ledger ctx q).state,
               budget := chargedBudget s, nextTicket := s.nextTicket + 1 } := by
  obtain ⟨hl, b₁, b₂, hr, hc⟩ := (executeCore_committed_iff s ctx q).1 h
  rw [executeCore_of_reserve_charge s ctx q hl hr hc]
  rw [reserveOptimized_eq] at hr
  rw [reserve_then_charge hb hr] at hc
  cases hc
  rfl

/-- **H1.3.** Field-by-field consequences of a commit. Exactly one tool-call slot is
charged; cost, tokens and compute are untouched; the pending tickets are exactly the
previous ones (none is created or released); the next ticket increases by one. -/
theorem executeCore_commit_exact (hb : BudgetInvariant s.budget)
    (h : (executeCore s ctx q).outcome = .committed) :
    let r := executeCore s ctx q
    r.state.ledger = (ledgerStep s.policy s.ledger ctx q).state ∧
    r.state.budget.spent 3 = s.budget.spent 3 + 1 ∧
    (∀ i : Resource, i ≠ 3 → r.state.budget.spent i = s.budget.spent i) ∧
    r.state.budget.pending = s.budget.pending ∧
    r.state.budget.seen = s.budget.seen ++ [s.nextTicket] ∧
    r.state.budget.limit = s.budget.limit ∧
    r.state.nextTicket = s.nextTicket + 1 ∧
    r.state.policy = s.policy ∧ r.state.controls = s.controls ∧
    r.state.initialized = s.initialized := by
  intro r
  have hs := executeCore_commit_state s ctx q hb h
  simp only [r, hs]
  simp +contextual [chargedBudget, financialTicket]

/-- **H1.4.** A noncommitting step publishes nothing: the whole worker state, hence its
ledger, budget and next ticket, is unchanged. -/
theorem executeCore_noncommit_unchanged (h : (executeCore s ctx q).outcome ≠ .committed) :
    (executeCore s ctx q).state = s := by
  by_cases hl : (ledgerStep s.policy s.ledger ctx q).outcome = .committed
  · cases hr : reserveOptimized s.budget (financialTicket s) with
    | none => simp [executeCore_of_reserve_none s ctx q hl hr]
    | some b₁ =>
        have hr' := hr
        rw [reserveOptimized_eq] at hr'
        obtain ⟨b₂, hc⟩ := Option.isSome_iff_exists.1 (chargeBound_after_reserve_isSome hr')
        simp [executeCore_of_reserve_charge s ctx q hl hr hc] at h
  · simp [executeCore_of_not_committed s ctx q hl]

/-- `executeCore` replays exactly when the ledger step replays. -/
theorem executeCore_replayed_iff :
    (executeCore s ctx q).outcome = .replayed ↔
      (ledgerStep s.policy s.ledger ctx q).outcome = .replayed := by
  by_cases hl : (ledgerStep s.policy s.ledger ctx q).outcome = .committed
  · rw [hl]
    cases hr : reserveOptimized s.budget (financialTicket s) with
    | none => simp [executeCore_of_reserve_none s ctx q hl hr]
    | some b₁ =>
        rw [reserveOptimized_eq] at hr
        obtain ⟨b₂, hc⟩ := Option.isSome_iff_exists.1 (chargeBound_after_reserve_isSome hr)
        rw [← reserveOptimized_eq] at hr
        simp [executeCore_of_reserve_charge s ctx q hl hr hc]
  · simp [executeCore_of_not_committed s ctx q hl]

/-- **H1.4, replay.** An exact retry (same request, same principal) of a journaled request
replays without any reservation, charge or ticket allocation. -/
theorem executeCore_exact_replay {c : Commit 3} (hc : lookupId s.ledger q.id = some c)
    (hq : c.request = q) (hp : c.principal = ctx.principal) :
    executeCore s ctx q = { state := s, outcome := .replayed } := by
  have h := exact_duplicate_replays s.policy s.ledger ctx q c hc hq hp
  rw [executeCore_of_not_committed s ctx q (by simp [h]), h]

end Core

/-- **H1.4, replay independence.** The exact replay holds under any later policy and with
any clock reading or approval (in particular an expired one): only the journal entry and
the principal matter. -/
theorem executeCore_replay_any_policy_clock_approval (s : Worker.State) (ctx : Context 3)
    (q : Request 3) {c : Commit 3} (hc : lookupId s.ledger q.id = some c) (hq : c.request = q)
    (hp : c.principal = ctx.principal) (policy' : Policy 3) (now' : Nat)
    (approval' : Option (Approval 3)) :
    executeCore { s with policy := policy' } { ctx with now := now', approval := approval' } q =
      { state := { s with policy := policy' }, outcome := .replayed } :=
  executeCore_exact_replay _ _ q hc hq hp

/-- A conflicting reuse of a journaled identifier blocks without mutation. -/
theorem executeCore_conflict (s : Worker.State) (ctx : Context 3) (q : Request 3)
    {c : Commit 3} (hc : lookupId s.ledger q.id = some c)
    (hne : ¬ (c.request = q ∧ c.principal = ctx.principal)) :
    executeCore s ctx q = { state := s, outcome := .blocked } := by
  have h := conflicting_duplicate_blocks s.policy s.ledger ctx q c hc hne
  rw [executeCore_of_not_committed s ctx q (by simp [h]), h]

/-! ## H1 target 1: invariant preservation -/

/-- **H1.1.** `executeCore` preserves `FinancialInvariant`. -/
theorem executeCore_financialInvariant (s : Worker.State) (ctx : Context 3) (q : Request 3)
    (hs : FinancialInvariant s) : FinancialInvariant (executeCore s ctx q).state := by
  by_cases h : (executeCore s ctx q).outcome = .committed
  · rw [executeCore_commit_state s ctx q hs.2 h]
    obtain ⟨hl, b₁, b₂, hr, hc⟩ := (executeCore_committed_iff s ctx q).1 h
    rw [reserveOptimized_eq] at hr
    refine ⟨ledger_step_invariant _ _ _ _ _ hs.1, ?_⟩
    have hb₁ := reserve_preserves _ _ _ hs.2 hr
    have hb₂ := charge_bound_preserves _ _ _ hb₁ hc
    rw [reserve_then_charge hs.2 hr] at hc
    cases hc
    exact hb₂
  · rw [executeCore_noncommit_unchanged s ctx q h]
    exact hs

/-- Reachable-state ticket discipline: every recorded budget ticket is below the next
ticket counter. It implies freshness of `financialTicket s`. -/
def TicketsBelow (s : Worker.State) : Prop :=
  ∀ id ∈ s.budget.seen, id < s.nextTicket

theorem TicketsBelow.fresh {s : Worker.State} (h : TicketsBelow s) :
    s.nextTicket ∉ s.budget.seen :=
  fun hm => Nat.lt_irrefl _ (h _ hm)

/-- `executeCore` preserves the ticket discipline, so freshness of the next financial
ticket is derived rather than assumed along `executeCore` traces. -/
theorem executeCore_ticketsBelow (s : Worker.State) (ctx : Context 3) (q : Request 3)
    (hb : BudgetInvariant s.budget) (h : TicketsBelow s) :
    TicketsBelow (executeCore s ctx q).state := by
  by_cases hc : (executeCore s ctx q).outcome = .committed
  · rw [executeCore_commit_state s ctx q hb hc]
    intro id hid
    simp only [chargedBudget, List.mem_append, List.mem_singleton] at hid
    rcases hid with hid | rfl
    · exact Nat.lt_succ_of_lt (h id hid)
    · exact Nat.lt_succ_self _
  · rw [executeCore_noncommit_unchanged s ctx q hc]
    exact h

/-! ## H1 target 6: encoder/decoder agreement -/

private theorem okb {ε α β : Type} (a : α) (f : α → Except ε β) : (Except.ok a >>= f) = f a := rfl
private theorem pureb {ε α β : Type} (a : α) (f : α → Except ε β) : (pure a >>= f) = f a := rfl
private theorem throwb {ε α β : Type} (e : ε) (f : α → Except ε β) : (throw e >>= f) = throw e := rfl

/-- **H1.6 (request).** The worker's request decoder inverts `requestJson`. -/
theorem request_requestJson (q : Request 3) : Worker.request (requestJson q) = .ok q := by
  have h1 : Worker.nat (requestJson q) "id" = .ok q.id := rfl
  have h2 : Worker.nat (requestJson q) "source" = .ok q.source.val := rfl
  have h3 : Worker.nat (requestJson q) "destination" = .ok q.destination.val := rfl
  have h4 : Worker.nat (requestJson q) "amount" = .ok q.amount := rfl
  have h5 : Worker.nat (requestJson q) "expectedRevision" = .ok q.expectedRevision := rfl
  have h6 : Worker.nat (requestJson q) "policyEpoch" = .ok q.policyEpoch := rfl
  unfold Worker.request
  simp only [h1, h2, h3, h4, h5, h6]
  change (match Next.fromWire 3 (Next.toWire q) with
    | some q => (pure q : Except String (Request 3))
    | _ => throw "account out of range") = _
  rw [Next.wire_roundtrip]
  rfl

/-- On a non-`null` value, `Worker.approvalOpt` decodes the four approval fields. -/
theorem approvalOpt_of_ne_null (a : Json) (h : a ≠ Json.null) :
    Worker.approvalOpt a = (do
      let nonce ← Worker.nat a "nonce"
      let principal ← Worker.nat a "principal"
      let boundRequest ← Worker.request (← Worker.field a "boundRequest")
      let expires ← Worker.nat a "expires"
      return some { nonce, principal, boundRequest, expires }) := by
  unfold Worker.approvalOpt
  split
  · exact absurd rfl h
  · rfl

/-- **H1.6 (context).** The worker's context decoder inverts `contextJson`. -/
theorem context_contextJson (ctx : Context 3) :
    Worker.context (contextJson ctx) = .ok ctx := by
  obtain ⟨p, now, _ | ⟨n, ap, bq, e⟩⟩ := ctx
  · rfl
  · have h4 : Worker.request (requestJson bq) = .ok bq := request_requestJson bq
    have ha : Worker.approvalOpt (approvalJson ⟨n, ap, bq, e⟩) = .ok (some ⟨n, ap, bq, e⟩) := by
      have h1 : Worker.nat (approvalJson ⟨n, ap, bq, e⟩) "nonce" = .ok n := rfl
      have h2 : Worker.nat (approvalJson ⟨n, ap, bq, e⟩) "principal" = .ok ap := rfl
      have h3 : Worker.nat (approvalJson ⟨n, ap, bq, e⟩) "expires" = .ok e := rfl
      have h5 : Worker.field (approvalJson ⟨n, ap, bq, e⟩) "boundRequest" =
          .ok (requestJson bq) := rfl
      rw [approvalOpt_of_ne_null _ (by simp [approvalJson, Json.mkObj])]
      simp only [h1, h2, h3, h5, okb, h4]
      rfl
    have hf : Worker.field (contextJson ⟨p, now, some ⟨n, ap, bq, e⟩⟩) "approval" =
        .ok (approvalJson ⟨n, ap, bq, e⟩) := rfl
    have hp : Worker.nat (contextJson ⟨p, now, some ⟨n, ap, bq, e⟩⟩) "principal" = .ok p := rfl
    have hn : Worker.nat (contextJson ⟨p, now, some ⟨n, ap, bq, e⟩⟩) "now" = .ok now := rfl
    unfold Worker.context
    simp only [hf, hp, hn, okb, ha]
    rfl

/-! ## H1 target 5: the actual worker dispatch -/

/-- The three fields of `executeJson` read back exactly. -/
theorem executeJson_fields (ctx : Context 3) (q : Request 3) :
    Worker.str (executeJson ctx q) "op" = .ok "execute" ∧
    Worker.field (executeJson ctx q) "request" = .ok (requestJson q) ∧
    Worker.field (executeJson ctx q) "context" = .ok (contextJson ctx) := ⟨rfl, rfl, rfl⟩

/-- **H1.5, totality and exact branch.** On an initialized worker, the actual
`Worker.dispatch` of `executeJson ctx q` succeeds and returns exactly
`(executeCore s ctx q).state` together with `Worker.result` of that state, whose tag is the
one `ExecuteReplyTag` assigns to the `executeCore` outcome. -/
theorem dispatch_executeJson_spec (s : Worker.State)
    (ctx : Context 3) (q : Request 3) (hinit : s.initialized = true) :
    ∃ tag reason, Worker.dispatch s (executeJson ctx q) =
      .ok ((executeCore s ctx q).state, Worker.result (executeCore s ctx q).state tag reason) ∧
      ExecuteReplyTag (executeCore s ctx q).outcome tag := by
  obtain ⟨hop, hr, hc⟩ := executeJson_fields ctx q
  have e1 : ("execute" == "snapshot") = false := by decide
  have e2 : ("execute" == "control_decide") = false := by decide
  have e3 : ("execute" == "control_hard") = false := by decide
  have e4 : ("execute" == "control_configure") = false := by decide
  have e5 : ("execute" == "configure") = false := by decide
  have e6 : ("execute" == "reserve") = false := by decide
  have e7 : ("execute" == "settle") = false := by decide
  have e8 : ("execute" == "charge") = false := by decide
  have e9 : ("execute" == "flow") = false := by decide
  have e10 : ("execute" == "preview") = false := by decide
  have e11 : ("execute" == "execute") = true := by decide
  unfold Worker.dispatch
  simp only [hop, hr, hc, okb, pureb, request_requestJson, context_contextJson, e1, e2,
    e3, e4, e5, e6, e7, e8, e9, e10, e11, hinit, Bool.or_false, Bool.or_true,
    Bool.false_eq_true, ite_false, ite_true, Bool.not_true]
  have hft : ({ id := s.nextTicket, bound := fun r => if r = 3 then 1 else 0 } : Ticket) =
      financialTicket s := rfl
  rw [hft]
  rcases hl : (ledgerStep s.policy s.ledger ctx q).outcome
  · cases hres : reserveOptimized s.budget (financialTicket s) with
    | none =>
        refine ⟨"BLOCKED", "BUDGET_EXHAUSTED", ?_⟩
        rw [executeCore_of_reserve_none s ctx q hl hres]
        exact ⟨rfl, Or.inl rfl⟩
    | some b₁ =>
        have hr' := hres
        rw [reserveOptimized_eq] at hr'
        obtain ⟨b₂, hch⟩ := Option.isSome_iff_exists.1 (chargeBound_after_reserve_isSome hr')
        have hch' : chargeBound b₁ s.nextTicket = some b₂ := hch
        refine ⟨"COMMITTED", "ADMITTED", ?_, ?_⟩
        · rw [executeCore_of_reserve_charge s ctx q hl hres hch]
          simp only [hch', hinit]
          rfl
        · rw [executeCore_of_reserve_charge s ctx q hl hres hch]
          rfl
  · rw [executeCore_of_not_committed s ctx q (by simp [hl]), hl]
    exact ⟨"REPLAYED", "EXACT_RETRY", rfl, rfl⟩
  · rw [executeCore_of_not_committed s ctx q (by simp [hl]), hl]
    have hb : (LedgerOutcome.blocked == LedgerOutcome.replayed) = false := rfl
    have hb' : (LedgerOutcome.blocked == LedgerOutcome.blocked) = true := rfl
    simp only [hb, hb', Bool.false_eq_true, ite_false, ite_true]
    split_ifs
    · exact ⟨_, _, rfl, Or.inl rfl⟩
    · exact ⟨_, _, rfl, Or.inr rfl⟩
    · exact ⟨_, _, rfl, Or.inl rfl⟩


/-- An uninitialized worker rejects an execute command (no state is returned): the check
precedes request/context parsing. -/
theorem dispatch_executeJson_uninitialized (s : Worker.State) (ctx : Context 3) (q : Request 3)
    (hinit : s.initialized = false) :
    Worker.dispatch s (executeJson ctx q) = .error "worker not configured" := by
  obtain ⟨hop, -, -⟩ := executeJson_fields ctx q
  have e1 : ("execute" == "snapshot") = false := by decide
  have e2 : ("execute" == "control_decide") = false := by decide
  have e3 : ("execute" == "control_hard") = false := by decide
  have e4 : ("execute" == "control_configure") = false := by decide
  have e5 : ("execute" == "configure") = false := by decide
  unfold Worker.dispatch
  simp only [hop, okb, pureb, e1, e2, e3, e4, e5, hinit, Bool.or_false,
    Bool.false_eq_true, ite_false, ite_true, Bool.not_false, throwb]
  rfl

/-- **H1.5.** If the actual `Worker.dispatch` accepts `executeJson ctx q` with result
`(s', reply)`, then the worker was initialized, `s'` is exactly `(executeCore s ctx q).state`,
and the reply is `Worker.result s'` with a tag that reports `COMMITTED` exactly on the
committing branch; replay maps to `REPLAYED`, and blocked steps to `BLOCKED` or
`PENDING_APPROVAL` with their reason string. -/
theorem dispatch_executeJson_refines (s s' : Worker.State)
    (ctx : Context 3) (q : Request 3) (reply : Json)
    (hd : Worker.dispatch s (executeJson ctx q) = .ok (s', reply)) :
    s.initialized = true ∧ s' = (executeCore s ctx q).state ∧
      ∃ tag reason, reply = Worker.result s' tag reason ∧
        ExecuteReplyTag (executeCore s ctx q).outcome tag ∧
        (tag = "COMMITTED" ↔ (executeCore s ctx q).outcome = .committed) := by
  cases hinit : s.initialized
  · rw [dispatch_executeJson_uninitialized s ctx q hinit] at hd
    cases hd
  · obtain ⟨tag, reason, h, htag⟩ := dispatch_executeJson_spec s ctx q hinit
    rw [h] at hd
    cases hd
    exact ⟨rfl, rfl, tag, reason, rfl, htag, executeReplyTag_committed_iff htag⟩

/-- The three fields of `previewJson` read back exactly. -/
theorem previewJson_fields (ctx : Context 3) (q : Request 3) :
    Worker.str (previewJson ctx q) "op" = .ok "preview" ∧
    Worker.field (previewJson ctx q) "request" = .ok (requestJson q) ∧
    Worker.field (previewJson ctx q) "context" = .ok (contextJson ctx) := ⟨rfl, rfl, rfl⟩

/-- Preview through the actual `Worker.dispatch` never changes the state (no ledger write,
no reservation, no ticket increment), and reports `ALLOWED` exactly when the corresponding
execute would commit. -/
theorem dispatch_previewJson_spec (s : Worker.State)
    (ctx : Context 3) (q : Request 3) (hinit : s.initialized = true) :
    ∃ tag reason, Worker.dispatch s (previewJson ctx q) = .ok (s, Worker.result s tag reason) ∧
      (tag = "ALLOWED" ↔ (executeCore s ctx q).outcome = .committed) ∧
      (tag = "REPLAYED" ↔ (executeCore s ctx q).outcome = .replayed) := by
  obtain ⟨hop, hr, hc⟩ := previewJson_fields ctx q
  have e1 : ("preview" == "snapshot") = false := by decide
  have e2 : ("preview" == "control_decide") = false := by decide
  have e3 : ("preview" == "control_hard") = false := by decide
  have e4 : ("preview" == "control_configure") = false := by decide
  have e5 : ("preview" == "configure") = false := by decide
  have e6 : ("preview" == "reserve") = false := by decide
  have e7 : ("preview" == "settle") = false := by decide
  have e8 : ("preview" == "charge") = false := by decide
  have e9 : ("preview" == "flow") = false := by decide
  have e10 : ("preview" == "preview") = true := by decide
  unfold Worker.dispatch
  simp only [hop, hr, hc, okb, pureb, request_requestJson, context_contextJson, e1, e2,
    e3, e4, e5, e6, e7, e8, e9, e10, hinit, Bool.or_false, Bool.true_or,
    Bool.false_eq_true, ite_false, ite_true, Bool.not_true]
  have hft : ({ id := s.nextTicket, bound := fun r => if r = 3 then 1 else 0 } : Ticket) =
      financialTicket s := rfl
  rw [hft]
  rcases hl : (ledgerStep s.policy s.ledger ctx q).outcome
  · cases hres : reserveOptimized s.budget (financialTicket s) with
    | none =>
        refine ⟨"BLOCKED", "BUDGET_EXHAUSTED", rfl, ?_⟩
        rw [executeCore_of_reserve_none s ctx q hl hres]
        simp
    | some b₁ =>
        have hr' := hres
        rw [reserveOptimized_eq] at hr'
        obtain ⟨b₂, hch⟩ := Option.isSome_iff_exists.1 (chargeBound_after_reserve_isSome hr')
        refine ⟨"ALLOWED", "READY", rfl, ?_⟩
        rw [executeCore_of_reserve_charge s ctx q hl hres hch]
        simp
  · rw [executeCore_of_not_committed s ctx q (by simp [hl]), hl]
    exact ⟨"REPLAYED", "EXACT_RETRY", rfl, by simp⟩
  · rw [executeCore_of_not_committed s ctx q (by simp [hl]), hl]
    have hb : (LedgerOutcome.blocked == LedgerOutcome.replayed) = false := rfl
    have hb' : (LedgerOutcome.blocked == LedgerOutcome.blocked) = true := rfl
    simp only [hb, hb', Bool.false_eq_true, ite_false, ite_true]
    split_ifs
    · exact ⟨_, _, rfl, by simp⟩
    · exact ⟨_, _, rfl, by simp⟩
    · exact ⟨_, _, rfl, by simp⟩

/-! ## Concrete cases (kernel-checked with `decide`)

Initialized worker over the demo ledger/policy with two tool-call slots and no other budget.
-/

/-- Concrete initialized worker state with a two-slot tool-call budget. -/
def h1State : Worker.State :=
  { initialized := true, budget := initialBudget (fun r => if r = 3 then 2 else 0) }

/-- An approval for the demo request that has already expired at any later clock reading. -/
def h1ExpiredApproval : Approval 3 :=
  { nonce := 5, principal := 1, boundRequest := demoRequest, expires := 1 }

/-- Fresh commit: one slot charged, nothing left pending, next ticket 1, revision 1. -/
theorem demo_h1_fresh_commit :
    let r := executeCore h1State demoContext demoRequest
    r.outcome = .committed ∧ r.state.nextTicket = 1 ∧ r.state.budget.spent 3 = 1 ∧
      r.state.budget.pending = [] ∧ r.state.budget.seen = [0] ∧ r.state.ledger.revision = 1 ∧
      List.ofFn r.state.ledger.balances = [97500, 22500, 0] := by
  decide

/-- Capacity denial: the ledger step alone would commit, but with no tool-call capacity
nothing is published. -/
theorem demo_h1_capacity_denial :
    let s := { h1State with budget := initialBudget (fun _ => 0) }
    let r := executeCore s demoContext demoRequest
    (ledgerStep s.policy s.ledger demoContext demoRequest).outcome = .committed ∧
      r.outcome = .blocked ∧ r.state.nextTicket = 0 ∧ r.state.ledger.revision = 0 ∧
      r.state.budget.seen = [] ∧ r.state.budget.spent 3 = 0 := by
  decide

/-- Exact replay after a policy-epoch change, with an expired approval and a late clock:
replayed, no new reservation, charge or ticket. -/
theorem demo_h1_expired_exact_replay :
    let s₁ := (executeCore h1State demoContext demoRequest).state
    let s₂ := { s₁ with policy := { s₁.policy with epoch := 8 } }
    let r := executeCore s₂ { demoContext with now := 1000000, approval := some h1ExpiredApproval }
      demoRequest
    r.outcome = .replayed ∧ r.state.nextTicket = 1 ∧ r.state.budget.spent 3 = 1 ∧
      r.state.budget.seen = [0] ∧ r.state.ledger.revision = 1 := by
  decide

/-- Conflict: reusing a committed identifier with a changed amount blocks without effect. -/
theorem demo_h1_conflict :
    let s₁ := (executeCore h1State demoContext demoRequest).state
    let r := executeCore s₁ demoContext { demoRequest with amount := 2600, expectedRevision := 1 }
    r.outcome = .blocked ∧ r.state.nextTicket = 1 ∧ r.state.budget.spent 3 = 1 ∧
      r.state.budget.seen = [0] ∧ r.state.ledger.revision = 1 := by
  decide

/-- Preview through the actual `Worker.dispatch`: the
dry run of the demo request reports `ALLOWED` and returns the state unchanged. -/
theorem demo_h1_preview :
    ∃ reason, Worker.dispatch h1State (previewJson demoContext demoRequest) =
      .ok (h1State, Worker.result h1State "ALLOWED" reason) := by
  obtain ⟨tag, reason, h, hall, -⟩ := dispatch_previewJson_spec h1State demoContext
    demoRequest rfl
  have : tag = "ALLOWED" := hall.2 demo_h1_fresh_commit.1
  subst this
  exact ⟨reason, h⟩

/-- Fresh commit through the actual `Worker.dispatch`. -/
theorem demo_h1_dispatch_commit :
    ∃ reason, Worker.dispatch h1State (executeJson demoContext demoRequest) =
      .ok ((executeCore h1State demoContext demoRequest).state,
        Worker.result (executeCore h1State demoContext demoRequest).state "COMMITTED" reason) := by
  obtain ⟨tag, reason, h, htag⟩ := dispatch_executeJson_spec h1State demoContext
    demoRequest rfl
  have : tag = "COMMITTED" := (executeReplyTag_committed_iff htag).2 demo_h1_fresh_commit.1
  subst this
  exact ⟨reason, h⟩

end Mathguard.Release
