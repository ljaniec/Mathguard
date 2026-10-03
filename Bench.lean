module

import Mathguard.Spec
import Mathguard.OptimizedBudget
import Lean.Data.Json

open Mathguard

def benchPolicy : Policy 2 :=
  { epoch := 7, owner := fun i => i.val + 1,
    transferEnabled := fun a => a == 1,
    beneficiaryAllowed := fun a dst => a == 1 && dst == 1,
    maxTransfer := 1000000, debitCap := fun _ => 1000000,
    approvalThreshold := 1000000 }

def benchRequest (id revision : Nat) : Request 2 :=
  { id := id, source := 0, destination := 1, amount := 1,
    expectedRevision := revision, policyEpoch := 7 }

def benchContext : Context 2 := { principal := 1, now := 0, approval := none }

def ledgerFixture (size : Nat) : Ledger 2 :=
  { balances := fun i => if i == 0 then 1000000 - size else size,
    debited := fun i => if i == 0 then size else 0,
    revision := size,
    journal := (List.range size).map fun id =>
      { request := benchRequest id id, principal := 1, approvalNonce := none },
    consumedApprovals := [] }

@[noinline] def ledgerProbe (s : Ledger 2) (q : Request 2) : Nat :=
  let result := ledgerStep benchPolicy s benchContext q
  result.state.revision + result.state.balances 0 +
    (match result.outcome with | .committed => 1 | .replayed => 2 | .blocked => 3)

def budgetFixture (size : Nat) : Budget :=
  { limit := fun _ => size + 100, spent := fun _ => 0,
    pending := (List.range size).map fun id => { id := id, bound := fun _ => 1 },
    seen := List.range size }

@[noinline] def reserveProbe (optimized : Bool) (b : Budget) (id : Nat) : Nat :=
  let t : Ticket := { id := id, bound := fun _ => 1 }
  let result := if optimized then reserveOptimized b t else reserve b t
  match result with
  | none => 1
  | some next => next.limit 0 + next.pending.length

@[noinline] def settleProbe (b : Budget) (id : Nat) : Nat :=
  match settle b id (fun _ => 1) with
  | none => 1
  | some next => next.spent 0 + next.pending.length

def measureCase (name : String) (size iterations : Nat) (action : Nat → Nat) : IO Unit := do
  -- Warm-up and a consumed checksum prevent dead-code elimination. Timing excludes setup.
  let mut checksum := action 0
  let mut timings : List Nat := []
  for sample in List.range 15 do
    let start ← IO.monoNanosNow
    for k in List.range iterations do
      checksum := checksum + action (sample * iterations + k + 1)
    let stop ← IO.monoNanosNow
    timings := (stop - start) / iterations :: timings
  let sorted := timings.mergeSort (· ≤ ·)
  let median := sorted[7]!
  let p95 := sorted[14]!
  IO.println (Lean.Json.mkObj [
    ("case", Lean.toJson name), ("size", Lean.toJson size),
    ("iterations", Lean.toJson iterations), ("samples", Lean.toJson (15 : Nat)),
    ("p50_batch_mean_ns", Lean.toJson median), ("p95_batch_mean_ns", Lean.toJson p95),
    ("checksum", Lean.toJson checksum)]).compress

public def main (args : List String) : IO Unit := do
  let iterations := (args.head?.bind String.toNat?).getD 20
  if iterations == 0 || iterations > 10000 then
    throw (IO.userError "iterations must be in 1..10000")
  for size in [10, 100, 1000, 10000] do
    let ledger := ledgerFixture size
    let last := benchRequest (size - 1) (size - 1)
    let first := benchRequest 0 0
    if (ledgerStep benchPolicy ledger benchContext last).outcome != .replayed ||
        (ledgerStep benchPolicy ledger benchContext (benchRequest size size)).outcome != .committed then
      throw (IO.userError "invalid ledger benchmark fixture")
    measureCase "ledger.commit" size iterations fun seed =>
      ledgerProbe ledger (benchRequest (size + seed) size)
    measureCase "ledger.retry_oldest" size iterations fun _ => ledgerProbe ledger first
    measureCase "ledger.retry_newest" size iterations fun _ => ledgerProbe ledger last
    measureCase "ledger.stale" size iterations fun seed =>
      ledgerProbe ledger (benchRequest (size + seed) (size - 1))
    let budget := budgetFixture size
    for optimized in [false, true] do
      let suffix := if optimized then "optimized" else "reference"
      measureCase ("budget.reserve." ++ suffix) size iterations fun seed =>
        reserveProbe optimized budget (size + seed)
      let full := { budget with limit := fun _ => size }
      measureCase ("budget.reject." ++ suffix) size iterations fun seed =>
        reserveProbe optimized full (size + seed)
    measureCase "budget.settle_first" size iterations fun _ => settleProbe budget 0
    measureCase "budget.settle_last" size iterations fun _ => settleProbe budget (size - 1)
