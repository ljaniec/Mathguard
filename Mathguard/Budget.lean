module

public import Mathguard.Spec
import Mathlib.Tactic.Linarith

/-!
# Mathguard budget kernel: proofs

Usage is a four-dimensional natural-number vector. Calls reserve an upper bound before
they run; settlement removes the unique pending ticket and charges the actual usage,
which must not exceed the reserved bound. We prove that `BudgetInvariant`
(spent plus reserved stays within the limits, ticket identifiers are unique and recorded
in `seen`) holds initially and is preserved by every event and every finite trace, plus
exactness facts for reservation and settlement and two concrete witnesses.

The theorems guarantee *accounted* usage; actual provider behaviour and the computation
of bounds remain assumptions.
-/

public section

namespace Mathguard

/-! ### Auxiliary list lemmas -/

@[simp] theorem reserved_mk (limit spent : Usage) (pending : List Ticket) (seen : List Nat)
    (r : Resource) :
    reserved ⟨limit, spent, pending, seen⟩ r = (pending.map (fun t => t.bound r)).sum := rfl

/-- Removing the (unique) ticket with identifier `t.id` from a list of tickets with distinct
identifiers decreases any additive quantity by exactly its value on `t`. -/
theorem sum_filter_id_ne_add {l : List Ticket} (hl : (l.map (fun t => t.id)).Nodup)
    {t : Ticket} (ht : t ∈ l) (f : Ticket → Nat) :
    ((l.filter (fun x => x.id != t.id)).map f).sum + f t = (l.map f).sum := by
  induction l with
  | nil => simp at ht
  | cons x xs ih =>
    simp only [List.map_cons, List.nodup_cons, List.mem_map, not_exists, not_and] at hl
    rcases List.mem_cons.1 ht with rfl | ht'
    · have hfilt : xs.filter (fun x => x.id != t.id) = xs :=
        List.filter_eq_self.2 fun y hy => by simpa using fun h => hl.1 y hy h
      simp [hfilt, Nat.add_comm]
    · have hne : x.id ≠ t.id := fun h => hl.1 t ht' h.symm
      simp [hne, ← ih hl.2 ht', Nat.add_assoc]

/-- A successful identifier lookup returns a pending ticket with that identifier. -/
theorem find?_id_eq_some {l : List Ticket} {id : Nat} {t : Ticket}
    (h : l.find? (fun t => t.id == id) = some t) : t ∈ l ∧ t.id = id :=
  ⟨List.mem_of_find?_eq_some h, by simpa using List.find?_some h⟩

/-! ### Initial state and reservation -/

theorem budget_initial_invariant (limit : Usage) :
    BudgetInvariant (initialBudget limit) := by
  refine ⟨fun r => ?_, ?_, ?_, ?_⟩ <;> simp [initialBudget, reserved]

theorem reserve_eq_some_iff (b b' : Budget) (t : Ticket) :
    reserve b t = some b' ↔
      (t.id ∉ b.seen ∧ ∀ r, b.spent r + reserved b r + t.bound r ≤ b.limit r) ∧
        b' = { b with pending := b.pending ++ [t], seen := b.seen ++ [t.id] } := by
  unfold reserve
  split_ifs with h <;> simp [h, eq_comm]

theorem reserve_exact (b b' : Budget) (t : Ticket)
    (h : reserve b t = some b') :
    b'.spent = b.spent ∧ b'.limit = b.limit ∧
    (∀ r, reserved b' r = reserved b r + t.bound r) ∧ t.id ∈ b'.seen := by
  obtain ⟨-, rfl⟩ := (reserve_eq_some_iff b b' t).1 h
  exact ⟨rfl, rfl, fun r => by simp [reserved], by simp⟩

theorem reserve_preserves (b b' : Budget) (t : Ticket)
    (hi : BudgetInvariant b) (h : reserve b t = some b') :
    BudgetInvariant b' := by
  obtain ⟨⟨hfresh, hfit⟩, rfl⟩ := (reserve_eq_some_iff b b' t).1 h
  obtain ⟨-, hids, hseen, hsub⟩ := hi
  refine ⟨fun r => ?_, ?_, ?_, ?_⟩
  · have := hfit r
    simp only [reserved, List.map_append, List.sum_append, List.map_cons, List.map_nil,
      List.sum_cons, List.sum_nil] at this ⊢
    omega
  · simp only [List.map_append, List.map_cons, List.map_nil]
    refine List.nodup_append.2 ⟨hids, List.nodup_singleton _, ?_⟩
    simp only [List.mem_map, List.mem_singleton]
    rintro _ ⟨x, hx, rfl⟩ _ rfl h
    exact hfresh (h ▸ hsub x hx)
  · exact List.nodup_append.2 ⟨hseen, List.nodup_singleton _,
      fun a ha b hb hab => hfresh (by simp_all)⟩
  · intro x hx
    rcases List.mem_append.1 hx with hx | hx
    · exact List.mem_append_left _ (hsub x hx)
    · simp_all

theorem reserve_over_limit (b : Budget) (t : Ticket) (r : Resource)
    (h : b.limit r < b.spent r + reserved b r + t.bound r) :
    reserve b t = none := by
  unfold reserve
  rw [if_neg]
  rintro ⟨-, hfit⟩
  exact absurd (hfit r) (Nat.not_le.2 h)

theorem reserve_same_id_rejected (b : Budget) (t : Ticket) (h : t.id ∈ b.seen) :
    reserve b t = none := by
  unfold reserve
  rw [if_neg]
  rintro ⟨hfresh, -⟩
  exact hfresh h

/-! ### Settlement -/

theorem settle_eq_some_iff (b b' : Budget) (id : Nat) (actual : Usage) :
    settle b id actual = some b' ↔
      ∃ t, b.pending.find? (fun t => t.id == id) = some t ∧ usageLE actual t.bound ∧
        b' = { b with spent := fun r => b.spent r + actual r,
                      pending := b.pending.filter (fun x => x.id != id) } := by
  unfold settle
  split
  · rename_i hnone
    simp [hnone]
  · rename_i t ht
    split_ifs with hle <;> simp [ht, hle, eq_comm]

theorem settle_exact (b b' : Budget) (id : Nat) (actual : Usage)
    (hi : BudgetInvariant b) (h : settle b id actual = some b') :
    ∃ t, t ∈ b.pending ∧ t.id = id ∧ usageLE actual t.bound ∧
      (∀ r, b'.spent r = b.spent r + actual r ∧
        reserved b' r + t.bound r = reserved b r) ∧
      b'.seen = b.seen ∧ (∀ x ∈ b'.pending, x.id ≠ id) := by
  obtain ⟨t, hfind, hle, rfl⟩ := (settle_eq_some_iff b b' id actual).1 h
  obtain ⟨ht, rfl⟩ := find?_id_eq_some hfind
  refine ⟨t, ht, rfl, hle, fun r => ⟨rfl, ?_⟩, rfl, fun x hx => ?_⟩
  · exact sum_filter_id_ne_add hi.2.1 ht (fun t => t.bound r)
  · simpa using (List.mem_filter.1 hx).2

theorem settle_preserves (b b' : Budget) (id : Nat) (actual : Usage)
    (hi : BudgetInvariant b) (h : settle b id actual = some b') :
    BudgetInvariant b' := by
  obtain ⟨t, -, -, hle, hacc, hseen', -⟩ := settle_exact b b' id actual hi h
  obtain ⟨t', -, -, rfl⟩ := (settle_eq_some_iff b b' id actual).1 h
  obtain ⟨hlim, hids, hseen, hsub⟩ := hi
  refine ⟨fun r => ?_, ?_, hseen, fun x hx => hsub x (List.mem_filter.1 hx).1⟩
  · have h1 := hacc r
    have h2 := hlim r
    have h3 := hle r
    simp only at h1 ⊢
    omega
  · exact (List.filter_sublist.map _).nodup hids

theorem settled_ticket_cannot_settle_twice (b b' : Budget) (id : Nat)
    (actual actual2 : Usage) (hi : BudgetInvariant b)
    (h : settle b id actual = some b') :
    settle b' id actual2 = none := by
  obtain ⟨-, -, -, -, -, -, hgone⟩ := settle_exact b b' id actual hi h
  have hnone : b'.pending.find? (fun t => t.id == id) = none :=
    List.find?_eq_none.2 fun x hx => by simpa using hgone x hx
  simp [settle, hnone]

theorem charge_bound_preserves (b b' : Budget) (id : Nat)
    (hi : BudgetInvariant b) (h : chargeBound b id = some b') :
    BudgetInvariant b' := by
  unfold chargeBound at h
  split at h
  · simp at h
  · exact settle_preserves b b' id _ hi h

/-! ### Reconfiguration -/

theorem reconfigure_preserves (b b' : Budget) (limit : Usage)
    (hi : BudgetInvariant b) (h : budgetReconfigure b limit = some b') :
    BudgetInvariant b' ∧ b'.spent = b.spent ∧ b'.pending = b.pending ∧
    b'.seen = b.seen ∧ b'.limit = limit := by
  unfold budgetReconfigure at h
  split_ifs at h with hfit
  cases h
  exact ⟨⟨hfit, hi.2⟩, rfl, rfl, rfl, rfl⟩

/-! ### Steps and traces -/

theorem budget_step_preserves (b : Budget) (e : BudgetEvent) (hi : BudgetInvariant b) :
    BudgetInvariant (budgetStep b e) := by
  have key : ∀ o : Option Budget, (∀ b', o = some b' → BudgetInvariant b') →
      BudgetInvariant (o.getD b) := by
    rintro (_ | b') ho
    · exact hi
    · exact ho b' rfl
  cases e with
  | reserveCall t => exact key _ fun b' => reserve_preserves b b' t hi
  | settleCall id actual => exact key _ fun b' => settle_preserves b b' id actual hi
  | chargeCall id => exact key _ fun b' => charge_bound_preserves b b' id hi
  | reconfigure limit => exact key _ fun b' h => (reconfigure_preserves b b' limit hi h).1

theorem budget_trace_preserves (b : Budget) (events : List BudgetEvent)
    (hi : BudgetInvariant b) : BudgetInvariant (budgetRun b events) := by
  induction events generalizing b with
  | nil => exact hi
  | cons e es ih => exact ih _ (budget_step_preserves b e hi)

/-! ### Nonvacuity and oversubscription witnesses -/

theorem demo_budget_first_reservation :
    ∃ b', reserve (initialBudget (fun _ => 10)) { id := 1, bound := fun _ => 6 } = some b' :=
  ⟨_, (reserve_eq_some_iff _ _ _).2 ⟨⟨by simp [initialBudget],
    fun r => by simp [initialBudget, reserved]⟩, rfl⟩⟩

theorem demo_budget_second_reservation_denied (b' : Budget)
    (h : reserve (initialBudget (fun _ => 10)) { id := 1, bound := fun _ => 6 } = some b') :
    reserve b' { id := 2, bound := fun _ => 6 } = none := by
  obtain ⟨-, rfl⟩ := (reserve_eq_some_iff _ _ _).1 h
  exact reserve_over_limit _ _ 0 (by simp [initialBudget, reserved])

end Mathguard

end
