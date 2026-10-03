module

public import Mathguard.Spec
import Mathlib.Tactic.FinCases

/-!
# One-pass reservation totals

The reference model stays unchanged. This implementation evaluates the four
pending-resource totals together without allocating four intermediate mapped lists.
Reservation first checks the cost dimension with an allocation-free scalar fold,
so a cost-exhausted request does not compute the other three totals.
`reserveOptimized_eq` and `budgetStepOptimized_eq` prove exact result equality,
including rejection and every state field. No persistent cache can become stale.
Membership checks, append, and settlement still have linear list costs.
-/

@[expose] public section

namespace Mathguard

structure ResourceTotals where
  cost : Nat
  tokens : Nat
  compute : Nat
  calls : Nat

def ResourceTotals.zero : ResourceTotals := ⟨0, 0, 0, 0⟩

def ResourceTotals.addTicket (a : ResourceTotals) (t : Ticket) : ResourceTotals :=
  ⟨a.cost + t.bound 0, a.tokens + t.bound 1,
    a.compute + t.bound 2, a.calls + t.bound 3⟩

def ResourceTotals.toUsage (a : ResourceTotals) : Usage := fun r =>
  match r.val with
  | 0 => a.cost
  | 1 => a.tokens
  | 2 => a.compute
  | _ => a.calls

def reservedTotals (b : Budget) : ResourceTotals :=
  b.pending.foldl ResourceTotals.addTicket ResourceTotals.zero

def reservedAt (b : Budget) (r : Resource) : Nat :=
  b.pending.foldl (fun total t => total + t.bound r) 0

private theorem foldAt_sum (ts : List Ticket) (a : Nat) (r : Resource) :
    ts.foldl (fun total t => total + t.bound r) a =
      a + (ts.map (fun t => t.bound r)).sum := by
  induction ts generalizing a with
  | nil => simp
  | cons t ts ih =>
      rw [List.foldl_cons, ih]
      simp [Nat.add_assoc]

theorem reservedAt_eq (b : Budget) (r : Resource) : reservedAt b r = reserved b r := by
  simpa [reservedAt, reserved] using foldAt_sum b.pending 0 r

private theorem foldTotals_apply (ts : List Ticket) (a : ResourceTotals)
    (r : Resource) :
    (ts.foldl ResourceTotals.addTicket a).toUsage r =
      a.toUsage r + (ts.map (fun t => t.bound r)).sum := by
  induction ts generalizing a with
  | nil => simp
  | cons t ts ih =>
      rw [List.foldl_cons, ih]
      fin_cases r <;>
        simp [ResourceTotals.toUsage, ResourceTotals.addTicket, Nat.add_assoc]

theorem reservedTotals_eq (b : Budget) :
    (reservedTotals b).toUsage = reserved b := by
  funext r
  have hz : ResourceTotals.zero.toUsage r = 0 := by
    fin_cases r <;> rfl
  simpa only [reservedTotals, reserved, hz, Nat.zero_add] using
    foldTotals_apply b.pending ResourceTotals.zero r

def reserveOptimized (b : Budget) (t : Ticket) : Option Budget :=
  if t.id ∉ b.seen then
    if b.spent 0 + reservedAt b 0 + t.bound 0 ≤ b.limit 0 then
      let totals := (reservedTotals b).toUsage
      if ∀ r, b.spent r + totals r + t.bound r ≤ b.limit r then
        some { b with pending := b.pending ++ [t], seen := b.seen ++ [t.id] }
      else none
    else none
  else none

theorem reserveOptimized_eq (b : Budget) (t : Ticket) :
    reserveOptimized b t = reserve b t := by
  by_cases h : t.id ∉ b.seen
  · by_cases h0 : b.spent 0 + reserved b 0 + t.bound 0 ≤ b.limit 0
    · simp [reserveOptimized, reserve, h, h0, reservedAt_eq, reservedTotals_eq]
    · have hn : ¬ ∀ r, b.spent r + reserved b r + t.bound r ≤ b.limit r :=
        fun hr => h0 (hr 0)
      simp [reserveOptimized, reserve, h, h0, hn, reservedAt_eq]
  · simp [reserveOptimized, reserve, h]

def budgetStepOptimized (b : Budget) (e : BudgetEvent) : Budget :=
  let result := match e with
    | .reserveCall t => reserveOptimized b t
    | .settleCall id actual => settle b id actual
    | .chargeCall id => chargeBound b id
    | .reconfigure limit => budgetReconfigure b limit
  result.getD b

theorem budgetStepOptimized_eq (b : Budget) (e : BudgetEvent) :
    budgetStepOptimized b e = budgetStep b e := by
  cases e <;> simp [budgetStepOptimized, budgetStep, reserveOptimized_eq]

end Mathguard

end
