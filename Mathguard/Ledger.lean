module

public import Mathguard.Spec
import Mathlib.Algebra.BigOperators.Group.Finset.Basic
import Mathlib.Algebra.BigOperators.Fin

/-!
# Mathguard ledger kernel: proofs

The ledger is closed, finite-account, one-currency and non-overdraft; money is `Nat` minor
units. A fresh request commits only if every admission guard holds (owner, capability,
beneficiary, policy epoch, state revision, distinct endpoints, positive amount, per-transfer
cap, sufficient funds, cumulative debit cap, exact high-value approval). Committed
identifiers take effect at most once: exact retries replay, conflicts block, and neither
mutates the state.

We prove that `LedgerInvariant` (conservation of total funds, journal replay of balances
and debits, unique identifiers, revision = journal length, and consistent single-use approval
nonces) holds at genesis and is preserved by every step and trace, together with the
guard-extraction, no-mutation, replay, stale/reuse/race corollaries and concrete witnesses.

All theorems quantify over an arbitrary number of accounts `n`. `ledgerRun` uses a fixed
policy; `ledger_step_invariant` itself is policy-parametric. The serial same-revision result
assumes sequential atomic transitions.
-/

public section

namespace Mathguard

variable {n : Nat}

/-! ### The transfer update -/

theorem applyTransfer_frame (b : Account n → Nat) (q : Request n)
    (i : Account n) (hs : i ≠ q.source) (hd : i ≠ q.destination) :
    applyTransfer b q i = b i := by
  simp [applyTransfer, hs, hd]

theorem applyTransfer_exact (b : Account n → Nat) (q : Request n)
    (hd : q.source ≠ q.destination) (hf : q.amount ≤ b q.source) :
    applyTransfer b q q.source + q.amount = b q.source ∧
    applyTransfer b q q.destination = b q.destination + q.amount := by
  simp [applyTransfer, hd.symm, Nat.sub_add_cancel hf]

theorem applyTransfer_conserves (b : Account n → Nat) (q : Request n)
    (hd : q.source ≠ q.destination) (hf : q.amount ≤ b q.source) :
    total (applyTransfer b q) = total b := by
  -- Pointwise: the new balance plus the source debit equals the old balance plus the credit.
  have key : ∀ i, applyTransfer b q i + (if i = q.source then q.amount else 0) =
      b i + (if i = q.destination then q.amount else 0) := by
    intro i
    by_cases hs : i = q.source
    · subst hs
      simp [applyTransfer, hd, Nat.sub_add_cancel hf]
    · by_cases hd' : i = q.destination <;> simp [applyTransfer, hs, hd', Ne.symm hd]
  have hsum := congrArg (fun f : Account n → Nat => ∑ i, f i) (funext key)
  simp only [Finset.sum_add_distrib, Finset.sum_ite_eq', Finset.mem_univ, if_true] at hsum
  change ∑ i, applyTransfer b q i = ∑ i, b i
  omega

/-! ### Journal replay -/

@[simp] theorem replayBalances_nil (genesis : Account n → Nat) :
    replayBalances genesis [] = genesis := rfl

@[simp] theorem replayBalances_append_singleton (genesis : Account n → Nat)
    (journal : List (Commit n)) (c : Commit n) :
    replayBalances genesis (journal ++ [c]) =
      applyTransfer (replayBalances genesis journal) c.request := by
  simp [replayBalances, List.foldl_append]

@[simp] theorem replayDebits_nil : replayDebits ([] : List (Commit n)) = fun _ => 0 := rfl

@[simp] theorem replayDebits_append_singleton (journal : List (Commit n)) (c : Commit n) :
    replayDebits (journal ++ [c]) = addDebit (replayDebits journal) c.request := by
  simp [replayDebits, List.foldl_append]

/-- `lookupId` fails exactly when no journal entry carries the identifier. -/
theorem lookupId_eq_none_iff (s : Ledger n) (id : Nat) :
    lookupId s id = none ↔ id ∉ s.journal.map (fun c => c.request.id) := by
  simp [lookupId, List.find?_eq_none]

theorem ledger_initial_invariant (genesis : Account n → Nat) :
    LedgerInvariant genesis (initialLedger genesis) := by
  simp [LedgerInvariant, initialLedger]

/-! ### Unfolding the transition -/

/-- Unpacked form of the admission guard. -/
theorem admission_eq_true_iff (p : Policy n) (s : Ledger n) (ctx : Context n)
    (q : Request n) :
    admission p s ctx q = true ↔
      q.policyEpoch = p.epoch ∧ q.expectedRevision = s.revision ∧
      p.transferEnabled ctx.principal = true ∧ p.owner q.source = ctx.principal ∧
      p.beneficiaryAllowed ctx.principal q.destination = true ∧
      q.source ≠ q.destination ∧ 0 < q.amount ∧ q.amount ≤ p.maxTransfer ∧
      q.amount ≤ s.balances q.source ∧
      s.debited q.source + q.amount ≤ p.debitCap q.source ∧
      (q.amount < p.approvalThreshold ∨ approvalOK p s ctx q = true) := by
  simp [admission]

/-- Unpacked form of approval validity. -/
theorem approvalOK_eq_true_iff (p : Policy n) (s : Ledger n) (ctx : Context n)
    (q : Request n) :
    approvalOK p s ctx q = true ↔
      ∃ a, ctx.approval = some a ∧ a.boundRequest = q ∧
        a.principal = ctx.principal ∧ a.principal = p.owner q.source ∧
        ctx.now ≤ a.expires ∧ a.nonce ∉ s.consumedApprovals := by
  unfold approvalOK
  cases ctx.approval <;> simp

/-- A committed step is exactly a fresh, admitted request applied by `commitTransfer`. -/
theorem ledgerStep_committed_iff (p : Policy n) (s : Ledger n) (ctx : Context n)
    (q : Request n) :
    (ledgerStep p s ctx q).outcome = .committed ↔
      lookupId s q.id = none ∧ admission p s ctx q = true := by
  unfold ledgerStep
  split
  · split_ifs <;> simp_all
  · split_ifs <;> simp_all

theorem ledgerStep_state_of_committed (p : Policy n) (s : Ledger n) (ctx : Context n)
    (q : Request n) (h : (ledgerStep p s ctx q).outcome = .committed) :
    (ledgerStep p s ctx q).state = commitTransfer p s ctx q := by
  obtain ⟨hl, ha⟩ := (ledgerStep_committed_iff p s ctx q).1 h
  simp [ledgerStep, hl, ha]

theorem fresh_commit_preconditions (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    lookupId s q.id = none ∧ admission p s ctx q = true :=
  (ledgerStep_committed_iff p s ctx q).1 h

/-- Every guard of `admission` holds for a committed request. -/
theorem admission_of_committed {p : Policy n} {s : Ledger n} {ctx : Context n}
    {q : Request n} (h : (ledgerStep p s ctx q).outcome = .committed) :
    q.policyEpoch = p.epoch ∧ q.expectedRevision = s.revision ∧
      p.transferEnabled ctx.principal = true ∧ p.owner q.source = ctx.principal ∧
      p.beneficiaryAllowed ctx.principal q.destination = true ∧
      q.source ≠ q.destination ∧ 0 < q.amount ∧ q.amount ≤ p.maxTransfer ∧
      q.amount ≤ s.balances q.source ∧
      s.debited q.source + q.amount ≤ p.debitCap q.source ∧
      (q.amount < p.approvalThreshold ∨ approvalOK p s ctx q = true) :=
  (admission_eq_true_iff p s ctx q).1 (fresh_commit_preconditions p s ctx q h).2

theorem fresh_commit_authorized (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    p.owner q.source = ctx.principal ∧
    p.transferEnabled ctx.principal = true ∧
    p.beneficiaryAllowed ctx.principal q.destination = true := by
  obtain ⟨-, -, he, ho, hb, -⟩ := admission_of_committed h
  exact ⟨ho, he, hb⟩

theorem fresh_commit_versions (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    q.expectedRevision = s.revision ∧ q.policyEpoch = p.epoch := by
  obtain ⟨he, hr, -⟩ := admission_of_committed h
  exact ⟨hr, he⟩

theorem fresh_commit_caps (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed) :
    q.amount ≤ p.maxTransfer ∧
    (ledgerStep p s ctx q).state.debited q.source ≤ p.debitCap q.source := by
  obtain ⟨-, -, -, -, -, -, -, hmax, -, hcap, -⟩ := admission_of_committed h
  rw [ledgerStep_state_of_committed p s ctx q h]
  exact ⟨hmax, by simpa [commitTransfer, addDebit] using hcap⟩

theorem high_value_exact_approval (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome = .committed)
    (hv : p.approvalThreshold ≤ q.amount) :
    ∃ a, ctx.approval = some a ∧ a.boundRequest = q ∧
      a.principal = ctx.principal ∧ a.principal = p.owner q.source ∧
      ctx.now ≤ a.expires ∧ a.nonce ∉ s.consumedApprovals := by
  obtain ⟨-, -, -, -, -, -, -, -, -, -, happ⟩ := admission_of_committed h
  exact (approvalOK_eq_true_iff p s ctx q).1 (happ.resolve_left (Nat.not_lt.2 hv))

/-! ### No mutation and at-most-once effects -/

theorem noncommit_no_mutation (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n)
    (h : (ledgerStep p s ctx q).outcome ≠ .committed) :
    (ledgerStep p s ctx q).state = s := by
  revert h
  unfold ledgerStep
  split
  · split_ifs <;> simp
  · split_ifs <;> simp

theorem duplicate_no_mutation (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (c : Commit n)
    (h : lookupId s q.id = some c) :
    (ledgerStep p s ctx q).state = s := by
  simp only [ledgerStep, h]
  split_ifs <;> rfl

theorem exact_duplicate_replays (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (c : Commit n)
    (h : lookupId s q.id = some c) (hq : c.request = q)
    (hp : c.principal = ctx.principal) :
    (ledgerStep p s ctx q).outcome = .replayed := by
  simp [ledgerStep, h, hq, hp]

theorem conflicting_duplicate_blocks (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (c : Commit n)
    (h : lookupId s q.id = some c)
    (hc : ¬ (c.request = q ∧ c.principal = ctx.principal)) :
    (ledgerStep p s ctx q).outcome = .blocked := by
  simp only [ledgerStep, h, if_neg hc]

/-! ### Invariant preservation -/

/-- The approval nonce consumed by an admitted commit is fresh. -/
theorem usedApproval_fresh {p : Policy n} {s : Ledger n} {ctx : Context n} {q : Request n}
    (ha : admission p s ctx q = true) {k : Nat} (hk : usedApproval p ctx q = some k) :
    k ∉ s.consumedApprovals := by
  unfold usedApproval at hk
  split_ifs at hk with hv
  obtain ⟨a, hctx, rfl⟩ := Option.map_eq_some_iff.1 hk
  have happ := ((admission_eq_true_iff p s ctx q).1 ha).2.2.2.2.2.2.2.2.2.2.resolve_left hv
  obtain ⟨a', hctx', -, -, -, -, hfresh⟩ := (approvalOK_eq_true_iff p s ctx q).1 happ
  rw [hctx] at hctx'
  cases hctx'
  exact hfresh

/-- Accounting is preserved by an admitted fresh commit, for any policy. -/
theorem commitTransfer_invariant (p : Policy n) (genesis : Account n → Nat)
    (s : Ledger n) (ctx : Context n) (q : Request n)
    (hi : LedgerInvariant genesis s) (hl : lookupId s q.id = none)
    (ha : admission p s ctx q = true) :
    LedgerInvariant genesis (commitTransfer p s ctx q) := by
  obtain ⟨htot, hbal, hids, hrev, hdeb, happ, hnodup⟩ := hi
  obtain ⟨-, -, -, -, -, hd, -, -, hf, -⟩ := (admission_eq_true_iff p s ctx q).1 ha
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · exact (applyTransfer_conserves _ q hd hf).trans htot
  · simp [commitTransfer, hbal]
  · simpa [commitTransfer, List.nodup_append, lookupId_eq_none_iff] using
      ⟨hids, fun c hc h => (lookupId_eq_none_iff s q.id).1 hl
        (List.mem_map.2 ⟨c, hc, h⟩)⟩
  · simp [commitTransfer, hrev]
  · simp [commitTransfer, hdeb]
  · cases h : usedApproval p ctx q <;> simp [commitTransfer, happ, h]
  · cases h : usedApproval p ctx q with
    | none => simpa [commitTransfer, h] using hnodup
    | some k =>
      simp only [commitTransfer, h, Option.toList_some]
      exact List.nodup_append.2 ⟨hnodup, List.nodup_singleton k,
        fun a ha' b hb hab => usedApproval_fresh ha h (by simp_all)⟩

theorem ledger_step_invariant (p : Policy n) (genesis : Account n → Nat)
    (s : Ledger n) (ctx : Context n) (q : Request n)
    (hi : LedgerInvariant genesis s) :
    LedgerInvariant genesis (ledgerStep p s ctx q).state := by
  by_cases h : (ledgerStep p s ctx q).outcome = .committed
  · obtain ⟨hl, ha⟩ := fresh_commit_preconditions p s ctx q h
    rw [ledgerStep_state_of_committed p s ctx q h]
    exact commitTransfer_invariant p genesis s ctx q hi hl ha
  · rw [noncommit_no_mutation p s ctx q h]
    exact hi

@[simp] theorem ledgerRun_nil (p : Policy n) (s : Ledger n) : ledgerRun p s [] = s := rfl

@[simp] theorem ledgerRun_cons (p : Policy n) (s : Ledger n) (input : Context n × Request n)
    (inputs : List (Context n × Request n)) :
    ledgerRun p s (input :: inputs) =
      ledgerRun p (ledgerStep p s input.1 input.2).state inputs := rfl

/-- Any property of states preserved by every step is preserved by every trace. -/
theorem ledgerRun_induction (p : Policy n) (P : Ledger n → Prop)
    (hstep : ∀ s ctx q, P s → P (ledgerStep p s ctx q).state)
    (s : Ledger n) (inputs : List (Context n × Request n)) (hs : P s) :
    P (ledgerRun p s inputs) := by
  induction inputs generalizing s with
  | nil => exact hs
  | cons input inputs ih => exact ih _ (hstep _ _ _ hs)

theorem ledger_trace_invariant (p : Policy n) (genesis : Account n → Nat)
    (s : Ledger n) (inputs : List (Context n × Request n))
    (hi : LedgerInvariant genesis s) :
    LedgerInvariant genesis (ledgerRun p s inputs) :=
  ledgerRun_induction p _ (fun s ctx q => ledger_step_invariant p genesis s ctx q) s inputs hi

/-- Every receipt in the journal satisfies the policy's owner/capability/beneficiary/epoch
checks. -/
def JournalAuthorized (p : Policy n) (s : Ledger n) : Prop :=
  ∀ c ∈ s.journal,
    p.owner c.request.source = c.principal ∧
    p.transferEnabled c.principal = true ∧
    p.beneficiaryAllowed c.principal c.request.destination = true ∧
    c.request.policyEpoch = p.epoch

theorem journalAuthorized_step (p : Policy n) (s : Ledger n) (ctx : Context n)
    (q : Request n) (hs : JournalAuthorized p s) :
    JournalAuthorized p (ledgerStep p s ctx q).state := by
  by_cases h : (ledgerStep p s ctx q).outcome = .committed
  · obtain ⟨he, -, hen, ho, hb, -⟩ := admission_of_committed h
    rw [ledgerStep_state_of_committed p s ctx q h]
    intro c hc
    rcases List.mem_append.1 hc with hc | hc
    · exact hs c hc
    · simp only [List.mem_singleton] at hc
      subst hc
      exact ⟨ho, hen, hb, he⟩
  · rw [noncommit_no_mutation p s ctx q h]
    exact hs

theorem ledger_trace_authorized (p : Policy n) (genesis : Account n → Nat)
    (inputs : List (Context n × Request n)) :
    ∀ c ∈ (ledgerRun p (initialLedger genesis) inputs).journal,
      p.owner c.request.source = c.principal ∧
      p.transferEnabled c.principal = true ∧
      p.beneficiaryAllowed c.principal c.request.destination = true ∧
      c.request.policyEpoch = p.epoch :=
  ledgerRun_induction p (JournalAuthorized p) (journalAuthorized_step p) _ inputs
    (by simp [JournalAuthorized, initialLedger])

/-! ### Stale, reused and racing requests -/

theorem stale_revision_not_committed (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (hs : q.expectedRevision ≠ s.revision) :
    (ledgerStep p s ctx q).outcome ≠ .committed :=
  fun h => hs (fresh_commit_versions p s ctx q h).1

theorem reused_high_value_approval_not_committed (p : Policy n) (s : Ledger n)
    (ctx : Context n) (q : Request n) (a : Approval n)
    (ha : ctx.approval = some a) (hu : a.nonce ∈ s.consumedApprovals)
    (hv : p.approvalThreshold ≤ q.amount) :
    (ledgerStep p s ctx q).outcome ≠ .committed := by
  intro h
  obtain ⟨a', ha', -, -, -, -, hfresh⟩ := high_value_exact_approval p s ctx q h hv
  rw [ha] at ha'
  cases ha'
  exact hfresh hu

theorem serial_same_revision_not_both_committed (p : Policy n) (s : Ledger n)
    (c1 c2 : Context n) (q1 q2 : Request n)
    (h1 : (ledgerStep p s c1 q1).outcome = .committed)
    (h2 : q2.expectedRevision = s.revision) :
    (ledgerStep p (ledgerStep p s c1 q1).state c2 q2).outcome ≠ .committed := by
  apply stale_revision_not_committed
  rw [ledgerStep_state_of_committed p s c1 q1 h1, h2]
  simp [commitTransfer]

/-! ### Nonvacuity witnesses (`n = 3`) -/

theorem demo_accepts :
    (ledgerStep demoPolicy (initialLedger demoGenesis) demoContext demoRequest).outcome =
      .committed := by
  decide

theorem demo_exact_balances :
    let result := ledgerStep demoPolicy (initialLedger demoGenesis) demoContext demoRequest
    result.state.balances 0 = 97500 ∧ result.state.balances 1 = 22500 ∧
    result.state.balances 2 = 0 ∧ total result.state.balances = 120000 := by
  intro result
  simp only [result, ledgerStep_state_of_committed _ _ _ _ demo_accepts, total,
    Fin.sum_univ_three]
  decide

theorem demo_blocks_overspend :
    let q := { demoRequest with amount := 100001 }
    (ledgerStep demoPolicy (initialLedger demoGenesis) demoContext q).outcome = .blocked := by
  decide

theorem demo_exact_retry :
    let first := ledgerStep demoPolicy (initialLedger demoGenesis) demoContext demoRequest
    let second := ledgerStep demoPolicy first.state demoContext demoRequest
    second.outcome = .replayed ∧ second.state = first.state := by
  intro first second
  have hlookup : lookupId first.state demoRequest.id =
      some { request := demoRequest, principal := demoContext.principal,
             approvalNonce := none } := by
    simp only [first, ledgerStep_state_of_committed _ _ _ _ demo_accepts]
    decide
  exact ⟨exact_duplicate_replays _ _ _ _ _ hlookup rfl rfl,
    duplicate_no_mutation _ _ _ _ _ hlookup⟩

theorem demo_high_value_approval_accepts :
    let q := { demoRequest with id := 18, amount := 10000 }
    let a : Approval 3 := { nonce := 9, principal := 1, boundRequest := q, expires := 100 }
    let ctx : Context 3 := { demoContext with approval := some a }
    let result := ledgerStep demoPolicy (initialLedger demoGenesis) ctx q
    result.outcome = .committed ∧ result.state.consumedApprovals = [9] ∧
      result.state.balances 0 = 90000 ∧ result.state.balances 1 = 30000 := by
  intro q a ctx result
  have h : result.outcome = .committed := by decide
  refine ⟨h, ?_⟩
  simp only [result, ledgerStep_state_of_committed _ _ _ _ h]
  decide

theorem demo_isolated_funds_rejection :
    let p := { demoPolicy with maxTransfer := 200000, debitCap := fun _ => 200000,
                               approvalThreshold := 200000 }
    let q := { demoRequest with amount := 100001 }
    (ledgerStep p (initialLedger demoGenesis) demoContext q).outcome = .blocked := by
  decide

end Mathguard

end
