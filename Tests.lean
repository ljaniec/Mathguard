module

import Mathguard

open Mathguard

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def budgetView (b : Budget) :=
  (List.ofFn b.limit, List.ofFn b.spent,
    b.pending.map (fun t => (t.id, List.ofFn t.bound)), b.seen)

def checkBudgetOptions (a b : Option Budget) (message : String) : IO Unit :=
  check (a.map budgetView == b.map budgetView) message

def snapshotTests : IO Unit := do
  let cell ← LedgerCell.genesis demoGenesis
  let first ← atomicLedgerStepResult cell demoPolicy demoContext demoRequest
  check (first.outcome == .committed && first.state.revision == 1)
    "initial transfer did not commit"
  let secondRequest := { demoRequest with id := 18, expectedRevision := 1 }
  let second ← atomicLedgerStepResult cell demoPolicy demoContext secondRequest
  check (second.outcome == .committed && second.state.revision == 2)
    "second transfer did not commit"
  -- Render the first result after another update: it must retain its own snapshot.
  check (first.state.revision == 1 && List.ofFn first.state.balances == [97500, 22500, 0])
    "first returned snapshot drifted to a later update"
  check (List.ofFn second.state.balances == [95000, 25000, 0])
    "second returned snapshot has incorrect balances"
  let retry ← atomicLedgerStepResult cell demoPolicy demoContext demoRequest
  check (retry.outcome == .replayed && retry.state.revision == 2)
    "retry must replay without a new revision"
  let stale ← atomicLedgerStep cell demoPolicy demoContext
    { demoRequest with id := 19 }
  check (stale == .blocked) "legacy outcome-only API changed"
  let big := { demoRequest with id := 20, amount := 10000, expectedRevision := 2 }
  let denied ← atomicLedgerStepResult cell demoPolicy demoContext big
  check (denied.outcome == .blocked && denied.state.revision == 2)
    "missing high-value approval was accepted"
  let approval : Approval 3 :=
    { nonce := 9, principal := 1, boundRequest := big, expires := 100 }
  let approved ← atomicLedgerStepResult cell demoPolicy
    { demoContext with approval := some approval } big
  check (approved.outcome == .committed && approved.state.revision == 3 &&
    approved.state.consumedApprovals == [9]) "bound approval failed"

def optimizedBudgetTests : IO Unit := do
  -- Nonuniform vectors exercise resource order and early failure in each dimension.
  for size in [0, 1, 10, 100, 1000] do
    let pending := (List.range size).map fun id =>
      ({ id := id, bound := fun r => (id + r.val) % 7 } : Ticket)
    let base : Budget :=
      { limit := fun _ => size * 7 + 10, spent := fun _ => 0,
        pending := pending, seen := List.range size }
    check (List.ofFn (reservedTotals base).toUsage == List.ofFn (reserved base))
      "reserved totals differ"
    for id in [0, size, size + 1] do
      for deniedResource in [0, 1, 2, 3, 4] do
        let b := { base with limit := fun r =>
          if r.val == deniedResource then reserved base r else base.limit r }
        let t : Ticket := { id := id, bound := fun r => r.val + 1 }
        checkBudgetOptions (reserveOptimized b t) (reserve b t)
          "optimized reservation result differs"
  let b := initialBudget (fun _ => 10)
  let t : Ticket := { id := 1, bound := fun _ => 6 }
  let b1 := budgetStepOptimized b (.reserveCall t)
  let denied := budgetStepOptimized b1 (.reserveCall { id := 2, bound := fun _ => 6 })
  check (budgetView denied == budgetView b1) "oversubscription changed state"
  let b2 := budgetStepOptimized b1 (.settleCall 1 (fun _ => 4))
  check (b2.pending.isEmpty && List.ofFn b2.spent == [4, 4, 4, 4])
    "settlement did not remove the ticket and charge actual usage"
  check (budgetView (budgetStepOptimized b2 (.settleCall 1 (fun _ => 4))) == budgetView b2)
    "double settlement changed state"
  checkBudgetOptions (reserveOptimized b2 t) none "settled ticket ID was reused"
  for e in [BudgetEvent.chargeCall 1, .reconfigure (fun _ => 3)] do
    check (budgetView (budgetStepOptimized b1 e) == budgetView (budgetStep b1 e))
      "non-reservation budget event differs"

public def main : IO Unit := do
  snapshotTests
  optimizedBudgetTests
  IO.println "runtime snapshot and optimized-budget regression tests passed"
