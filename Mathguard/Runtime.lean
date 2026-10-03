module

public import Mathguard.Spec

/-!
# Mathguard runtime commit boundary

The pure kernel `ledgerStep` is the only function that computes a new ledger state.
This module wraps it in a mutable cell so a runtime can execute the *reviewed* transition
through a single atomic update: `atomicLedgerStep` reads the current state, runs
`ledgerStep`, and installs the resulting state in one `IO.Ref.modifyGet`, so concurrent
callers are serialised and every installed state is `(ledgerStep p s ctx q).state` for the
state `s` it replaced. The proved properties of `ledgerStep` therefore describe each
committed state change; persistence, authentication and the adapters that build `Context`
remain outside the model.

Everything here is computable and is compiled to C together with the kernel.

This cell is VOLATILE: no durability or crash-recovery guarantee is supplied.
`ledgerUpdate_eq` is a pure definitional equality, not a verified IO concurrency theorem.
The runtime primitive supplies atomic reference modification; authentication,
policy/approval provenance, combined budget state, and persistence remain external.
-/

@[expose] public section

namespace Mathguard

/-- A mutable ledger cell owned by the runtime. -/
abbrev LedgerCell (n : Nat) := IO.Ref (Ledger n)

/-- Create a ledger cell at genesis. -/
def LedgerCell.genesis {n : Nat} (genesis : Account n → Nat) : BaseIO (LedgerCell n) :=
  IO.mkRef (initialLedger genesis)

/-- The pure update performed by `atomicLedgerStep`: the outcome together with the next
state, both computed by the reviewed kernel `ledgerStep`. -/
def ledgerUpdate {n : Nat} (p : Policy n) (ctx : Context n) (q : Request n)
    (s : Ledger n) : LedgerOutcome × Ledger n :=
  let r := ledgerStep p s ctx q
  (r.outcome, r.state)

theorem ledgerUpdate_eq {n : Nat} (p : Policy n) (ctx : Context n) (q : Request n)
    (s : Ledger n) :
    ledgerUpdate p ctx q s = ((ledgerStep p s ctx q).outcome, (ledgerStep p s ctx q).state) :=
  rfl

/-- Return the result and install its state from the same kernel evaluation. -/
def ledgerResultUpdate {n : Nat} (p : Policy n) (ctx : Context n) (q : Request n)
    (s : Ledger n) : LedgerResult n × Ledger n :=
  let r := ledgerStep p s ctx q
  (r, r.state)

theorem ledgerResultUpdate_eq {n : Nat} (p : Policy n) (ctx : Context n)
    (q : Request n) (s : Ledger n) :
    ledgerResultUpdate p ctx q s =
      (ledgerStep p s ctx q, (ledgerStep p s ctx q).state) := rfl

/-- The returned snapshot belongs to this transition, even if another caller
advances the cell before the recipient renders it. This is internal state, not
an authenticated public receipt; adapters must authorize and mask its fields. -/
def atomicLedgerStepResult {n : Nat} (cell : LedgerCell n) (p : Policy n)
    (ctx : Context n) (q : Request n) : BaseIO (LedgerResult n) :=
  cell.modifyGet (ledgerResultUpdate p ctx q)

/-- Execute one reviewed transition atomically on a volatile in-memory ledger cell.
This operation does not persist a receipt or prove database/whole-stack atomicity. -/
def atomicLedgerStep {n : Nat} (cell : LedgerCell n) (p : Policy n) (ctx : Context n)
    (q : Request n) : BaseIO LedgerOutcome := do
  return (← atomicLedgerStepResult cell p ctx q).outcome

/-- Read current balances independently of any earlier transition (account order).
This demo helper is NOT a commit-correlated receipt: a concurrent call may have
advanced the cell before this read. Production receipts must be returned from
the same authoritative update/transaction with their checked revision. -/
def LedgerCell.balances {n : Nat} (cell : LedgerCell n) : BaseIO (List Nat) := do
  let s ← cell.get
  return List.ofFn s.balances

end Mathguard

end
