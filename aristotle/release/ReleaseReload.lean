import ReleaseDispatch

/-!
# H5 groundwork — worker-level policy reload (`configure`, `control_configure`)

Checked facts about the unchanged production `Worker.dispatch` branches that reload the
ledger policy, budget limit and compiled controls. They cover the worker's joint
`configure` publication only; the host's two-file last-good snapshot, its persistence
envelope, feed versions and retained-history re-sanitization (rest of H5) are not modeled.
-/

namespace Mathguard.Release
open Lean Mathguard

private theorem err_ne_ok' {ε α : Type} {e : ε} {a : α} : (Except.error e : Except ε α) ≠ .ok a := by
  intro h; cases h

private theorem ok_pair' {ε α β : Type} {a a' : α} {b b' : β}
    (h : (Except.ok (a, b) : Except ε (α × β)) = .ok (a', b')) : a = a' := by
  cases h; rfl

/-- A rejected command leaves the worker state unchanged (the loop emits the fixed frame). -/
theorem workerFrame_of_error {s : Worker.State} {j : Json} {err : String}
    (h : Worker.dispatch s j = .error err) : workerFrame s j = (s, rejectedFrame) := by
  simp only [workerFrame, h]
  rfl

/-- The worker's control-policy parser only returns valid policies. -/
theorem controlPolicy_valid {j : Json} {p : Control.ControlPolicy}
    (h : Worker.controlPolicy j = .ok p) : p.valid = true := by
  unfold Worker.controlPolicy at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  repeat' split at h
  all_goals first
    | exact absurd h err_ne_ok'
    | (rename_i hv; cases h; simpa using hv)

/-- Shape of an accepted `configure` command on the actual worker. The compiled controls
are valid, the epoch strictly increases once the worker is initialized, and the budget
reconfiguration succeeded; the ledger, spent, pending and seen tickets and the ticket
counter are not part of the update. -/
theorem dispatch_configure {s s' : Worker.State} {j r : Json}
    (hop : Worker.str j "op" = .ok "configure") (hd : Worker.dispatch s j = .ok (s', r)) :
    ∃ epoch limit b maxTransfer threshold p, p.valid = true ∧
      (s.initialized = true → s.policy.epoch < epoch) ∧
      budgetReconfigure s.budget limit = some b ∧
      s' = { s with policy := { s.policy with epoch, maxTransfer, approvalThreshold := threshold },
                    budget := b, initialized := true, controls := s.controls.reload p } := by
  have e1 : ("configure" == "snapshot") = false := by decide
  have e2 : ("configure" == "control_decide") = false := by decide
  have e3 : ("configure" == "control_hard") = false := by decide
  have e4 : ("configure" == "control_configure") = false := by decide
  have e5 : ("configure" == "configure") = true := by decide
  unfold Worker.dispatch at hd
  simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at hd
  simp only [hop, e1, e2, e3, e4, e5, Bool.or_self, Bool.false_eq_true, ite_false,
    ite_true] at hd
  split at hd
  · exact absurd hd err_ne_ok'
  rename_i epoch _
  by_cases he : (s.initialized && decide (epoch ≤ s.policy.epoch)) = true
  · rw [if_pos he] at hd
    exact absurd hd err_ne_ok'
  rw [if_neg he] at hd
  have hep : s.initialized = true → s.policy.epoch < epoch := by
    intro hi; simp [hi] at he; omega
  repeat' split at hd
  all_goals first
    | exact absurd hd err_ne_ok'
    | exact ⟨_, _, _, _, _, _, controlPolicy_valid ‹_›, hep, ‹_›, (ok_pair' hd).symm⟩

/-- **H5 (worker level, accepted reload).** An accepted `configure` keeps the ledger, the
spent vector, the pending and seen tickets and the next ticket; the new limit covers spent
plus reserved in every dimension; the epoch strictly increases once initialized; and the
new compiled controls become active. -/
theorem configure_preserves {s s' : Worker.State} {j r : Json}
    (hop : Worker.str j "op" = .ok "configure") (hd : Worker.dispatch s j = .ok (s', r)) :
    s'.ledger = s.ledger ∧ s'.budget.spent = s.budget.spent ∧
      s'.budget.pending = s.budget.pending ∧ s'.budget.seen = s.budget.seen ∧
      s'.nextTicket = s.nextTicket ∧
      (∀ i, s'.budget.spent i + reserved s'.budget i ≤ s'.budget.limit i) ∧
      (s.initialized = true → s.policy.epoch < s'.policy.epoch) ∧ s'.initialized = true ∧
      (∃ p, p.valid = true ∧ s'.controls.active = some p) := by
  obtain ⟨epoch, limit, b, mt, th, p, hp, hep, hrc, rfl⟩ := dispatch_configure hop hd
  unfold budgetReconfigure at hrc
  split_ifs at hrc with hfit
  cases hrc
  exact ⟨rfl, rfl, rfl, rfl, rfl, hfit, hep, rfl, p, hp, (Control.reload_valid_activates hp).1⟩

/-- **H5 (worker level, rejected reload).** A rejected command of any kind, in particular a
rejected `configure` (stale epoch, limit below spent plus reserved, invalid controls,
malformed fields), leaves the whole worker state unchanged. -/
theorem rejected_command_unchanged {s : Worker.State} {j : Json} {err : String}
    (h : Worker.dispatch s j = .error err) : (workerFrame s j).1 = s := by
  rw [workerFrame_of_error h]

/-- **H5 (stale approvals).** After an accepted `configure` on an initialized worker, no
request bound to the previous (or an older) policy epoch can freshly commit; an exact
retry of an already committed one may still replay, without effect. -/
theorem configure_stales_old_epoch {s s' : Worker.State} {j r : Json}
    (hop : Worker.str j "op" = .ok "configure") (hd : Worker.dispatch s j = .ok (s', r))
    (hinit : s.initialized = true) (ctx : Context 3) (q : Request 3)
    (hq : q.policyEpoch ≤ s.policy.epoch) :
    (executeCore s' ctx q).outcome ≠ .committed := by
  intro hc
  obtain ⟨hl, -⟩ := (executeCore_committed_iff s' ctx q).1 hc
  obtain ⟨-, ha⟩ := (ledgerStep_committed_iff _ _ _ _).1 hl
  have hq' := ((admission_eq_true_iff _ _ _ _).1 ha).1
  have hlt := (configure_preserves hop hd).2.2.2.2.2.2.1 hinit
  omega

/-- **H5 (controls-only reload).** An accepted `control_configure` changes only the compiled
controls, which become the parsed (valid) policy; ledger, budget, ledger policy, ticket
counter and initialization are untouched. -/
theorem dispatch_control_configure {s s' : Worker.State} {j r : Json}
    (hop : Worker.str j "op" = .ok "control_configure")
    (hd : Worker.dispatch s j = .ok (s', r)) :
    ∃ p, p.valid = true ∧ s' = { s with controls := s.controls.reload p } ∧
      s'.controls.active = some p := by
  have e1 : ("control_configure" == "snapshot") = false := by decide
  have e2 : ("control_configure" == "control_decide") = false := by decide
  have e3 : ("control_configure" == "control_hard") = false := by decide
  have e4 : ("control_configure" == "control_configure") = true := by decide
  unfold Worker.dispatch at hd
  simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at hd
  simp only [hop, e1, e2, e3, e4, Bool.or_self, Bool.false_eq_true, ite_false, ite_true] at hd
  repeat' split at hd
  all_goals first
    | exact absurd hd err_ne_ok'
    | (rename_i hcp
       have hv := controlPolicy_valid hcp
       exact ⟨_, hv, (ok_pair' hd).symm, by rw [← ok_pair' hd]; exact (Control.reload_valid_activates hv).1⟩)

end Mathguard.Release
