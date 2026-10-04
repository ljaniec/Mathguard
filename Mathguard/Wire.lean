module

public import Mathguard.Spec

/-!
# W1 — exact typed wire projection

`toWire` projects a typed `Request n` onto a flat record of already-parsed natural numbers,
and `fromWire n` rebuilds the request, rejecting any account index that is not below `n`
(for `n = 0` every index is rejected). Indices are never clamped and every other field is
passed through unchanged.

This module starts *after* strict JSON parsing, canonical integer-string validation and
account-name resolution. It is not a verified JSON parser, and it neither authenticates the
caller nor constructs approvals.
-/

@[expose] public section

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
  { id := q.id,
    sourceIndex := q.source.val,
    destinationIndex := q.destination.val,
    amount := q.amount,
    expectedRevision := q.expectedRevision,
    policyEpoch := q.policyEpoch }

def fromWire (n : Nat) (wire : WireTransfer) : Option (Request n) :=
  if hs : wire.sourceIndex < n then
    if hd : wire.destinationIndex < n then
      some
        { id := wire.id,
          source := ⟨wire.sourceIndex, hs⟩,
          destination := ⟨wire.destinationIndex, hd⟩,
          amount := wire.amount,
          expectedRevision := wire.expectedRevision,
          policyEpoch := wire.policyEpoch }
    else none
  else none

theorem wire_roundtrip {n : Nat} (q : Request n) :
    fromWire n (toWire q) = some q := by
  obtain ⟨id, ⟨src, hs⟩, ⟨dst, hd⟩, amount, rev, epoch⟩ := q
  simp [fromWire, toWire, hs, hd]

theorem wire_decode_preserves_fields (n : Nat)
    (wire : WireTransfer) (q : Request n)
    (h : fromWire n wire = some q) :
    toWire q = wire := by
  unfold fromWire at h
  split_ifs at h with hs hd
  cases h
  rfl

theorem wire_projection_injective {n : Nat}
    (q q' : Request n) (h : toWire q = toWire q') :
    q = q' := by
  have h' : fromWire n (toWire q) = fromWire n (toWire q') := by rw [h]
  rw [wire_roundtrip, wire_roundtrip] at h'
  exact Option.some.inj h'

theorem wire_source_out_of_range (n : Nat)
    (wire : WireTransfer) (h : n ≤ wire.sourceIndex) :
    fromWire n wire = none := by
  simp [fromWire, Nat.not_lt.2 h]

theorem wire_destination_out_of_range (n : Nat)
    (wire : WireTransfer) (h : n ≤ wire.destinationIndex) :
    fromWire n wire = none := by
  simp [fromWire, Nat.not_lt.2 h]

theorem wire_valid_indices_decode (n : Nat)
    (wire : WireTransfer)
    (hs : wire.sourceIndex < n) (hd : wire.destinationIndex < n) :
    ∃ q, fromWire n wire = some q := by
  rw [fromWire, dif_pos hs, dif_pos hd]
  exact ⟨_, rfl⟩

theorem wire_approval_cannot_match_changed_fields {n : Nat}
    (a : Approval n) (q : Request n)
    (h : toWire a.boundRequest ≠ toWire q) :
    a.boundRequest ≠ q := by
  intro he
  exact h (congrArg toWire he)

theorem demo_wire_decodes :
    fromWire 3 (toWire demoRequest) = some demoRequest := by
  exact wire_roundtrip demoRequest

theorem demo_wire_rejects_unknown_account :
    fromWire 3 { (toWire demoRequest) with sourceIndex := 3 } = none := by
  decide

end Mathguard.Next

end
