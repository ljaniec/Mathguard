/- NEXT REQUEST W1. Typed wire projection, not a JSON/parser/authentication theorem.
Integers below are already strictly parsed natural numbers. Preserve that boundary. -/
import Mathguard

namespace Mathguard.Next

structure WireTransfer where
  id : Nat
  sourceIndex : Nat
  destinationIndex : Nat
  amount : Nat
  expectedRevision : Nat
  policyEpoch : Nat
  deriving DecidableEq, Repr

def toWire {n : Nat} (q : Request n) : WireTransfer :=
  { id := q.id, sourceIndex := q.source.val, destinationIndex := q.destination.val,
    amount := q.amount, expectedRevision := q.expectedRevision, policyEpoch := q.policyEpoch }

def fromWire (n : Nat) (wire : WireTransfer) : Option (Request n) :=
  if hs : wire.sourceIndex < n then
    if hd : wire.destinationIndex < n then
      some { id := wire.id, source := ⟨wire.sourceIndex, hs⟩,
        destination := ⟨wire.destinationIndex, hd⟩, amount := wire.amount,
        expectedRevision := wire.expectedRevision, policyEpoch := wire.policyEpoch }
    else none
  else none

theorem wire_roundtrip {n : Nat} (q : Request n) : fromWire n (toWire q) = some q := by
  sorry

theorem wire_decode_preserves_fields (n : Nat) (wire : WireTransfer) (q : Request n)
    (h : fromWire n wire = some q) : toWire q = wire := by
  sorry

theorem wire_projection_injective {n : Nat} (q q' : Request n)
    (h : toWire q = toWire q') : q = q' := by
  sorry

theorem wire_source_out_of_range (n : Nat) (wire : WireTransfer)
    (h : n ≤ wire.sourceIndex) : fromWire n wire = none := by
  sorry

theorem wire_destination_out_of_range (n : Nat) (wire : WireTransfer)
    (h : n ≤ wire.destinationIndex) : fromWire n wire = none := by
  sorry

theorem wire_valid_indices_decode (n : Nat) (wire : WireTransfer)
    (hs : wire.sourceIndex < n) (hd : wire.destinationIndex < n) :
    ∃ q, fromWire n wire = some q := by
  sorry

theorem wire_approval_cannot_match_changed_fields {n : Nat} (a : Approval n)
    (q : Request n) (h : toWire a.boundRequest ≠ toWire q) : a.boundRequest ≠ q := by
  sorry

theorem demo_wire_decodes : fromWire 3 (toWire demoRequest) = some demoRequest := by
  sorry

theorem demo_wire_rejects_unknown_account :
    fromWire 3 { (toWire demoRequest) with sourceIndex := 3 } = none := by
  sorry

end Mathguard.Next
