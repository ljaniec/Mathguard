import Mathguard.Worker

/-! Definition-only release request model. This is outside the production build.
It supplies concrete targets for the handoff; no new proof or runtime replacement
is claimed. `executeCore` models the financial state publication in Worker.dispatch,
not the host's earlier semantic/provider work or its pending-approval presentation.
-/

namespace Mathguard.Release
open Lean
open Mathguard

def FinancialInvariant (s : Worker.State) : Prop :=
  LedgerInvariant demoGenesis s.ledger ∧ BudgetInvariant s.budget

def financialTicket (s : Worker.State) : Ticket :=
  { id := s.nextTicket, bound := fun r => if r = 3 then 1 else 0 }

structure ExecuteResult where
  state : Worker.State
  outcome : LedgerOutcome

def executeCore (s : Worker.State) (ctx : Context 3) (q : Request 3) : ExecuteResult :=
  let r := ledgerStep s.policy s.ledger ctx q
  if r.outcome = .committed then
    let t := financialTicket s
    match reserveOptimized s.budget t with
    | none => { state := s, outcome := .blocked }
    | some reservedBudget =>
        match chargeBound reservedBudget t.id with
        | none => { state := s, outcome := .blocked }
        | some chargedBudget =>
            { state := { s with ledger := r.state, budget := chargedBudget,
                                nextTicket := s.nextTicket + 1 },
              outcome := .committed }
  else
    { state := s, outcome := r.outcome }

def requestJson (q : Request 3) : Json := Json.mkObj [
  ("id", toJson q.id), ("source", toJson q.source.val),
  ("destination", toJson q.destination.val), ("amount", toJson q.amount),
  ("expectedRevision", toJson q.expectedRevision), ("policyEpoch", toJson q.policyEpoch)]

def approvalJson (a : Approval 3) : Json := Json.mkObj [
  ("nonce", toJson a.nonce), ("principal", toJson a.principal),
  ("boundRequest", requestJson a.boundRequest), ("expires", toJson a.expires)]

def contextJson (ctx : Context 3) : Json := Json.mkObj [
  ("principal", toJson ctx.principal), ("now", toJson ctx.now),
  ("approval", ctx.approval.map approvalJson |>.getD Json.null)]

def executeJson (ctx : Context 3) (q : Request 3) : Json := Json.mkObj [
  ("op", toJson ("execute" : String)), ("context", contextJson ctx),
  ("request", requestJson q)]

/-- Completed private worker command. Storage integrity/ownership is a separate premise. -/
structure Completed where
  command : Json
  response : Json

/-- The worker loop preserves state and emits a fixed error frame on dispatch rejection. -/
def workerFrame (s : Worker.State) (command : Json) : Worker.State × Json :=
  match Worker.dispatch s command with
  | .ok pair => pair
  | .error _ => (s, Json.mkObj [("error", toJson ("WORKER_REQUEST_REJECTED" : String))])

/-- Replay succeeds only if each exact computed response matches its recorded response. -/
def replayCompleted : Worker.State → List Completed → Except String Worker.State
  | s, [] => .ok s
  | s, e :: es => do
      let (next, response) := workerFrame s e.command
      if response == e.response then replayCompleted next es
      else throw "recorded worker response mismatch"

/-- Full typed generic interaction binding, stronger than an unqualified hash equality. -/
structure BoundInteraction where
  principal : Nat
  session : String
  kind : String
  target : String
  originalContent : String
  policyEpoch : Nat
  feedVersion : Nat
  deriving DecidableEq

structure GenericApproval where
  binding : BoundInteraction
  expires : Nat
  used : Bool
  deriving DecidableEq

def genericApprovalValid (a : GenericApproval) (b : BoundInteraction) (now : Nat) : Bool :=
  decide (a.binding = b ∧ now ≤ a.expires ∧ a.used = false)

def consumeGenericApproval (a : GenericApproval) (b : BoundInteraction) (now : Nat) :
    Option GenericApproval :=
  if genericApprovalValid a b now then some { a with used := true } else none

end Mathguard.Release
