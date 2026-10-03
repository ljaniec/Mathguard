module

public import Mathguard.Spec
import Mathlib.Order.Lattice
import Mathlib.Tactic.FinCases

/-!
# Mathguard information-flow kernel: proofs

Labels carry independent confidentiality and provenance (trust) components; `joinLabel`
is the componentwise maximum. We prove

* `joinLabel` is a least upper bound for `labelLE` and is associative;
* the context label of an observation trace never decreases and dominates every
  observed label;
* the output gate `flowAllowed` enforces sink clearance and the untrusted-data flag;
* semantic restrictions can only remove hard-permitted effects;
* concrete witnesses: a denied secret export and two accepted exports.

These are label-enforcement facts only: no noninterference, classifier accuracy, or
injection-detection claim follows from them.
-/

public section

namespace Mathguard

/-! ### Order structure of labels -/

theorem labelLE_refl (a : Label) : labelLE a a :=
  ⟨le_rfl, le_rfl⟩

theorem labelLE_trans {a b c : Label} (hab : labelLE a b) (hbc : labelLE b c) :
    labelLE a c :=
  ⟨hab.1.trans hbc.1, hab.2.trans hbc.2⟩

theorem label_join_upper_left (a b : Label) : labelLE a (joinLabel a b) :=
  ⟨le_max_left _ _, le_max_left _ _⟩

theorem label_join_upper_right (a b : Label) : labelLE b (joinLabel a b) :=
  ⟨le_max_right _ _, le_max_right _ _⟩

theorem label_join_least (a b upper : Label)
    (ha : labelLE a upper) (hb : labelLE b upper) :
    labelLE (joinLabel a b) upper :=
  ⟨max_le ha.1 hb.1, max_le ha.2 hb.2⟩

theorem label_join_associative (a b c : Label) :
    joinLabel (joinLabel a b) c = joinLabel a (joinLabel b c) := by
  simp only [joinLabel, max_assoc]

/-- Joining on the right is monotone in the left argument. -/
theorem labelLE_joinLabel_left {a b : Label} (h : labelLE a b) (c : Label) :
    labelLE (joinLabel a c) (joinLabel b c) :=
  label_join_least _ _ _ (labelLE_trans h (label_join_upper_left b c))
    (label_join_upper_right b c)

/-! ### Context traces -/

@[simp] theorem contextRun_nil (initial : Label) : contextRun initial [] = initial := rfl

@[simp] theorem contextRun_cons (initial l : Label) (observations : List Label) :
    contextRun initial (l :: observations) = contextRun (joinLabel initial l) observations :=
  rfl

/-- The context label is monotone in its starting label. -/
theorem contextRun_mono {a b : Label} (h : labelLE a b) (observations : List Label) :
    labelLE (contextRun a observations) (contextRun b observations) := by
  induction observations generalizing a b with
  | nil => exact h
  | cons l obs ih => exact ih (labelLE_joinLabel_left h l)

theorem label_trace_never_lowers (initial : Label) (observations : List Label) :
    labelLE initial (contextRun initial observations) := by
  induction observations generalizing initial with
  | nil => exact labelLE_refl initial
  | cons l obs ih => exact labelLE_trans (label_join_upper_left initial l) (ih _)

theorem label_trace_contains_observation (initial : Label) (observations : List Label)
    (label : Label) (h : label ∈ observations) :
    labelLE label (contextRun initial observations) := by
  induction observations generalizing initial with
  | nil => simp at h
  | cons l obs ih =>
    rcases List.mem_cons.1 h with rfl | h
    · exact labelLE_trans (label_join_upper_right initial label)
        (label_trace_never_lowers _ obs)
    · exact ih _ h

/-! ### Output gate -/

theorem flowAllowed_eq_true_iff (label : Label) (sink : Sink) :
    flowAllowed label sink = true ↔
      label.confidentiality ≤ sink.clearance ∧
        (label.trust = 0 ∨ sink.acceptsUntrusted = true) := by
  simp [flowAllowed]

theorem output_clearance_enforced (label : Label) (sink : Sink)
    (h : flowAllowed label sink = true) :
    label.confidentiality ≤ sink.clearance :=
  ((flowAllowed_eq_true_iff label sink).1 h).1

theorem public_sink_rejects_sensitive (label : Label) (sink : Sink)
    (hs : sink.clearance = 0) (hl : 0 < label.confidentiality.val) :
    flowAllowed label sink = false := by
  rw [Bool.eq_false_iff]
  intro h
  have h₁ := output_clearance_enforced label sink h
  rw [hs, Fin.le_iff_val_le_val] at h₁
  simp at h₁
  omega

theorem trust_gate_enforced (label : Label) (sink : Sink)
    (h : flowAllowed label sink = true) (hu : label.trust = 1) :
    sink.acceptsUntrusted = true := by
  rcases ((flowAllowed_eq_true_iff label sink).1 h).2 with h₀ | h₁
  · exact absurd (hu.symm.trans h₀) (by decide)
  · exact h₁

/-! ### Hard and semantic gates -/

theorem semantic_cannot_override_hard (semantic : Bool) :
    hardSemanticPermit false semantic = false := rfl

theorem semantic_veto (hard : Bool) :
    hardSemanticPermit hard false = false := by
  cases hard <;> rfl

theorem final_effects_subset_hard {α : Type} (hard semantic : α → Prop) (effect : α)
    (h : allowedEffects hard semantic effect) : hard effect :=
  h.1

theorem semantic_tightening_never_adds_effect {α : Type}
    (hard oldSemantic newSemantic : α → Prop)
    (ht : ∀ effect, newSemantic effect → oldSemantic effect) (effect : α)
    (h : allowedEffects hard newSemantic effect) :
    allowedEffects hard oldSemantic effect :=
  ⟨h.1, ht _ h.2⟩

/-! ### Nonvacuity witnesses -/

theorem demo_secret_export_denied : flowAllowed secretUntrusted publicSink = false := by
  decide

theorem demo_internal_export_allowed : flowAllowed secretUntrusted internalSink = true := by
  decide

theorem demo_public_export_allowed : flowAllowed publicTrusted publicSink = true := by
  decide

end Mathguard

end
