import ReleaseH1

/-!
# H2/H5 groundwork — every accepted worker command, and exact-response replay

Checked results about the unchanged production `Worker.dispatch` for an arbitrary command,
and about the unchanged `RuntimeSpec` definitions `workerFrame` and `replayCompleted`.

* `dispatch_ok_cases`: the complete list of state transitions an accepted command can make.
* `dispatch_preserves_workerInvariant`, `workerFrame_preserves_workerInvariant`: ledger and
  budget invariants plus the ticket discipline hold after every accepted (or rejected)
  command, so freshness of the next financial ticket is derived for reachable states.
* `dispatch_monotone`: journal and seen-ticket prefixes, spent, next ticket and (once
  initialized) the policy epoch never go backwards.
* H2 targets 1, 2 and part of 5 for `replayCompleted`: empty-prefix and append laws,
  equality with sequential `workerFrame` replay, invariant preservation, and rejection of a
  response mismatch.
* H5 worker-level reload facts for `configure` and `control_configure`.

These are statements about the in-memory worker transition only. They do not model SQLite,
fsync, crash points, ownership or the host's persisted configuration envelope; those remain
explicit implementation assumptions of H2/H5. `replayCompleted` compares responses with the
compiled `Json` equality; the results below never evaluate it, they only use the Boolean it
returns.
-/

namespace Mathguard.Release
open Lean Mathguard

private theorem err_ne_ok {ε α : Type} {e : ε} {a : α} : (Except.error e : Except ε α) ≠ .ok a := by
  intro h; cases h

private theorem ok_pair {ε α β : Type} {a a' : α} {b b' : β}
    (h : (Except.ok (a, b) : Except ε (α × β)) = .ok (a', b')) : a = a' := by
  cases h; rfl

/-- **Every accepted worker command is one of seven transitions.** For an arbitrary command
`j`, if the actual `Worker.dispatch` succeeds then the new state is: unchanged (snapshot,
control decisions, flow, preview, replay/blocked execute, budget-exhausted reserve); a
control-policy reload; a `configure` with strictly increasing epoch (once initialized) and a
successful `budgetReconfigure`; a reservation of the next ticket; a charge; a settlement; or
exactly `(executeCore s ctx q).state` for the parsed context/request. No JSON assumption
is needed: the parsed values are existentially quantified. -/
theorem dispatch_ok_cases (s s' : Worker.State) (j r : Json)
    (hd : Worker.dispatch s j = .ok (s', r)) :
    s' = s ∨
    (∃ p, s' = { s with controls := s.controls.reload p }) ∨
    (∃ epoch limit b maxTransfer threshold p,
      (s.initialized = true → s.policy.epoch < epoch) ∧
      budgetReconfigure s.budget limit = some b ∧
      s' = { s with policy := { s.policy with epoch, maxTransfer, approvalThreshold := threshold },
                    budget := b, initialized := true, controls := s.controls.reload p }) ∨
    (s.initialized = true ∧ ∃ bound b, reserveOptimized s.budget ⟨s.nextTicket, bound⟩ = some b ∧
      s' = { s with budget := b, nextTicket := s.nextTicket + 1 }) ∨
    (s.initialized = true ∧ ∃ id b, chargeBound s.budget id = some b ∧ s' = { s with budget := b }) ∨
    (s.initialized = true ∧ ∃ id actual b, settle s.budget id actual = some b ∧
      s' = { s with budget := b }) ∨
    (s.initialized = true ∧ ∃ ctx q, s' = (executeCore s ctx q).state) := by
  unfold Worker.dispatch at hd
  simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at hd
  split at hd
  · exact absurd hd err_ne_ok
  rename_i op hop
  by_cases h1 : (op == "snapshot") = true
  · rw [if_pos h1] at hd
    exact Or.inl (ok_pair hd).symm
  rw [if_neg h1] at hd
  by_cases h2 : (op == "control_decide" || op == "control_hard") = true
  · rw [if_pos h2] at hd
    repeat' split at hd
    all_goals first | exact absurd hd err_ne_ok | exact Or.inl (ok_pair hd).symm
  rw [if_neg h2] at hd
  by_cases h3 : (op == "control_configure") = true
  · rw [if_pos h3] at hd
    repeat' split at hd
    all_goals first | exact absurd hd err_ne_ok | exact Or.inr (Or.inl ⟨_, (ok_pair hd).symm⟩)
  rw [if_neg h3] at hd
  by_cases h4 : (op == "configure") = true
  · rw [if_pos h4] at hd
    split at hd
    · exact absurd hd err_ne_ok
    rename_i epoch _
    by_cases he : (s.initialized && decide (epoch ≤ s.policy.epoch)) = true
    · rw [if_pos he] at hd
      exact absurd hd err_ne_ok
    rw [if_neg he] at hd
    have hep : s.initialized = true → s.policy.epoch < epoch := by
      intro hi; simp [hi] at he; omega
    repeat' split at hd
    all_goals first
      | exact absurd hd err_ne_ok
      | exact Or.inr (Or.inr (Or.inl ⟨_, _, _, _, _, _, hep, ‹_›, (ok_pair hd).symm⟩))
  rw [if_neg h4] at hd
  by_cases hi : (!s.initialized) = true
  · rw [if_pos hi] at hd
    exact absurd hd err_ne_ok
  rw [if_neg hi] at hd
  have hinit : s.initialized = true := by simpa using hi
  by_cases h5 : (op == "reserve") = true
  · rw [if_pos h5] at hd
    repeat' split at hd
    all_goals first
      | exact absurd hd err_ne_ok
      | exact Or.inl (ok_pair hd).symm
      | exact Or.inr (Or.inr (Or.inr (Or.inl ⟨hinit, _, _, ‹_›, (ok_pair hd).symm⟩)))
  rw [if_neg h5] at hd
  by_cases h6 : (op == "settle" || op == "charge") = true
  · rw [if_pos h6] at hd
    split at hd
    · exact absurd hd err_ne_ok
    by_cases h7 : (op == "charge") = true
    · rw [if_pos h7] at hd
      repeat' split at hd
      all_goals first
        | exact absurd hd err_ne_ok
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨hinit, _, _, ‹_›, (ok_pair hd).symm⟩))))
    rw [if_neg h7] at hd
    repeat' split at hd
    all_goals first
      | exact absurd hd err_ne_ok
      | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl
          ⟨hinit, _, _, _, ‹_›, (ok_pair hd).symm⟩)))))
  rw [if_neg h6] at hd
  by_cases h8 : (op == "flow") = true
  · rw [if_pos h8] at hd
    repeat' split at hd
    all_goals first | exact absurd hd err_ne_ok | exact Or.inl (ok_pair hd).symm
  rw [if_neg h8] at hd
  by_cases h9 : (op == "preview" || op == "execute") = true
  · rw [if_pos h9] at hd
    split at hd
    · exact absurd hd err_ne_ok
    split at hd
    · exact absurd hd err_ne_ok
    rename_i q _
    split at hd
    · exact absurd hd err_ne_ok
    split at hd
    · exact absurd hd err_ne_ok
    rename_i ctx _
    by_cases hr : ((ledgerStep s.policy s.ledger ctx q).outcome == .replayed) = true
    · rw [if_pos hr] at hd
      exact Or.inl (ok_pair hd).symm
    rw [if_neg hr] at hd
    by_cases hb : ((ledgerStep s.policy s.ledger ctx q).outcome == .blocked) = true
    · rw [if_pos hb] at hd
      repeat' split at hd
      all_goals exact Or.inl (ok_pair hd).symm
    rw [if_neg hb] at hd
    have hl : (ledgerStep s.policy s.ledger ctx q).outcome = .committed := by
      revert hr hb
      cases (ledgerStep s.policy s.ledger ctx q).outcome <;> simp
    split at hd
    · rename_i rb hres
      by_cases hp : (op == "preview") = true
      · rw [if_pos hp] at hd
        exact Or.inl (ok_pair hd).symm
      rw [if_neg hp] at hd
      split at hd
      · rename_i sb hch
        refine Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨hinit, ctx, q, ?_⟩)))))
        rw [executeCore_of_reserve_charge s ctx q hl hres hch]
        exact (ok_pair hd).symm
      · exact absurd hd err_ne_ok
    · exact Or.inl (ok_pair hd).symm
  rw [if_neg h9] at hd
  exact absurd hd err_ne_ok

/-! ## Invariant preservation for every command -/

/-- Reachable worker invariant: the financial invariant plus the ticket discipline. -/
def WorkerInvariant (s : Worker.State) : Prop := FinancialInvariant s ∧ TicketsBelow s

theorem settle_seen {b b' : Budget} {id : Nat} {actual : Usage}
    (h : settle b id actual = some b') : b'.seen = b.seen := by
  obtain ⟨t, -, -, rfl⟩ := (settle_eq_some_iff b b' id actual).1 h
  rfl

theorem settle_spent {b b' : Budget} {id : Nat} {actual : Usage}
    (h : settle b id actual = some b') (r : Resource) : b.spent r ≤ b'.spent r := by
  obtain ⟨t, -, -, rfl⟩ := (settle_eq_some_iff b b' id actual).1 h
  exact Nat.le_add_right _ _

theorem chargeBound_settle {b b' : Budget} {id : Nat} (h : chargeBound b id = some b') :
    ∃ actual, settle b id actual = some b' := by
  unfold chargeBound at h
  split at h
  · simp at h
  · exact ⟨_, h⟩

theorem initial_workerInvariant : WorkerInvariant {} :=
  ⟨⟨ledger_initial_invariant demoGenesis, budget_initial_invariant _⟩,
    fun _ h => by simp [initialBudget] at h⟩

/-- **H2.2 (invariants).** Every accepted command preserves `WorkerInvariant`. -/
theorem dispatch_preserves_workerInvariant {s s' : Worker.State} {j r : Json}
    (hs : WorkerInvariant s) (hd : Worker.dispatch s j = .ok (s', r)) : WorkerInvariant s' := by
  obtain ⟨⟨hl, hb⟩, ht⟩ := hs
  rcases dispatch_ok_cases s s' j r hd with
    rfl | ⟨p, rfl⟩ | ⟨epoch, limit, b, mt, th, p, -, hrc, rfl⟩ | ⟨-, bound, b, hres, rfl⟩ |
    ⟨-, id, b, hch, rfl⟩ | ⟨-, id, actual, b, hst, rfl⟩ | ⟨-, ctx, q, rfl⟩
  · exact ⟨⟨hl, hb⟩, ht⟩
  · exact ⟨⟨hl, hb⟩, ht⟩
  · obtain ⟨hb', -, -, hseen, -⟩ := reconfigure_preserves _ _ _ hb hrc
    refine ⟨⟨hl, hb'⟩, fun id hid => ?_⟩
    exact ht id (hseen ▸ hid)
  · rw [reserveOptimized_eq] at hres
    obtain ⟨-, rfl⟩ := (reserve_eq_some_iff _ _ _).1 hres
    refine ⟨⟨hl, reserve_preserves _ _ _ hb hres⟩, fun id hid => ?_⟩
    simp only [List.mem_append, List.mem_singleton] at hid
    rcases hid with hid | rfl
    · exact Nat.lt_succ_of_lt (ht id hid)
    · exact Nat.lt_succ_self _
  · obtain ⟨actual, hst⟩ := chargeBound_settle hch
    refine ⟨⟨hl, charge_bound_preserves _ _ _ hb hch⟩, fun id' hid => ?_⟩
    exact ht id' ((settle_seen hst) ▸ hid)
  · refine ⟨⟨hl, settle_preserves _ _ _ _ hb hst⟩, fun id' hid => ?_⟩
    exact ht id' ((settle_seen hst) ▸ hid)
  · exact ⟨executeCore_financialInvariant s ctx q ⟨hl, hb⟩,
      executeCore_ticketsBelow s ctx q hb ht⟩

/-- The worker loop frame (rejections keep the state) preserves `WorkerInvariant`. -/
theorem workerFrame_preserves_workerInvariant {s : Worker.State} (j : Json)
    (hs : WorkerInvariant s) : WorkerInvariant (workerFrame s j).1 := by
  unfold workerFrame
  split
  · rename_i pair hd
    obtain ⟨s', r⟩ := pair
    exact dispatch_preserves_workerInvariant hs hd
  · exact hs

/-- In a reachable state the next financial ticket is fresh, so the capacity form of H1.2
applies without an extra freshness hypothesis. -/
theorem WorkerInvariant.committed_iff_capacity {s : Worker.State} (hs : WorkerInvariant s)
    (ctx : Context 3) (q : Request 3) :
    (executeCore s ctx q).outcome = .committed ↔
      (ledgerStep s.policy s.ledger ctx q).outcome = .committed ∧
        s.budget.spent 3 + reserved s.budget 3 + 1 ≤ s.budget.limit 3 :=
  executeCore_committed_iff_capacity s ctx q hs.1.2 hs.2.fresh

/-! ## Monotonicity of every accepted command -/

/-- Facts every `executeCore` step satisfies, with no invariant hypothesis. -/
theorem executeCore_monotone (s : Worker.State) (ctx : Context 3) (q : Request 3) :
    s.ledger.journal <+: (executeCore s ctx q).state.ledger.journal ∧
      s.budget.seen <+: (executeCore s ctx q).state.budget.seen ∧
      (∀ r, s.budget.spent r ≤ (executeCore s ctx q).state.budget.spent r) ∧
      s.nextTicket ≤ (executeCore s ctx q).state.nextTicket ∧
      (executeCore s ctx q).state.initialized = s.initialized ∧
      (executeCore s ctx q).state.policy = s.policy := by
  by_cases hc : (executeCore s ctx q).outcome = .committed
  · obtain ⟨hl, b₁, b₂, hr, hch⟩ := (executeCore_committed_iff s ctx q).1 hc
    rw [executeCore_of_reserve_charge s ctx q hl hr hch]
    rw [reserveOptimized_eq] at hr
    obtain ⟨-, rfl⟩ := (reserve_eq_some_iff _ _ _).1 hr
    obtain ⟨actual, hst⟩ := chargeBound_settle hch
    refine ⟨?_, ?_, fun r => ?_, Nat.le_succ _, rfl, rfl⟩
    · rw [ledgerStep_state_of_committed _ _ _ _ hl]
      exact List.prefix_append _ _
    · rw [settle_seen hst]
      exact List.prefix_append _ _
    · exact settle_spent hst r
  · rw [executeCore_noncommit_unchanged s ctx q hc]
    exact ⟨List.prefix_refl _, List.prefix_refl _, fun _ => le_rfl, le_rfl, rfl, rfl⟩

/-- **Monotonicity.** No accepted command shortens the journal or the seen-ticket list,
lowers any spent dimension, moves the ticket counter back, or (once initialized)
de-initializes the worker or lowers its policy epoch. -/
theorem dispatch_monotone {s s' : Worker.State} {j r : Json}
    (hd : Worker.dispatch s j = .ok (s', r)) :
    s.ledger.journal <+: s'.ledger.journal ∧ s.budget.seen <+: s'.budget.seen ∧
      (∀ r, s.budget.spent r ≤ s'.budget.spent r) ∧ s.nextTicket ≤ s'.nextTicket ∧
      (s.initialized = true → s'.initialized = true ∧ s.policy.epoch ≤ s'.policy.epoch) := by
  rcases dispatch_ok_cases s s' j r hd with
    rfl | ⟨p, rfl⟩ | ⟨epoch, limit, b, mt, th, p, hep, hrc, rfl⟩ | ⟨-, bound, b, hres, rfl⟩ |
    ⟨-, id, b, hch, rfl⟩ | ⟨-, id, actual, b, hst, rfl⟩ | ⟨-, ctx, q, rfl⟩
  · exact ⟨List.prefix_refl _, List.prefix_refl _, fun _ => le_rfl, le_rfl, fun h => ⟨h, le_rfl⟩⟩
  · exact ⟨List.prefix_refl _, List.prefix_refl _, fun _ => le_rfl, le_rfl, fun h => ⟨h, le_rfl⟩⟩
  · unfold budgetReconfigure at hrc
    split_ifs at hrc
    cases hrc
    exact ⟨List.prefix_refl _, List.prefix_refl _, fun _ => le_rfl, le_rfl,
      fun h => ⟨rfl, (hep h).le⟩⟩
  · rw [reserveOptimized_eq] at hres
    obtain ⟨-, rfl⟩ := (reserve_eq_some_iff _ _ _).1 hres
    exact ⟨List.prefix_refl _, List.prefix_append _ _, fun _ => le_rfl, Nat.le_succ _,
      fun h => ⟨h, le_rfl⟩⟩
  · obtain ⟨actual, hst⟩ := chargeBound_settle hch
    exact ⟨List.prefix_refl _, (settle_seen hst) ▸ List.prefix_refl _, settle_spent hst, le_rfl,
      fun h => ⟨h, le_rfl⟩⟩
  · exact ⟨List.prefix_refl _, (settle_seen hst) ▸ List.prefix_refl _, settle_spent hst, le_rfl,
      fun h => ⟨h, le_rfl⟩⟩
  · obtain ⟨h1, h2, h3, h4, h5, h6⟩ := executeCore_monotone s ctx q
    exact ⟨h1, h2, h3, h4, fun h => ⟨h5.trans h, h6 ▸ le_rfl⟩⟩

/-- The journal of the worker never shrinks along the loop frame. -/
theorem workerFrame_journal_prefix (s : Worker.State) (j : Json) :
    s.ledger.journal <+: (workerFrame s j).1.ledger.journal := by
  unfold workerFrame
  split
  · rename_i pair hd
    obtain ⟨s', r⟩ := pair
    exact (dispatch_monotone hd).1
  · exact List.prefix_refl _

/-! ## H2 targets 1, 2, 4 and 5 for exact-response replay -/

/-- The fixed error frame emitted by `Worker.loop`/`workerFrame` on rejection. -/
def rejectedFrame : Json := Json.mkObj [("error", toJson ("WORKER_REQUEST_REJECTED" : String))]

/-- **H2.1 (empty prefix).** Replaying no entries returns the starting worker. -/
theorem replayCompleted_nil (s : Worker.State) : replayCompleted s [] = .ok s := rfl

/-- One replay step, unfolded. -/
theorem replayCompleted_cons (s : Worker.State) (e : Completed) (es : List Completed) :
    replayCompleted s (e :: es) =
      if ((workerFrame s e.command).2 == e.response) = true then
        replayCompleted (workerFrame s e.command).1 es
      else .error "recorded worker response mismatch" := by
  simp only [replayCompleted]
  rfl

/-- **H2.1 (concatenation).** Replaying a concatenation is replaying the first part and
then the second part from its result. -/
theorem replayCompleted_append (s : Worker.State) (l₁ l₂ : List Completed) :
    replayCompleted s (l₁ ++ l₂) = (replayCompleted s l₁).bind (fun s' => replayCompleted s' l₂) := by
  induction l₁ generalizing s with
  | nil => rfl
  | cons e es ih =>
      rw [List.cons_append, replayCompleted_cons, replayCompleted_cons]
      split
      · exact ih _
      · rfl

/-- **H2.1.** When the first part replays successfully, replaying the concatenation equals
replaying the second part from that state. -/
theorem replayCompleted_append_of_ok {s s₁ : Worker.State} {l₁ : List Completed}
    (h : replayCompleted s l₁ = .ok s₁) (l₂ : List Completed) :
    replayCompleted s (l₁ ++ l₂) = replayCompleted s₁ l₂ := by
  rw [replayCompleted_append, h]
  rfl

/-- **H2.2 (exact state).** A successful replay produces exactly the state of running the
recorded private worker commands through the worker frame in order. -/
theorem replayCompleted_ok_state {s s' : Worker.State} {es : List Completed}
    (h : replayCompleted s es = .ok s') :
    s' = es.foldl (fun st e => (workerFrame st e.command).1) s := by
  induction es generalizing s with
  | nil => cases h; rfl
  | cons e es ih =>
      rw [replayCompleted_cons] at h
      split at h
      · exact ih h
      · cases h

/-- **H2.2 (invariants).** A successful replay from a `WorkerInvariant` state ends in a
`WorkerInvariant` state; budget tickets and charges come only from replayed commands. -/
theorem replayCompleted_preserves {s s' : Worker.State} {es : List Completed}
    (hs : WorkerInvariant s) (h : replayCompleted s es = .ok s') : WorkerInvariant s' := by
  induction es generalizing s with
  | nil => cases h; exact hs
  | cons e es ih =>
      rw [replayCompleted_cons] at h
      split at h
      · exact ih (workerFrame_preserves_workerInvariant _ hs) h
      · cases h

/-- A successful replay never shortens the journal. -/
theorem replayCompleted_journal_prefix {s s' : Worker.State} {es : List Completed}
    (h : replayCompleted s es = .ok s') : s.ledger.journal <+: s'.ledger.journal := by
  induction es generalizing s with
  | nil => cases h; exact List.prefix_refl _
  | cons e es ih =>
      rw [replayCompleted_cons] at h
      split at h
      · exact (workerFrame_journal_prefix s e.command).trans (ih h)
      · cases h

/-- **H2.5 (response mismatch).** If the recomputed response of the next entry does not
match the recorded one, replay fails: no recovered state is returned. -/
theorem replayCompleted_mismatch (s : Worker.State) (e : Completed) (es : List Completed)
    (h : ((workerFrame s e.command).2 == e.response) = false) :
    replayCompleted s (e :: es) = .error "recorded worker response mismatch" := by
  rw [replayCompleted_cons, if_neg (by simp [h])]

/-- A replay failure anywhere in the prefix makes the whole replay fail. -/
theorem replayCompleted_append_of_error {s : Worker.State} {l₁ : List Completed} {err : String}
    (h : replayCompleted s l₁ = .error err) (l₂ : List Completed) :
    replayCompleted s (l₁ ++ l₂) = .error err := by
  rw [replayCompleted_append, h]
  rfl

/-- A recorded rejected command (whose recorded response is the fixed rejection frame) does
not abort replay and does not change the state: replay continues with the next entry. The
hypothesis on `==` is about the compiled `Json` equality on that recorded frame. -/
theorem replayCompleted_rejected (s : Worker.State) (e : Completed) (es : List Completed)
    {err : String} (hd : Worker.dispatch s e.command = .error err)
    (hr : (rejectedFrame == e.response) = true) :
    replayCompleted s (e :: es) = replayCompleted s es := by
  have hw : workerFrame s e.command = (s, rejectedFrame) := by
    simp only [workerFrame, hd]
    rfl
  rw [replayCompleted_cons, hw]
  simp [hr]

/-- A commit leaves a journal entry that makes every exact retry by the same principal
replay after any journal extension (later commands, restart replay), whatever the later
policy, clock or approval: no new debit, reservation, charge or ticket. -/
theorem committed_retry_replays (s : Worker.State) (ctx : Context 3) (q : Request 3)
    (hc : (executeCore s ctx q).outcome = .committed) (s₂ : Worker.State)
    (hpre : (executeCore s ctx q).state.ledger.journal <+: s₂.ledger.journal)
    (ctx' : Context 3) (hp : ctx'.principal = ctx.principal) :
    executeCore s₂ ctx' q = { state := s₂, outcome := .replayed } := by
  obtain ⟨hl, b₁, b₂, hr, hch⟩ := (executeCore_committed_iff s ctx q).1 hc
  have hstate := executeCore_of_reserve_charge s ctx q hl hr hch
  rw [hstate] at hpre
  simp only [ledgerStep_state_of_committed _ _ _ _ hl, commitTransfer] at hpre
  obtain ⟨rest, hrest⟩ := hpre
  obtain ⟨hnone, -⟩ := (ledgerStep_committed_iff _ _ _ _).1 hl
  have hfind : lookupId s₂.ledger q.id =
      some { request := q, principal := ctx.principal, approvalNonce := usedApproval s.policy ctx q } := by
    unfold lookupId at hnone ⊢
    rw [← hrest, List.append_assoc, List.find?_append, hnone]
    simp
  exact executeCore_exact_replay s₂ ctx' q hfind rfl hp.symm

/-- **H2.4 (worker level).** After a commit, replaying any further recorded commands that
succeeds yields a state in which an exact retry by the same principal replays, with no new
debit or financial charge. -/
theorem retry_after_replay (s : Worker.State) (ctx : Context 3) (q : Request 3)
    (hc : (executeCore s ctx q).outcome = .committed) {es : List Completed} {s₂ : Worker.State}
    (hrep : replayCompleted (executeCore s ctx q).state es = .ok s₂)
    (ctx' : Context 3) (hp : ctx'.principal = ctx.principal) :
    executeCore s₂ ctx' q = { state := s₂, outcome := .replayed } :=
  committed_retry_replays s ctx q hc s₂ (replayCompleted_journal_prefix hrep) ctx' hp

end Mathguard.Release
