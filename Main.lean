module

import Mathguard.Spec
import Mathguard.Runtime

/-!
# Mathguard demo executable

Runs the reviewed kernels on the documented `n = 3` fixtures. `lake build mathguard`
compiles this file and the kernel modules to C (see `.lake/build/ir/`) and links a native
binary; `lake exe mathguard` runs it.
-/

open Mathguard

def outcomeName : LedgerOutcome → String
  | .committed => "committed"
  | .replayed => "replayed"
  | .blocked => "blocked"

def budgetSummary (b : Budget) : String :=
  s!"spent={List.ofFn b.spent} reserved={List.ofFn (reserved b)} pending={b.pending.length}"

public def main : IO Unit := do
  IO.println "== Ledger (atomic commit boundary over ledgerStep)"
  let cell ← LedgerCell.genesis demoGenesis
  IO.println s!"genesis balances: {← cell.balances}"
  let o₁ ← atomicLedgerStep cell demoPolicy demoContext demoRequest
  IO.println s!"transfer 2500 from 0 to 1: {outcomeName o₁}, balances {← cell.balances}"
  let o₂ ← atomicLedgerStep cell demoPolicy demoContext demoRequest
  IO.println s!"exact retry: {outcomeName o₂}, balances {← cell.balances}"
  let stale := { demoRequest with id := 19 }
  let o₃ ← atomicLedgerStep cell demoPolicy demoContext stale
  IO.println s!"stale revision: {outcomeName o₃}"
  let big := { demoRequest with id := 18, amount := 10000, expectedRevision := 1 }
  let o₄ ← atomicLedgerStep cell demoPolicy demoContext big
  IO.println s!"high value without approval: {outcomeName o₄}"
  let a : Approval 3 := { nonce := 9, principal := 1, boundRequest := big, expires := 100 }
  let o₅ ← atomicLedgerStep cell demoPolicy { demoContext with approval := some a } big
  IO.println s!"high value with bound approval: {outcomeName o₅}, balances {← cell.balances}"
  IO.println "== Budget"
  let b₀ := initialBudget (fun _ => 10)
  let b₁ := budgetStep b₀ (.reserveCall { id := 1, bound := fun _ => 6 })
  IO.println s!"reserve 6/10: {budgetSummary b₁}"
  let b₂ := budgetStep b₁ (.reserveCall { id := 2, bound := fun _ => 6 })
  IO.println s!"reserve another 6 (denied): {budgetSummary b₂}"
  let b₃ := budgetStep b₂ (.settleCall 1 (fun _ => 4))
  IO.println s!"settle actual 4: {budgetSummary b₃}"
  IO.println "== Flow"
  IO.println s!"secret/untrusted -> public: {flowAllowed secretUntrusted publicSink}"
  IO.println s!"secret/untrusted -> internal: {flowAllowed secretUntrusted internalSink}"
  IO.println s!"public/trusted -> public: {flowAllowed publicTrusted publicSink}"
