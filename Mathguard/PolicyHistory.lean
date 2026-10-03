module

public import Mathguard.Spec
import Mathguard.Ledger

/-!
# P1 — policy activation and historical evidence

A separate ledger-and-history model (it is not composed with the C1 budget/label state).

* `governedStep` activates a candidate policy only if its epoch is strictly higher; activation
  changes neither the ledger nor the recorded history.
* Every attempted transfer — committed, replayed or blocked — appends one `Evidence` record
  holding the policy snapshot it was evaluated under, the context, the request, and the
  ledger before and after the attempt.
* `GovernedInvariant` states that the ledger invariant holds, the history is a linked chain
  from the genesis ledger to the current ledger, and every record is sound (it is an actual
  `ledgerStep` result) and authorized under its *own* stored policy snapshot.

Activation events assume an authenticated and validated administrator; administrative
authentication is outside these theorems.
-/

@[expose] public section

namespace Mathguard.Next

structure Evidence (n : Nat) where
  policy : Policy n
  context : Context n
  request : Request n
  before : Ledger n
  after : Ledger n
  outcome : LedgerOutcome

def EvidenceSound {n : Nat} (e : Evidence n) : Prop :=
  e.after = (ledgerStep e.policy e.before e.context e.request).state ∧
  e.outcome = (ledgerStep e.policy e.before e.context e.request).outcome

def EvidenceAuthorized {n : Nat} (e : Evidence n) : Prop :=
  e.outcome = .committed →
    e.policy.owner e.request.source = e.context.principal ∧
    e.policy.transferEnabled e.context.principal = true ∧
    e.policy.beneficiaryAllowed e.context.principal e.request.destination = true ∧
    e.request.policyEpoch = e.policy.epoch ∧
    e.request.expectedRevision = e.before.revision

inductive EvidenceChain {n : Nat} :
    Ledger n → List (Evidence n) → Ledger n → Prop where
  | nil (s : Ledger n) : EvidenceChain s [] s
  | cons (start finish : Ledger n) (e : Evidence n)
      (rest : List (Evidence n))
      (hb : e.before = start)
      (tail : EvidenceChain e.after rest finish) :
      EvidenceChain start (e :: rest) finish

structure GovernedState (n : Nat) where
  active : Policy n
  ledger : Ledger n
  history : List (Evidence n)

inductive GovernedEvent (n : Nat) where
  | activate (candidate : Policy n)
  | transfer (context : Context n) (request : Request n)

def initialGoverned {n : Nat} (genesis : Account n → Nat)
    (policy : Policy n) : GovernedState n :=
  { active := policy, ledger := initialLedger genesis, history := [] }

def governedStep {n : Nat} (s : GovernedState n)
    (event : GovernedEvent n) : GovernedState n :=
  match event with
  | .activate candidate =>
      if s.active.epoch < candidate.epoch then
        { s with active := candidate }
      else s
  | .transfer context request =>
      let r := ledgerStep s.active s.ledger context request
      let e : Evidence n :=
        { policy := s.active,
          context := context,
          request := request,
          before := s.ledger,
          after := r.state,
          outcome := r.outcome }
      { s with ledger := r.state, history := s.history ++ [e] }

def GovernedInvariant {n : Nat} (genesis : Account n → Nat)
    (s : GovernedState n) : Prop :=
  LedgerInvariant genesis s.ledger ∧
  EvidenceChain (initialLedger genesis) s.history s.ledger ∧
  (∀ e ∈ s.history, EvidenceSound e ∧ EvidenceAuthorized e)

def governedRun {n : Nat} (s : GovernedState n)
    (events : List (GovernedEvent n)) : GovernedState n :=
  events.foldl governedStep s

/-! ### Evidence helpers -/

/-- Extending a linked evidence chain by one record whose `before` is the chain's end. -/
theorem EvidenceChain.snoc {n : Nat} {start finish : Ledger n} {history : List (Evidence n)}
    (h : EvidenceChain start history finish) (e : Evidence n) (hb : e.before = finish) :
    EvidenceChain start (history ++ [e]) e.after := by
  induction h with
  | nil s => exact .cons s e.after e [] hb (.nil _)
  | cons start finish e' rest hb' _ ih => exact .cons start e.after e' (rest ++ [e]) hb' (ih hb)

/-- The evidence record built from an actual `ledgerStep` is sound. -/
theorem evidenceSound_of_step {n : Nat} (p : Policy n) (s : Ledger n) (ctx : Context n)
    (q : Request n) :
    EvidenceSound
      { policy := p, context := ctx, request := q, before := s,
        after := (ledgerStep p s ctx q).state,
        outcome := (ledgerStep p s ctx q).outcome } :=
  ⟨rfl, rfl⟩

/-- A sound evidence record is authorized under its own stored policy snapshot. -/
theorem evidenceAuthorized_of_sound {n : Nat} (e : Evidence n) (h : EvidenceSound e) :
    EvidenceAuthorized e := by
  intro hc
  rw [h.2] at hc
  obtain ⟨ho, he, hb⟩ := fresh_commit_authorized _ _ _ _ hc
  obtain ⟨hr, hp⟩ := fresh_commit_versions _ _ _ _ hc
  exact ⟨ho, he, hb, hp, hr⟩

theorem governed_initial_invariant {n : Nat}
    (genesis : Account n → Nat) (policy : Policy n) :
    GovernedInvariant genesis (initialGoverned genesis policy) := by
  exact ⟨ledger_initial_invariant genesis, .nil _, by simp [initialGoverned]⟩

theorem governed_step_invariant {n : Nat}
    (genesis : Account n → Nat) (s : GovernedState n)
    (event : GovernedEvent n) (hi : GovernedInvariant genesis s) :
    GovernedInvariant genesis (governedStep s event) := by
  cases event with
  | activate candidate =>
    simp only [governedStep]
    split_ifs
    · exact hi
    · exact hi
  | transfer context request =>
    obtain ⟨hl, hc, he⟩ := hi
    refine ⟨ledger_step_invariant _ genesis _ _ _ hl, hc.snoc _ rfl, ?_⟩
    intro e hmem
    rcases List.mem_append.1 hmem with hmem | hmem
    · exact he e hmem
    · rw [List.mem_singleton.1 hmem]
      exact ⟨evidenceSound_of_step _ _ _ _,
        evidenceAuthorized_of_sound _ (evidenceSound_of_step _ _ _ _)⟩

theorem governed_trace_invariant {n : Nat}
    (genesis : Account n → Nat) (s : GovernedState n)
    (events : List (GovernedEvent n))
    (hi : GovernedInvariant genesis s) :
    GovernedInvariant genesis (governedRun s events) := by
  induction events generalizing s with
  | nil => exact hi
  | cons x xs ih => exact ih _ (governed_step_invariant genesis s x hi)

theorem policy_reload_preserves_financial_state {n : Nat}
    (s : GovernedState n) (candidate : Policy n) :
    (governedStep s (.activate candidate)).ledger = s.ledger ∧
    (governedStep s (.activate candidate)).history = s.history := by
  simp only [governedStep]
  split_ifs <;> exact ⟨rfl, rfl⟩

theorem nonincreasing_policy_epoch_rejected {n : Nat}
    (s : GovernedState n) (candidate : Policy n)
    (h : candidate.epoch ≤ s.active.epoch) :
    governedStep s (.activate candidate) = s := by
  simp [governedStep, Nat.not_lt.2 h]

theorem policy_epoch_never_decreases {n : Nat}
    (s : GovernedState n) (event : GovernedEvent n) :
    s.active.epoch ≤ (governedStep s event).active.epoch := by
  cases event with
  | activate candidate =>
    simp only [governedStep]
    split_ifs with h
    · exact h.le
    · exact le_rfl
  | transfer context request => exact le_rfl

theorem policy_epoch_trace_monotone {n : Nat}
    (s : GovernedState n) (events : List (GovernedEvent n)) :
    s.active.epoch ≤ (governedRun s events).active.epoch := by
  induction events generalizing s with
  | nil => exact le_rfl
  | cons x xs ih => exact (policy_epoch_never_decreases s x).trans (ih _)

theorem old_epoch_cannot_fresh_commit_after_reload {n : Nat}
    (s : GovernedState n) (candidate : Policy n)
    (context : Context n) (request : Request n)
    (hc : s.active.epoch < candidate.epoch)
    (hq : request.policyEpoch = s.active.epoch) :
    (ledgerStep (governedStep s (.activate candidate)).active
      (governedStep s (.activate candidate)).ledger
      context request).outcome ≠ .committed := by
  simp only [governedStep, if_pos hc]
  intro h
  have := (fresh_commit_versions _ _ _ _ h).2
  omega

theorem governed_history_extends {n : Nat}
    (s : GovernedState n) (event : GovernedEvent n) :
    ∃ suffix, (governedStep s event).history = s.history ++ suffix := by
  cases event with
  | activate candidate => exact ⟨[], by rw [(policy_reload_preserves_financial_state s candidate).2,
      List.append_nil]⟩
  | transfer context request => exact ⟨_, rfl⟩

theorem historical_authorization_uses_own_snapshot {n : Nat}
    (genesis : Account n → Nat) (s : GovernedState n)
    (hi : GovernedInvariant genesis s) (e : Evidence n)
    (he : e ∈ s.history) :
    EvidenceAuthorized e := by
  exact (hi.2.2 e he).2

theorem demo_reload_blocks_old_request :
    let s := initialGoverned demoGenesis demoPolicy
    let next := governedStep s (.activate { demoPolicy with epoch := 8 })
    (ledgerStep next.active next.ledger
      demoContext demoRequest).outcome = .blocked := by
  decide

theorem demo_reload_accepts_new_request :
    let s := initialGoverned demoGenesis demoPolicy
    let next := governedStep s (.activate { demoPolicy with epoch := 8 })
    let q := { demoRequest with policyEpoch := 8 }
    (ledgerStep next.active next.ledger
      demoContext q).outcome = .committed := by
  decide

end Mathguard.Next

end
