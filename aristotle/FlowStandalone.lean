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

/- ARISTOTLE REQUEST ONLY. These goals prove label enforcement, not
classifier accuracy, cryptographic security, or full noninterference. -/

namespace Mathguard

theorem label_join_upper_left (a b : Label) : labelLE a (joinLabel a b) := by
  sorry

theorem label_join_upper_right (a b : Label) : labelLE b (joinLabel a b) := by
  sorry

theorem label_join_least (a b upper : Label)
    (ha : labelLE a upper) (hb : labelLE b upper) :
    labelLE (joinLabel a b) upper := by
  sorry

theorem label_join_associative (a b c : Label) :
    joinLabel (joinLabel a b) c = joinLabel a (joinLabel b c) := by
  sorry

theorem label_trace_never_lowers (initial : Label) (observations : List Label) :
    labelLE initial (contextRun initial observations) := by
  sorry

theorem label_trace_contains_observation (initial : Label) (observations : List Label)
    (label : Label) (h : label ∈ observations) :
    labelLE label (contextRun initial observations) := by
  sorry

theorem output_clearance_enforced (label : Label) (sink : Sink)
    (h : flowAllowed label sink = true) :
    label.confidentiality ≤ sink.clearance := by
  sorry

theorem public_sink_rejects_sensitive (label : Label) (sink : Sink)
    (hs : sink.clearance = 0) (hl : 0 < label.confidentiality.val) :
    flowAllowed label sink = false := by
  sorry

theorem trust_gate_enforced (label : Label) (sink : Sink)
    (h : flowAllowed label sink = true) (hu : label.trust = 1) :
    sink.acceptsUntrusted = true := by
  sorry

theorem semantic_cannot_override_hard (semantic : Bool) :
    hardSemanticPermit false semantic = false := by
  sorry

theorem semantic_veto (hard : Bool) :
    hardSemanticPermit hard false = false := by
  sorry

theorem final_effects_subset_hard {α : Type} (hard semantic : α → Prop) (effect : α)
    (h : allowedEffects hard semantic effect) : hard effect := by
  sorry

theorem semantic_tightening_never_adds_effect {α : Type}
    (hard oldSemantic newSemantic : α → Prop)
    (ht : ∀ effect, newSemantic effect → oldSemantic effect) (effect : α)
    (h : allowedEffects hard newSemantic effect) :
    allowedEffects hard oldSemantic effect := by
  sorry

theorem demo_secret_export_denied : flowAllowed secretUntrusted publicSink = false := by
  sorry

theorem demo_internal_export_allowed : flowAllowed secretUntrusted internalSink = true := by
  sorry

theorem demo_public_export_allowed : flowAllowed publicTrusted publicSink = true := by
  sorry

end Mathguard
