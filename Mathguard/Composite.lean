module

public import Mathguard.Spec
import Mathguard.Ledger
import Mathguard.Budget
import Mathguard.Flow

/-!
# C1 — composite financial admission

A single pure transition `compositeStep` that joins the ledger kernel, the resource-budget
kernel and the label kernel:

* the observation is always joined into the context label (even on denial or replay);
* the hard flow gate, an extra hard check and an exact-request semantic assessment must all
  pass before the ledger is consulted (a semantic permit cannot override a hard denial);
* a fresh ledger commit is published only together with a successful reservation of the
  financial-tool ticket, which must reserve at least one tool call;
* denied and replayed actions change neither the ledger nor the budget.

This is a pure joint state update. It does not prove that separate database writes or
mutable cells are atomic, and it does not authenticate the assessment, the source label,
the sink, the policy or the resource bound: those are trusted adapter inputs.
-/

@[expose] public section

namespace Mathguard.Next

structure Assessment (n : Nat) where
  boundRequest : Request n
  permit : Bool

structure CompositeState (n : Nat) where
  ledger : Ledger n
  budget : Budget
  label : Label

structure CompositeInput (n : Nat) where
  policy : Policy n
  context : Context n
  request : Request n
  ticket : Ticket
  observed : Label
  sink : Sink
  hardExtra : Bool
  assessment : Assessment n

structure CompositeResult (n : Nat) where
  state : CompositeState n
  outcome : LedgerOutcome

def initialComposite {n : Nat} (genesis : Account n → Nat) (limit : Usage)
    (label : Label) : CompositeState n :=
  { ledger := initialLedger genesis,
    budget := initialBudget limit, label := label }

def CompositeInvariant {n : Nat} (genesis : Account n → Nat)
    (s : CompositeState n) : Prop :=
  LedgerInvariant genesis s.ledger ∧ BudgetInvariant s.budget

def transferGate {n : Nat} (s : CompositeState n)
    (i : CompositeInput n) : Bool :=
  flowAllowed (joinLabel s.label i.observed) i.sink && i.hardExtra &&
    decide (i.assessment.boundRequest = i.request ∧
      i.assessment.permit = true)

def compositeStep {n : Nat} (s : CompositeState n)
    (i : CompositeInput n) : CompositeResult n :=
  let observedState := { s with label := joinLabel s.label i.observed }
  if transferGate s i then
    let r := ledgerStep i.policy s.ledger i.context i.request
    if r.outcome = .committed then
      if 0 < i.ticket.bound (3 : Resource) then
        match reserve s.budget i.ticket with
        | some budget =>
            { state :=
                { observedState with ledger := r.state, budget := budget },
              outcome := .committed }
        | none =>
            { state := observedState, outcome := .blocked }
      else
        { state := observedState, outcome := .blocked }
    else
      { state := { observedState with ledger := r.state },
        outcome := r.outcome }
  else
    { state := observedState, outcome := .blocked }

def compositeRun {n : Nat} (s : CompositeState n)
    (inputs : List (CompositeInput n)) : CompositeState n :=
  inputs.foldl (fun state input => (compositeStep state input).state) s

/-! ### Branch characterisation of `compositeStep` -/

/-- The context label after any composite step is the join with the observation. -/
theorem compositeStep_label {n : Nat} (s : CompositeState n) (i : CompositeInput n) :
    (compositeStep s i).state.label = joinLabel s.label i.observed := by
  by_cases hg : transferGate s i = true
  · by_cases hl : (ledgerStep i.policy s.ledger i.context i.request).outcome = .committed
    · by_cases ht : 0 < i.ticket.bound (3 : Resource)
      · cases hr : reserve s.budget i.ticket <;> simp [compositeStep, hg, hl, ht, hr]
      · simp [compositeStep, hg, hl, ht]
    · simp [compositeStep, hg, hl]
  · simp [compositeStep, hg]

/-- The committed branch of `compositeStep`, written out. -/
theorem compositeStep_of_commit {n : Nat} (s : CompositeState n) (i : CompositeInput n)
    (b : Budget) (hg : transferGate s i = true)
    (hl : (ledgerStep i.policy s.ledger i.context i.request).outcome = .committed)
    (ht : 0 < i.ticket.bound (3 : Resource))
    (hr : reserve s.budget i.ticket = some b) :
    compositeStep s i =
      { state := { ledger := (ledgerStep i.policy s.ledger i.context i.request).state,
                   budget := b, label := joinLabel s.label i.observed },
        outcome := .committed } := by
  simp [compositeStep, hg, hl, ht, hr]

/-- A composite step commits exactly when every gate passes, the ledger commits freshly,
the ticket reserves a tool call, and the reservation fits. -/
theorem compositeStep_committed_iff {n : Nat} (s : CompositeState n) (i : CompositeInput n) :
    (compositeStep s i).outcome = .committed ↔
      transferGate s i = true ∧
      (ledgerStep i.policy s.ledger i.context i.request).outcome = .committed ∧
      0 < i.ticket.bound (3 : Resource) ∧ ∃ b, reserve s.budget i.ticket = some b := by
  by_cases hg : transferGate s i = true
  · by_cases hl : (ledgerStep i.policy s.ledger i.context i.request).outcome = .committed
    · by_cases ht : 0 < i.ticket.bound (3 : Resource)
      · cases hr : reserve s.budget i.ticket <;> simp [compositeStep, hg, hl, ht, hr]
      · simp [compositeStep, hg, hl, ht]
    · simp [compositeStep, hg, hl]
  · simp [compositeStep, hg]

/-- A non-committed composite step leaves the ledger and the budget unchanged. -/
theorem compositeStep_noncommit {n : Nat} (s : CompositeState n) (i : CompositeInput n)
    (h : (compositeStep s i).outcome ≠ .committed) :
    (compositeStep s i).state.ledger = s.ledger ∧
    (compositeStep s i).state.budget = s.budget := by
  by_cases hg : transferGate s i = true
  · by_cases hl : (ledgerStep i.policy s.ledger i.context i.request).outcome = .committed
    · by_cases ht : 0 < i.ticket.bound (3 : Resource)
      · cases hr : reserve s.budget i.ticket with
        | none => simp [compositeStep, hg, hl, ht, hr]
        | some b => simp [compositeStep, hg, hl, ht, hr] at h
      · simp [compositeStep, hg, hl, ht]
    · simp [compositeStep, hg, hl, noncommit_no_mutation _ _ _ _ hl]
  · simp [compositeStep, hg]

/-- `transferGate` unpacked. -/
theorem transferGate_eq_true_iff {n : Nat} (s : CompositeState n) (i : CompositeInput n) :
    transferGate s i = true ↔
      flowAllowed (joinLabel s.label i.observed) i.sink = true ∧ i.hardExtra = true ∧
      i.assessment.boundRequest = i.request ∧ i.assessment.permit = true := by
  simp [transferGate, and_assoc]

theorem composite_initial_invariant {n : Nat} (genesis : Account n → Nat)
    (limit : Usage) (label : Label) :
    CompositeInvariant genesis (initialComposite genesis limit label) := by
  exact ⟨ledger_initial_invariant genesis, budget_initial_invariant limit⟩

theorem composite_commit_exact {n : Nat} (s : CompositeState n)
    (i : CompositeInput n)
    (h : (compositeStep s i).outcome = .committed) :
    transferGate s i = true ∧
    (ledgerStep i.policy s.ledger i.context i.request).outcome = .committed ∧
    0 < i.ticket.bound (3 : Resource) ∧
    reserve s.budget i.ticket = some (compositeStep s i).state.budget ∧
    (compositeStep s i).state.ledger =
      (ledgerStep i.policy s.ledger i.context i.request).state := by
  obtain ⟨hg, hl, ht, b, hr⟩ := (compositeStep_committed_iff s i).1 h
  rw [compositeStep_of_commit s i b hg hl ht hr]
  exact ⟨hg, hl, ht, hr, rfl⟩

theorem composite_commit_gates {n : Nat} (s : CompositeState n)
    (i : CompositeInput n)
    (h : (compositeStep s i).outcome = .committed) :
    i.hardExtra = true ∧
    i.assessment.boundRequest = i.request ∧
    i.assessment.permit = true ∧
    flowAllowed (joinLabel s.label i.observed) i.sink = true := by
  obtain ⟨hf, hh, hb, hp⟩ := (transferGate_eq_true_iff s i).1 (composite_commit_exact s i h).1
  exact ⟨hh, hb, hp, hf⟩

theorem composite_step_invariant {n : Nat} (genesis : Account n → Nat)
    (s : CompositeState n) (i : CompositeInput n)
    (hi : CompositeInvariant genesis s) :
    CompositeInvariant genesis (compositeStep s i).state := by
  by_cases h : (compositeStep s i).outcome = .committed
  · obtain ⟨-, -, -, hr, hledger⟩ := composite_commit_exact s i h
    refine ⟨?_, reserve_preserves _ _ _ hi.2 hr⟩
    rw [hledger]
    exact ledger_step_invariant _ genesis _ _ _ hi.1
  · obtain ⟨hledger, hbudget⟩ := compositeStep_noncommit s i h
    exact ⟨hledger ▸ hi.1, hbudget ▸ hi.2⟩

theorem composite_label_never_lowers {n : Nat} (s : CompositeState n)
    (i : CompositeInput n) :
    labelLE s.label (compositeStep s i).state.label := by
  rw [compositeStep_label]
  exact label_join_upper_left _ _

theorem composite_observation_retained {n : Nat} (s : CompositeState n)
    (i : CompositeInput n) :
    labelLE i.observed (compositeStep s i).state.label := by
  rw [compositeStep_label]
  exact label_join_upper_right _ _

theorem composite_noncommit_financial_nonmutation {n : Nat}
    (s : CompositeState n) (i : CompositeInput n)
    (h : (compositeStep s i).outcome ≠ .committed) :
    (compositeStep s i).state.ledger = s.ledger ∧
    (compositeStep s i).state.budget = s.budget := by
  exact compositeStep_noncommit s i h

theorem composite_hard_deny_cannot_be_overridden {n : Nat}
    (s : CompositeState n) (i : CompositeInput n)
    (h : i.hardExtra = false) :
    (compositeStep s i).outcome = .blocked := by
  have hg : transferGate s i = false := by simp [transferGate, h]
  simp [compositeStep, hg]

theorem composite_sensitive_flow_denied {n : Nat}
    (s : CompositeState n) (i : CompositeInput n)
    (h : flowAllowed (joinLabel s.label i.observed) i.sink = false) :
    (compositeStep s i).outcome = .blocked := by
  have hg : transferGate s i = false := by simp [transferGate, h]
  simp [compositeStep, hg]

theorem composite_budget_denial_prevents_commit {n : Nat}
    (s : CompositeState n) (i : CompositeInput n)
    (h : reserve s.budget i.ticket = none) :
    (compositeStep s i).outcome ≠ .committed := by
  intro hc
  obtain ⟨-, -, -, b, hb⟩ := (compositeStep_committed_iff s i).1 hc
  rw [h] at hb
  cases hb

theorem composite_replay_no_new_reservation {n : Nat}
    (s : CompositeState n) (i : CompositeInput n)
    (hg : transferGate s i = true)
    (hr : (ledgerStep i.policy s.ledger i.context i.request).outcome = .replayed) :
    (compositeStep s i).outcome = .replayed ∧
    (compositeStep s i).state.budget = s.budget := by
  simp [compositeStep, hg, hr]

theorem composite_trace_invariant {n : Nat} (genesis : Account n → Nat)
    (s : CompositeState n) (inputs : List (CompositeInput n))
    (hi : CompositeInvariant genesis s) :
    CompositeInvariant genesis (compositeRun s inputs) := by
  induction inputs generalizing s with
  | nil => exact hi
  | cons x xs ih => exact ih _ (composite_step_invariant genesis s x hi)

theorem composite_trace_label_never_lowers {n : Nat}
    (s : CompositeState n) (inputs : List (CompositeInput n)) :
    labelLE s.label (compositeRun s inputs).label := by
  induction inputs generalizing s with
  | nil => exact labelLE_refl _
  | cons x xs ih => exact labelLE_trans (composite_label_never_lowers s x) (ih _)

def demoCompositeInput : CompositeInput 3 :=
  { policy := demoPolicy,
    context := demoContext,
    request := demoRequest,
    ticket := { id := 1, bound := fun _ => 1 },
    observed := publicTrusted,
    sink := internalSink,
    hardExtra := true,
    assessment := { boundRequest := demoRequest, permit := true } }

theorem demo_composite_accepts :
    let s := initialComposite demoGenesis (fun _ => 10) publicTrusted
    let r := compositeStep s demoCompositeInput
    r.outcome = .committed ∧
    r.state.ledger.balances 0 = 97500 ∧
    reserved r.state.budget (3 : Resource) = 1 := by
  decide

end Mathguard.Next

end
