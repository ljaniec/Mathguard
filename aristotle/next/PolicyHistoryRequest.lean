-- P1 request statements, kept unchanged for statement comparison.
-- Not part of the Lake build; the theorem holes are intentional.
import Mathguard.Spec

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

theorem governed_initial_invariant {n : Nat}
    (genesis : Account n → Nat) (policy : Policy n) :
    GovernedInvariant genesis (initialGoverned genesis policy) := by
  sorry

theorem governed_step_invariant {n : Nat}
    (genesis : Account n → Nat) (s : GovernedState n)
    (event : GovernedEvent n) (hi : GovernedInvariant genesis s) :
    GovernedInvariant genesis (governedStep s event) := by
  sorry

theorem governed_trace_invariant {n : Nat}
    (genesis : Account n → Nat) (s : GovernedState n)
    (events : List (GovernedEvent n))
    (hi : GovernedInvariant genesis s) :
    GovernedInvariant genesis (governedRun s events) := by
  sorry

theorem policy_reload_preserves_financial_state {n : Nat}
    (s : GovernedState n) (candidate : Policy n) :
    (governedStep s (.activate candidate)).ledger = s.ledger ∧
    (governedStep s (.activate candidate)).history = s.history := by
  sorry

theorem nonincreasing_policy_epoch_rejected {n : Nat}
    (s : GovernedState n) (candidate : Policy n)
    (h : candidate.epoch ≤ s.active.epoch) :
    governedStep s (.activate candidate) = s := by
  sorry

theorem policy_epoch_never_decreases {n : Nat}
    (s : GovernedState n) (event : GovernedEvent n) :
    s.active.epoch ≤ (governedStep s event).active.epoch := by
  sorry

theorem policy_epoch_trace_monotone {n : Nat}
    (s : GovernedState n) (events : List (GovernedEvent n)) :
    s.active.epoch ≤ (governedRun s events).active.epoch := by
  sorry

theorem old_epoch_cannot_fresh_commit_after_reload {n : Nat}
    (s : GovernedState n) (candidate : Policy n)
    (context : Context n) (request : Request n)
    (hc : s.active.epoch < candidate.epoch)
    (hq : request.policyEpoch = s.active.epoch) :
    (ledgerStep (governedStep s (.activate candidate)).active
      (governedStep s (.activate candidate)).ledger
      context request).outcome ≠ .committed := by
  sorry

theorem governed_history_extends {n : Nat}
    (s : GovernedState n) (event : GovernedEvent n) :
    ∃ suffix, (governedStep s event).history = s.history ++ suffix := by
  sorry

theorem historical_authorization_uses_own_snapshot {n : Nat}
    (genesis : Account n → Nat) (s : GovernedState n)
    (hi : GovernedInvariant genesis s) (e : Evidence n)
    (he : e ∈ s.history) :
    EvidenceAuthorized e := by
  sorry

theorem demo_reload_blocks_old_request :
    let s := initialGoverned demoGenesis demoPolicy
    let next := governedStep s (.activate { demoPolicy with epoch := 8 })
    (ledgerStep next.active next.ledger
      demoContext demoRequest).outcome = .blocked := by
  sorry

theorem demo_reload_accepts_new_request :
    let s := initialGoverned demoGenesis demoPolicy
    let next := governedStep s (.activate { demoPolicy with epoch := 8 })
    let q := { demoRequest with policyEpoch := 8 }
    (ledgerStep next.active next.ledger
      demoContext q).outcome = .committed := by
  sorry

end Mathguard.Next
