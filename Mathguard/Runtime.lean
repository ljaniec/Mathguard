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

/-- Execute one reviewed transition atomically on a ledger cell. -/
def atomicLedgerStep {n : Nat} (cell : LedgerCell n) (p : Policy n) (ctx : Context n)
    (q : Request n) : BaseIO LedgerOutcome :=
  cell.modifyGet (ledgerUpdate p ctx q)

/-- Read the current balances of a ledger cell as a list (account order). -/
def LedgerCell.balances {n : Nat} (cell : LedgerCell n) : BaseIO (List Nat) := do
  let s ← cell.get
  return List.ofFn s.balances

end Mathguard

end
