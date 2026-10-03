import Lean
import Mathguard.Spec
import Mathguard.OptimizedBudget

/-! Private JSONL adapter. Executes the reviewed kernels; parsing, IO and their
composition are tested runtime code, not additional formal-verification claims. -/
open Lean
namespace Mathguard.Worker
open Mathguard

structure State where
  ledger : Ledger 3 := initialLedger demoGenesis
  budget : Budget := initialBudget (fun _ => 0)
  policy : Policy 3 := demoPolicy
  initialized : Bool := false
  nextTicket : Nat := 0

def field (j : Json) (k : String) : Except String Json := j.getObjVal? k
def nat (j : Json) (k : String) : Except String Nat := do (← field j k).getNat?
def str (j : Json) (k : String) : Except String String := do (← field j k).getStr?
def fin3 (n : Nat) : Except String (Fin 3) :=
  if h : n < 3 then .ok ⟨n, h⟩ else .error "account out of range"
def usage (j : Json) : Except String Usage := do
  let a ← j.getArr?
  if a.size != 4 then throw "four resources required"
  let values ← a.mapM Json.getNat?
  return fun i => values[i.val]!
def uj (u : Usage) : Json := toJson ((List.finRange 4).map u)
def request (j : Json) : Except String (Request 3) := do
  return { id := (← nat j "id"), source := (← fin3 (← nat j "source")), destination := (← fin3 (← nat j "destination")), amount := (← nat j "amount"), expectedRevision := (← nat j "expectedRevision"), policyEpoch := (← nat j "policyEpoch") }
def context (j : Json) : Except String (Context 3) := do
  let mut approval := none
  let a ← field j "approval"
  if a != Json.null then
    approval := some { nonce := (← nat a "nonce"), principal := (← nat a "principal"), boundRequest := (← request (← field a "boundRequest")), expires := (← nat a "expires") }
  return { principal := (← nat j "principal"), now := (← nat j "now"), approval }
def snapshot (s : State) : Json := Json.mkObj [
  ("revision", toJson s.ledger.revision),
  ("balances", toJson ((List.finRange 3).map s.ledger.balances)),
  ("debited", toJson ((List.finRange 3).map s.ledger.debited)),
  ("journal_length", toJson s.ledger.journal.length),
  ("epoch", toJson s.policy.epoch), ("limit", uj s.budget.limit),
  ("spent", uj s.budget.spent), ("reserved", uj (reserved s.budget)),
  ("pending", toJson s.budget.pending.length)]
def result (s : State) (outcome reason : String) : Json := Json.mkObj [
  ("outcome", toJson outcome), ("reason", toJson reason), ("state", snapshot s)]
def blockReason (s : State) (ctx : Context 3) (q : Request 3) : String :=
  if (lookupId s.ledger q.id).isSome then "IDEMPOTENCY_CONFLICT"
  else if q.policyEpoch != s.policy.epoch then "STALE_POLICY"
  else if q.expectedRevision != s.ledger.revision then "STALE_REVISION"
  else if s.policy.owner q.source != ctx.principal then "OWNER_MISMATCH"
  else if !s.policy.transferEnabled ctx.principal then "CAPABILITY_DENIED"
  else if !s.policy.beneficiaryAllowed ctx.principal q.destination then "BENEFICIARY_DENIED"
  else if q.source == q.destination then "SAME_ACCOUNT"
  else if q.amount == 0 then "AMOUNT_INVALID"
  else if q.amount > s.policy.maxTransfer then "TRANSFER_CAP"
  else if q.amount > s.ledger.balances q.source then "INSUFFICIENT_FUNDS"
  else if s.ledger.debited q.source + q.amount > s.policy.debitCap q.source then "DEBIT_CAP"
  else "APPROVAL_INVALID"

def dispatch (s : State) (j : Json) : Except String (State × Json) := do
  let op ← str j "op"
  if op == "snapshot" then return (s, snapshot s)
  if op == "configure" then
    let epoch ← nat j "epoch"
    if s.initialized && epoch ≤ s.policy.epoch then throw "epoch must increase"
    let limit ← usage (← field j "limit")
    let some b := budgetReconfigure s.budget limit | throw "limit below spent plus reserved"
    let p := { s.policy with epoch, maxTransfer := (← nat j "maxTransfer"), approvalThreshold := (← nat j "approvalThreshold") }
    let s' := { s with policy := p, budget := b, initialized := true }
    return (s', snapshot s')
  if !s.initialized then throw "worker not configured"
  if op == "reserve" then
    let bound ← usage (← field j "bound")
    let t : Ticket := { id := s.nextTicket, bound }
    let some b := reserveOptimized s.budget t |
      return (s, result s "BLOCKED" "BUDGET_EXHAUSTED")
    let s' := { s with budget := b, nextTicket := s.nextTicket + 1 }
    return (s', Json.mkObj [("ticket", toJson t.id), ("state", snapshot s')])
  if op == "settle" || op == "charge" then
    let id ← nat j "ticket"
    let b? ← if op == "charge" then pure (chargeBound s.budget id)
      else pure (settle s.budget id (← usage (← field j "actual")))
    let some b := b? | throw "invalid settlement"
    let s' := { s with budget := b }
    return (s', snapshot s')
  if op == "flow" then
    let conf ← nat j "confidentiality"
    let trust ← nat j "trust"
    let clearance ← nat j "clearance"
    if h : trust < 2 then
      let label : Label := { confidentiality := (← fin3 conf), trust := ⟨trust, h⟩ }
      let sink : Sink := { clearance := (← fin3 clearance), acceptsUntrusted := (← (← field j "acceptsUntrusted").getBool?) }
      return (s, toJson (flowAllowed label sink))
    else throw "invalid trust"
  if op == "preview" || op == "execute" then
    let q ← request (← field j "request")
    let ctx ← context (← field j "context")
    let r := ledgerStep s.policy s.ledger ctx q
    if r.outcome == .replayed then return (s, result s "REPLAYED" "EXACT_RETRY")
    if r.outcome == .blocked then
      -- A synthetic approval is used only to test the remaining predicates;
      -- it never enters ledgerStep's committing path or the returned state.
      let probe : Context 3 := { ctx with approval := some { nonce := s.ledger.consumedApprovals.foldl max 0 + 1, principal := ctx.principal, boundRequest := q, expires := ctx.now } }
      if ctx.approval.isNone && admission s.policy s.ledger probe q then
        let capacity : Ticket := { id := s.nextTicket, bound := fun r => if r = 3 then 1 else 0 }
        if (reserveOptimized s.budget capacity).isNone then
          return (s, result s "BLOCKED" "BUDGET_EXHAUSTED")
        return (s, result s "PENDING_APPROVAL" "APPROVAL_REQUIRED")
      return (s, result s "BLOCKED" (blockReason s ctx q))
    let t : Ticket := { id := s.nextTicket, bound := fun r => if r = 3 then 1 else 0 }
    let some reservedBudget := reserveOptimized s.budget t |
      return (s, result s "BLOCKED" "BUDGET_EXHAUSTED")
    if op == "preview" then return (s, result s "ALLOWED" "READY")
    let some settledBudget := chargeBound reservedBudget t.id | throw "internal settlement failure"
    let s' := { s with ledger := r.state, budget := settledBudget, nextTicket := s.nextTicket + 1 }
    return (s', result s' "COMMITTED" "ADMITTED")
  throw "unknown operation"

partial def loop (stdin stdout : IO.FS.Stream) (s : State) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let (s', response) := match Json.parse line >>= dispatch s with
    | .ok pair => pair
    | .error _ => (s, Json.mkObj [("error", toJson "WORKER_REQUEST_REJECTED")])
  stdout.putStrLn response.compress
  stdout.flush
  loop stdin stdout s'
end Mathguard.Worker

def main : IO Unit := do
  Mathguard.Worker.loop (← IO.getStdin) (← IO.getStdout) {}
