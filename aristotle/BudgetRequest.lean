/- ARISTOTLE REQUEST ONLY. Preserve the definitions in Spec.lean. -/
import Spec

namespace Mathguard

theorem budget_initial_invariant (limit : Usage) :
    BudgetInvariant (initialBudget limit) := by
  sorry

theorem reserve_preserves (b b' : Budget) (t : Ticket)
    (hi : BudgetInvariant b) (h : reserve b t = some b') :
    BudgetInvariant b' := by
  sorry

theorem reserve_exact (b b' : Budget) (t : Ticket)
    (h : reserve b t = some b') :
    b'.spent = b.spent ∧ b'.limit = b.limit ∧
    (∀ r, reserved b' r = reserved b r + t.bound r) ∧ t.id ∈ b'.seen := by
  sorry

theorem reserve_over_limit (b : Budget) (t : Ticket) (r : Resource)
    (h : b.limit r < b.spent r + reserved b r + t.bound r) :
    reserve b t = none := by
  sorry

theorem reserve_same_id_rejected (b : Budget) (t : Ticket) (h : t.id ∈ b.seen) :
    reserve b t = none := by
  sorry

theorem settle_preserves (b b' : Budget) (id : Nat) (actual : Usage)
    (hi : BudgetInvariant b) (h : settle b id actual = some b') :
    BudgetInvariant b' := by
  sorry

theorem settle_exact (b b' : Budget) (id : Nat) (actual : Usage)
    (hi : BudgetInvariant b) (h : settle b id actual = some b') :
    ∃ t, t ∈ b.pending ∧ t.id = id ∧ usageLE actual t.bound ∧
      (∀ r, b'.spent r = b.spent r + actual r ∧
        reserved b' r + t.bound r = reserved b r) ∧
      b'.seen = b.seen ∧ (∀ x ∈ b'.pending, x.id ≠ id) := by
  sorry

theorem settled_ticket_cannot_settle_twice (b b' : Budget) (id : Nat)
    (actual actual2 : Usage) (hi : BudgetInvariant b)
    (h : settle b id actual = some b') :
    settle b' id actual2 = none := by
  sorry

theorem charge_bound_preserves (b b' : Budget) (id : Nat)
    (hi : BudgetInvariant b) (h : chargeBound b id = some b') :
    BudgetInvariant b' := by
  sorry

theorem reconfigure_preserves (b b' : Budget) (limit : Usage)
    (hi : BudgetInvariant b) (h : budgetReconfigure b limit = some b') :
    BudgetInvariant b' ∧ b'.spent = b.spent ∧ b'.pending = b.pending ∧
    b'.seen = b.seen ∧ b'.limit = limit := by
  sorry

theorem budget_step_preserves (b : Budget) (e : BudgetEvent) (hi : BudgetInvariant b) :
    BudgetInvariant (budgetStep b e) := by
  sorry

theorem budget_trace_preserves (b : Budget) (events : List BudgetEvent)
    (hi : BudgetInvariant b) : BudgetInvariant (budgetRun b events) := by
  sorry

-- NONVACUITY and oversubscription: all components use simple constant bounds.
theorem demo_budget_first_reservation :
    ∃ b', reserve (initialBudget (fun _ => 10)) { id := 1, bound := fun _ => 6 } = some b' := by
  sorry

theorem demo_budget_second_reservation_denied (b' : Budget)
    (h : reserve (initialBudget (fun _ => 10)) { id := 1, bound := fun _ => 6 } = some b') :
    reserve b' { id := 2, bound := fun _ => 6 } = none := by
  sorry

end Mathguard
