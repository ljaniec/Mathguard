/-
Mathguard reference definitions, model-v1, 2026-10-03.
AUTHORING STATUS: not typechecked in this environment. No proof claims.
Use with a pinned compatible Lean/Mathlib workspace. Freeze reviewed semantics
before requesting proofs. See README.md and docs/05-FORMAL-MODEL.md.
-/
import Mathlib.Data.Finset.Basic
import Mathlib.Algebra.BigOperators.Group.Finset.Basic
import Mathlib.Tactic

namespace Mathguard

abbrev Account (n : Nat) := Fin n
abbrev Principal := Nat

structure Request (n : Nat) where
  id : Nat
  source : Account n
  destination : Account n
  amount : Nat
  expectedRevision : Nat
  policyEpoch : Nat
  deriving DecidableEq, Repr

structure Approval (n : Nat) where
  nonce : Nat
  principal : Principal
  boundRequest : Request n
  expires : Nat
  deriving DecidableEq, Repr

structure Context (n : Nat) where
  principal : Principal
  now : Nat
  approval : Option (Approval n)
  deriving DecidableEq, Repr

structure Policy (n : Nat) where
  epoch : Nat
  owner : Account n → Principal
  transferEnabled : Principal → Bool
  beneficiaryAllowed : Principal → Account n → Bool
  maxTransfer : Nat
  debitCap : Account n → Nat
  approvalThreshold : Nat

structure Commit (n : Nat) where
  request : Request n
  principal : Principal
  approvalNonce : Option Nat
  deriving DecidableEq, Repr

structure Ledger (n : Nat) where
  balances : Account n → Nat
  debited : Account n → Nat
  revision : Nat
  journal : List (Commit n)
  consumedApprovals : List Nat

def initialLedger {n : Nat} (genesis : Account n → Nat) : Ledger n :=
  { balances := genesis, debited := fun _ => 0, revision := 0,
    journal := [], consumedApprovals := [] }

def total {n : Nat} (b : Account n → Nat) : Nat :=
  Finset.univ.sum b

-- Total operational function. Its preservation theorem REQUIRES distinct
-- accounts and sufficient source funds; Nat subtraction otherwise truncates.
def applyTransfer {n : Nat} (b : Account n → Nat) (q : Request n) : Account n → Nat :=
  fun i => if i = q.source then b i - q.amount
           else if i = q.destination then b i + q.amount else b i

def addDebit {n : Nat} (d : Account n → Nat) (q : Request n) : Account n → Nat :=
  fun i => if i = q.source then d i + q.amount else d i

def replayBalances {n : Nat} (genesis : Account n → Nat)
    (journal : List (Commit n)) : Account n → Nat :=
  journal.foldl (fun b c => applyTransfer b c.request) genesis

def replayDebits {n : Nat} (journal : List (Commit n)) : Account n → Nat :=
  journal.foldl (fun d c => addDebit d c.request) (fun _ => 0)

def approvalOK {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) : Bool :=
  match ctx.approval with
  | none => false
  | some a => decide (a.boundRequest = q ∧ a.principal = ctx.principal ∧
      a.principal = p.owner q.source ∧ ctx.now ≤ a.expires ∧
      a.nonce ∉ s.consumedApprovals)

-- No global Invariant is assumed in this guard.
def admission {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) : Bool :=
  decide (q.policyEpoch = p.epoch ∧ q.expectedRevision = s.revision ∧
    p.transferEnabled ctx.principal = true ∧ p.owner q.source = ctx.principal ∧
    p.beneficiaryAllowed ctx.principal q.destination = true ∧
    q.source ≠ q.destination ∧ 0 < q.amount ∧ q.amount ≤ p.maxTransfer ∧
    q.amount ≤ s.balances q.source ∧
    s.debited q.source + q.amount ≤ p.debitCap q.source ∧
    (q.amount < p.approvalThreshold ∨ approvalOK p s ctx q = true))

def usedApproval {n : Nat} (p : Policy n) (ctx : Context n)
    (q : Request n) : Option Nat :=
  if q.amount < p.approvalThreshold then none
  else ctx.approval.map (fun a => a.nonce)

def commitTransfer {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) : Ledger n :=
  let nonce := usedApproval p ctx q
  let c : Commit n := { request := q, principal := ctx.principal, approvalNonce := nonce }
  { balances := applyTransfer s.balances q,
    debited := addDebit s.debited q,
    revision := s.revision + 1,
    journal := s.journal ++ [c],
    consumedApprovals := s.consumedApprovals ++ nonce.toList }

inductive LedgerOutcome where
  | committed | replayed | blocked
  deriving DecidableEq, Repr

structure LedgerResult (n : Nat) where
  state : Ledger n
  outcome : LedgerOutcome

def lookupId {n : Nat} (s : Ledger n) (id : Nat) : Option (Commit n) :=
  s.journal.find? (fun c => c.request.id == id)

def ledgerStep {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) : LedgerResult n :=
  match lookupId s q.id with
  | some c =>
      if c.request = q ∧ c.principal = ctx.principal then
        { state := s, outcome := .replayed }
      else { state := s, outcome := .blocked }
  | none =>
      if admission p s ctx q then
        { state := commitTransfer p s ctx q, outcome := .committed }
      else { state := s, outcome := .blocked }

def LedgerInvariant {n : Nat} (genesis : Account n → Nat) (s : Ledger n) : Prop :=
  total s.balances = total genesis ∧
  replayBalances genesis s.journal = s.balances ∧
  (s.journal.map (fun c => c.request.id)).Nodup ∧
  s.revision = s.journal.length ∧
  replayDebits s.journal = s.debited ∧
  s.consumedApprovals = s.journal.filterMap (fun c => c.approvalNonce) ∧
  s.consumedApprovals.Nodup

def ledgerRun {n : Nat} (p : Policy n) (s : Ledger n)
    (inputs : List (Context n × Request n)) : Ledger n :=
  inputs.foldl (fun st input => (ledgerStep p st input.1 input.2).state) s

-- Concrete satisfiability fixtures: not proofs until checked.
def demoGenesis : Account 3 → Nat := fun i =>
  if i = 0 then 100000 else if i = 1 then 20000 else 0

def demoPolicy : Policy 3 :=
  { epoch := 7, owner := fun i => i.val + 1,
    transferEnabled := fun actor => decide (actor = 1 ∨ actor = 2),
    beneficiaryAllowed := fun actor dst => decide (actor = 1 ∧ dst ≠ 0),
    maxTransfer := 50000,
    debitCap := fun i => if i = 0 then 75000 else if i = 1 then 20000 else 0,
    approvalThreshold := 10000 }

def demoContext : Context 3 := { principal := 1, now := 100, approval := none }

def demoRequest : Request 3 :=
  { id := 17, source := 0, destination := 1, amount := 2500,
    expectedRevision := 0, policyEpoch := 7 }

-- Resource order: API cost micros, tokens, compute milliseconds, tool calls.
abbrev Resource := Fin 4
abbrev Usage := Resource → Nat

def usageLE (a b : Usage) : Prop := ∀ r, a r ≤ b r

structure Ticket where
  id : Nat
  bound : Usage

structure Budget where
  limit : Usage
  spent : Usage
  pending : List Ticket
  seen : List Nat

def reserved (b : Budget) : Usage :=
  fun r => (b.pending.map (fun t => t.bound r)).sum

def BudgetInvariant (b : Budget) : Prop :=
  (∀ r, b.spent r + reserved b r ≤ b.limit r) ∧
  (b.pending.map (fun t => t.id)).Nodup ∧
  b.seen.Nodup ∧
  (∀ t ∈ b.pending, t.id ∈ b.seen)

def initialBudget (limit : Usage) : Budget :=
  { limit := limit, spent := fun _ => 0, pending := [], seen := [] }

def reserve (b : Budget) (t : Ticket) : Option Budget :=
  if t.id ∉ b.seen ∧
      (∀ r, b.spent r + reserved b r + t.bound r ≤ b.limit r) then
    some { b with pending := b.pending ++ [t], seen := b.seen ++ [t.id] }
  else none

def settle (b : Budget) (id : Nat) (actual : Usage) : Option Budget :=
  match b.pending.find? (fun t => t.id == id) with
  | none => none
  | some t =>
      if usageLE actual t.bound then
        some { b with spent := fun r => b.spent r + actual r,
                       pending := b.pending.filter (fun x => x.id != id) }
      else none

-- Cancellation/unknown billing is charged at the full reserved bound.
def chargeBound (b : Budget) (id : Nat) : Option Budget :=
  match b.pending.find? (fun t => t.id == id) with
  | none => none
  | some t => settle b id t.bound

def budgetReconfigure (b : Budget) (newLimit : Usage) : Option Budget :=
  if ∀ r, b.spent r + reserved b r ≤ newLimit r then
    some { b with limit := newLimit }
  else none

inductive BudgetEvent where
  | reserveCall (ticket : Ticket)
  | settleCall (id : Nat) (actual : Usage)
  | chargeCall (id : Nat)
  | reconfigure (newLimit : Usage)

def budgetStep (b : Budget) (e : BudgetEvent) : Budget :=
  let result := match e with
    | .reserveCall t => reserve b t
    | .settleCall id actual => settle b id actual
    | .chargeCall id => chargeBound b id
    | .reconfigure limit => budgetReconfigure b limit
  result.getD b

def budgetRun (b : Budget) (events : List BudgetEvent) : Budget :=
  events.foldl budgetStep b

-- Confidentiality and provenance are separate components.
abbrev Confidentiality := Fin 3  -- 0 public, 1 confidential, 2 secret
abbrev Trust := Fin 2            -- 0 trusted, 1 external-untrusted

structure Label where
  confidentiality : Confidentiality
  trust : Trust
  deriving DecidableEq, Repr

def labelLE (a b : Label) : Prop :=
  a.confidentiality ≤ b.confidentiality ∧ a.trust ≤ b.trust

def joinLabel (a b : Label) : Label :=
  { confidentiality := max a.confidentiality b.confidentiality,
    trust := max a.trust b.trust }

structure Sink where
  clearance : Confidentiality
  acceptsUntrusted : Bool
  deriving DecidableEq, Repr

def flowAllowed (label : Label) (sink : Sink) : Bool :=
  decide (label.confidentiality ≤ sink.clearance ∧
    (label.trust = 0 ∨ sink.acceptsUntrusted = true))

def hardSemanticPermit (hard semantic : Bool) : Bool := hard && semantic

def allowedEffects {α : Type} (hard semantic : α → Prop) : α → Prop :=
  fun effect => hard effect ∧ semantic effect

def contextRun (initial : Label) (observations : List Label) : Label :=
  observations.foldl joinLabel initial

def publicTrusted : Label := { confidentiality := 0, trust := 0 }
def secretUntrusted : Label := { confidentiality := 2, trust := 1 }
def publicSink : Sink := { clearance := 0, acceptsUntrusted := true }
def internalSink : Sink := { clearance := 2, acceptsUntrusted := true }

end Mathguard

/- ARISTOTLE REQUEST ONLY. Holes are targets, not verified results.
Load alongside Spec.lean; preserve all definitions and theorem statements.
Definitions must first typecheck in the pinned Lean/Mathlib workspace. -/

namespace Mathguard

theorem applyTransfer_frame {n : Nat} (b : Account n → Nat) (q : Request n)
    (i : Account n) (hs : i ≠ q.source) (hd : i ≠ q.destination) :
    applyTransfer b q i = b i := by
  sorry

theorem applyTransfer_exact {n : Nat} (b : Account n → Nat) (q : Request n)
    (hd : q.source ≠ q.destination) (hf : q.amount ≤ b q.source) :
    applyTransfer b q q.source + q.amount = b q.source ∧
    applyTransfer b q q.destination = b q.destination + q.amount := by
  sorry

theorem applyTransfer_conserves {n : Nat} (b : Account n → Nat) (q : Request n)
    (hd : q.source ≠ q.destination) (hf : q.amount ≤ b q.source) :
    total (applyTransfer b q) = total b := by
  sorry

theorem ledger_initial_invariant {n : Nat} (genesis : Account n → Nat) :
    LedgerInvariant genesis (initialLedger genesis) := by
  sorry

theorem fresh_commit_preconditions {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    lookupId s q.id = none ∧ admission p s ctx q = true := by
  sorry

theorem fresh_commit_authorized {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    p.owner q.source = ctx.principal ∧
    p.transferEnabled ctx.principal = true ∧
    p.beneficiaryAllowed ctx.principal q.destination = true := by
  sorry

theorem fresh_commit_versions {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    q.expectedRevision = s.revision ∧ q.policyEpoch = p.epoch := by
  sorry

theorem fresh_commit_caps {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    q.amount ≤ p.maxTransfer ∧
    (ledgerStep p s ctx q).state.debited q.source ≤ p.debitCap q.source := by
  sorry

theorem high_value_exact_approval {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed)
    (hv : p.approvalThreshold ≤ q.amount) :
    ∃ a, ctx.approval = some a ∧ a.boundRequest = q ∧
      a.principal = ctx.principal ∧ a.principal = p.owner q.source ∧
      ctx.now ≤ a.expires ∧ a.nonce ∉ s.consumedApprovals := by
  sorry

theorem noncommit_no_mutation {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome ≠ .committed) :
    (ledgerStep p s ctx q).state = s := by
  sorry

theorem duplicate_no_mutation {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (c : Commit n)
    (h : lookupId s q.id = some c) :
    (ledgerStep p s ctx q).state = s := by
  sorry

theorem exact_duplicate_replays {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (c : Commit n)
    (h : lookupId s q.id = some c) (hq : c.request = q)
    (hp : c.principal = ctx.principal) :
    (ledgerStep p s ctx q).outcome = .replayed := by
  sorry

theorem conflicting_duplicate_blocks {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (c : Commit n)
    (h : lookupId s q.id = some c)
    (hc : ¬ (c.request = q ∧ c.principal = ctx.principal)) :
    (ledgerStep p s ctx q).outcome = .blocked := by
  sorry

theorem ledger_step_invariant {n : Nat} (p : Policy n) (genesis : Account n → Nat)
    (s : Ledger n) (ctx : Context n) (q : Request n)
    (hi : LedgerInvariant genesis s) :
    LedgerInvariant genesis (ledgerStep p s ctx q).state := by
  sorry

theorem ledger_trace_invariant {n : Nat} (p : Policy n) (genesis : Account n → Nat)
    (s : Ledger n) (inputs : List (Context n × Request n))
    (hi : LedgerInvariant genesis s) :
    LedgerInvariant genesis (ledgerRun p s inputs) := by
  sorry

theorem ledger_trace_authorized {n : Nat} (p : Policy n) (genesis : Account n → Nat)
    (inputs : List (Context n × Request n)) :
    ∀ c ∈ (ledgerRun p (initialLedger genesis) inputs).journal,
      p.owner c.request.source = c.principal ∧
      p.transferEnabled c.principal = true ∧
      p.beneficiaryAllowed c.principal c.request.destination = true ∧
      c.request.policyEpoch = p.epoch := by
  sorry

theorem stale_revision_not_committed {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (hs : q.expectedRevision ≠ s.revision) :
    (ledgerStep p s ctx q).outcome ≠ .committed := by
  sorry

theorem reused_high_value_approval_not_committed {n : Nat} (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (a : Approval n)
    (ha : ctx.approval = some a) (hu : a.nonce ∈ s.consumedApprovals)
    (hv : p.approvalThreshold ≤ q.amount) :
    (ledgerStep p s ctx q).outcome ≠ .committed := by
  sorry

theorem serial_same_revision_not_both_committed {n : Nat} (p : Policy n) (s : Ledger n)
    (c1 c2 : Context n) (q1 q2 : Request n)
    (h1 : (ledgerStep p s c1 q1).outcome = .committed)
    (h2 : q2.expectedRevision = s.revision) :
    (ledgerStep p (ledgerStep p s c1 q1).state c2 q2).outcome ≠ .committed := by
  sorry

-- NONVACUITY: one real accepted operation and one rejected operation.
theorem demo_accepts :
    (ledgerStep demoPolicy (initialLedger demoGenesis) demoContext demoRequest).outcome =
      .committed := by
  sorry

theorem demo_exact_balances :
    let result := ledgerStep demoPolicy (initialLedger demoGenesis) demoContext demoRequest
    result.state.balances 0 = 97500 ∧ result.state.balances 1 = 22500 ∧
    result.state.balances 2 = 0 ∧ total result.state.balances = 120000 := by
  sorry

theorem demo_blocks_overspend :
    let q := { demoRequest with amount := 100001 }
    (ledgerStep demoPolicy (initialLedger demoGenesis) demoContext q).outcome = .blocked := by
  sorry

theorem demo_exact_retry :
    let first := ledgerStep demoPolicy (initialLedger demoGenesis) demoContext demoRequest
    let second := ledgerStep demoPolicy first.state demoContext demoRequest
    second.outcome = .replayed ∧ second.state = first.state := by
  sorry

theorem demo_high_value_approval_accepts :
    let q := { demoRequest with id := 18, amount := 10000 }
    let a : Approval 3 := { nonce := 9, principal := 1, boundRequest := q, expires := 100 }
    let ctx : Context 3 := { demoContext with approval := some a }
    let result := ledgerStep demoPolicy (initialLedger demoGenesis) ctx q
    result.outcome = .committed ∧ result.state.consumedApprovals = [9] ∧
      result.state.balances 0 = 90000 ∧ result.state.balances 1 = 30000 := by
  sorry

theorem demo_isolated_funds_rejection :
    let p := { demoPolicy with maxTransfer := 200000, debitCap := fun _ => 200000,
                              approvalThreshold := 200000 }
    let q := { demoRequest with amount := 100001 }
    (ledgerStep p (initialLedger demoGenesis) demoContext q).outcome = .blocked := by
  sorry

-- After filling holes, emit #print axioms for every theorem above.
-- Production model must not import this request with holes remaining.
end Mathguard
