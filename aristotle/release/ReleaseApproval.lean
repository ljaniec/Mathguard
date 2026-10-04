import RuntimeSpec

/-!
# H3 — exact generic approval binding and nonce freshness

Checked results for the unchanged `RuntimeSpec` definitions `BoundInteraction`,
`GenericApproval`, `genericApprovalValid` and `consumeGenericApproval`, together with a
small admission model connecting a generic approval to the existing G1 gate
(`Mathguard.Control.gate`) and a monotone ledger-approval nonce allocator.

The issuance/admission/allocator definitions in this file are proposed models for review
(the handoff asks for them to be defined); they are not taken from the host. Owner
authentication, the server-side principal/session derivation, clock consistency,
serialized consumption and canonical binding bytes remain explicit host assumptions. No
claim is made about SHA-256 or any digest: the binding compared here is the full typed
record.
-/

namespace Mathguard.Release
open Mathguard Mathguard.Control

/-! ## H3 targets 1–3 -/

/-- **H3.1.** Validity is exactly: identical binding, not expired, not used. -/
theorem genericApprovalValid_iff (a : GenericApproval) (b : BoundInteraction) (now : Nat) :
    genericApprovalValid a b now = true ↔ a.binding = b ∧ now ≤ a.expires ∧ a.used = false := by
  simp [genericApprovalValid]

/-- **H3.1, field by field.** A valid approval matches every binding field exactly. -/
theorem genericApprovalValid_fields {a : GenericApproval} {b : BoundInteraction} {now : Nat}
    (h : genericApprovalValid a b now = true) :
    a.binding.principal = b.principal ∧ a.binding.session = b.session ∧
      a.binding.kind = b.kind ∧ a.binding.target = b.target ∧
      a.binding.originalContent = b.originalContent ∧
      a.binding.policyEpoch = b.policyEpoch ∧ a.binding.feedVersion = b.feedVersion ∧
      now ≤ a.expires ∧ a.used = false := by
  obtain ⟨rfl, hexp, hused⟩ := (genericApprovalValid_iff a b now).1 h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, hexp, hused⟩

theorem consumeGenericApproval_eq_some_iff (a a' : GenericApproval) (b : BoundInteraction)
    (now : Nat) :
    consumeGenericApproval a b now = some a' ↔
      genericApprovalValid a b now = true ∧ a' = { a with used := true } := by
  unfold consumeGenericApproval
  split_ifs with h <;> simp [h, eq_comm]

/-- **H3.2.** Consumption against any interaction whose binding differs from the approved
one (session, kind, target, original content, policy epoch, feed version or principal)
is rejected, at every time. -/
theorem consume_rejects_other_binding (a : GenericApproval) (b : BoundInteraction) (now : Nat)
    (hb : a.binding ≠ b) : consumeGenericApproval a b now = none := by
  simp [consumeGenericApproval, genericApprovalValid, hb]

/-- **H3.2.** Changing any field of an interaction that a valid approval matches makes
consumption fail, at any time. -/
theorem consume_rejects_changed_interaction {a : GenericApproval} {b b' : BoundInteraction}
    {now : Nat} (hv : genericApprovalValid a b now = true) (hne : b' ≠ b) (now' : Nat) :
    consumeGenericApproval a b' now' = none := by
  obtain ⟨rfl, -, -⟩ := (genericApprovalValid_iff a b now).1 hv
  exact consume_rejects_other_binding a b' now' (Ne.symm hne)

/-- In particular, approving sanitized text does not authorize different original bytes. -/
theorem consume_rejects_changed_content {a : GenericApproval} {b : BoundInteraction} {now : Nat}
    (hv : genericApprovalValid a b now = true) (content : String)
    (hc : content ≠ b.originalContent) (now' : Nat) :
    consumeGenericApproval a { b with originalContent := content } now' = none :=
  consume_rejects_changed_interaction hv (fun h => hc (by rw [← h])) now'

/-- …and an approval does not survive a feed-version or policy-epoch change. -/
theorem consume_rejects_changed_config {a : GenericApproval} {b : BoundInteraction} {now : Nat}
    (hv : genericApprovalValid a b now = true) (epoch feed : Nat)
    (hc : epoch ≠ b.policyEpoch ∨ feed ≠ b.feedVersion) (now' : Nat) :
    consumeGenericApproval a { b with policyEpoch := epoch, feedVersion := feed } now' = none := by
  refine consume_rejects_changed_interaction hv (fun h => ?_) now'
  rcases hc with hc | hc
  · exact hc (by rw [← h])
  · exact hc (by rw [← h])

/-- **H3.3.** A successful consume marks the approval used and changes nothing else. -/
theorem consume_marks_used {a a' : GenericApproval} {b : BoundInteraction} {now : Nat}
    (h : consumeGenericApproval a b now = some a') :
    a'.used = true ∧ a'.binding = a.binding ∧ a'.expires = a.expires := by
  obtain ⟨-, rfl⟩ := (consumeGenericApproval_eq_some_iff a a' b now).1 h
  exact ⟨rfl, rfl, rfl⟩

/-- **H3.3.** A consumed approval can never be consumed again — for any interaction and at
any time, including the same timestamp. -/
theorem consume_twice_fails {a a' : GenericApproval} {b : BoundInteraction} {now : Nat}
    (h : consumeGenericApproval a b now = some a') (b' : BoundInteraction) (now' : Nat) :
    consumeGenericApproval a' b' now' = none := by
  obtain ⟨-, rfl⟩ := (consumeGenericApproval_eq_some_iff a a' b now).1 h
  simp [consumeGenericApproval, genericApprovalValid]

/-- **H3.3.** Expiry is checked at consumption time: after `expires` nothing is consumed,
whatever happened in between (for example semantic work). -/
theorem consume_after_expiry_fails (a : GenericApproval) (b : BoundInteraction) {now : Nat}
    (h : a.expires < now) : consumeGenericApproval a b now = none := by
  simp only [consumeGenericApproval, genericApprovalValid]
  rw [if_neg]
  simp only [decide_eq_true_eq, not_and]
  intro _ hle
  omega

/-! ## H3 target 4: issuance and final admission (proposed model) -/

/-- Issuance by an authenticated owner: a fresh, unused approval of the exact binding.
Issuance is a pure function of its arguments; in particular it does not take or return any
worker, ledger or budget state, so it cannot cause an effect or a charge. -/
def issueGenericApproval (ownerAuthenticated : Bool) (b : BoundInteraction) (expires : Nat) :
    Option GenericApproval :=
  if ownerAuthenticated then some { binding := b, expires, used := false } else none

theorem issue_some_iff (owner : Bool) (b : BoundInteraction) (expires : Nat) (a : GenericApproval) :
    issueGenericApproval owner b expires = some a ↔
      owner = true ∧ a = { binding := b, expires, used := false } := by
  unfold issueGenericApproval
  split_ifs with h <;> simp [h, eq_comm]

/-- A freshly issued approval is valid exactly for its binding until it expires. -/
theorem issued_valid {owner : Bool} {b : BoundInteraction} {expires : Nat} {a : GenericApproval}
    (h : issueGenericApproval owner b expires = some a) (b' : BoundInteraction) (now : Nat) :
    genericApprovalValid a b' now = true ↔ b = b' ∧ now ≤ expires := by
  obtain ⟨-, rfl⟩ := (issue_some_iff owner b expires a).1 h
  simp [genericApprovalValid]

/-- Final admission of a generic interaction: the independently computed G1 gate, evaluated
with the approval flag set to the *current* validity of the approval for the exact bound
interaction, and the budget admission. -/
def genericAdmit (p : ControlPolicy) (steps : Nat) (i : Interaction) (sem : SemanticResult)
    (a : GenericApproval) (b : BoundInteraction) (now : Nat) (budgetOk : Bool) : Bool :=
  (gate p steps { i with approved := genericApprovalValid a b now } sem).executes && budgetOk

theorem combine_executes_false_of_right {d e : Decision} (h : e.deny = true ∨ e.ask = true) :
    (d.combine e).executes = false := by
  rcases h with h | h <;> simp [Decision.combine, Decision.executes, h]

/-- **H3.4.** A semantic review or block verdict prevents dispatch whatever the approval
says (a valid owner approval does not override the semantic layer). -/
theorem semantic_review_blocks_despite_approval (p : ControlPolicy) (steps : Nat)
    (i : Interaction) (r : Nat) (hr : p.semReviewAt ≤ r) (approved : Bool) :
    (gate p steps { i with approved } (.risk r)).executes = false := by
  apply combine_executes_false_of_right
  right
  simp [semanticDecision, Decision.combine, Decision.when, hr, Decision.askBy]

/-- **H3.4.** Under balanced or strict fallback, an unavailable semantic guard is not an
owner-overridable approval request: dispatch stays blocked whatever the approval says. -/
theorem unavailable_blocks_despite_approval (p : ControlPolicy) (steps : Nat) (i : Interaction)
    (sem : SemanticResult) (hsem : sem = .timeout ∨ sem = .malformed)
    (hstrict : p.strictness ≠ .permissive) (approved : Bool) :
    (gate p steps { i with approved } sem).executes = false := by
  apply combine_executes_false_of_right
  right
  have : 1 ≤ p.strictness.rank := by
    cases h : p.strictness <;> simp_all [Strictness.rank]
  rcases hsem with rfl | rfl <;> simp [semanticDecision, fallbackDecision, this]

/-- **H3.4.** Admission of an irreversible tool call requires a currently valid approval
of the exact bound interaction (binding equal, unexpired, unused) and budget admission. -/
theorem genericAdmit_irreversible {p : ControlPolicy} {steps : Nat} {i : Interaction}
    {sem : SemanticResult} {a : GenericApproval} {b : BoundInteraction} {now budgetOk : _}
    {t : Nat} (hk : i.kind = .toolCall t) (hirr : t ∈ p.irreversibleTools)
    (h : genericAdmit p steps i sem a b now budgetOk = true) :
    a.binding = b ∧ now ≤ a.expires ∧ a.used = false ∧ budgetOk = true := by
  unfold genericAdmit at h
  simp only [Bool.and_eq_true] at h
  obtain ⟨hg, hb⟩ := h
  refine ⟨?_, ?_, ?_, hb⟩ <;>
  · by_contra hc
    have hv : genericApprovalValid a b now = false := by
      simp only [genericApprovalValid, decide_eq_false_iff_not, not_and]
      tauto
    revert hg
    simp [gate, hardDecision, kindDecision, hk, hirr, hv, Decision.combine, Decision.when,
      Decision.executes, Decision.askBy]

/-! ## H3 target 5: ledger approval nonce allocation and restart -/

theorem le_foldl_max (l : List Nat) (m : Nat) : m ≤ l.foldl max m := by
  induction l generalizing m with
  | nil => simp
  | cons y ys ih => exact le_trans (le_max_left m y) (ih _)

theorem lt_foldl_max_succ {l : List Nat} {x : Nat} (hx : x ∈ l) (m : Nat) :
    x < l.foldl max m + 1 := by
  induction l generalizing m with
  | nil => simp at hx
  | cons y ys ih =>
      simp only [List.foldl_cons]
      rcases List.mem_cons.1 hx with rfl | hx
      · exact Nat.lt_succ_of_le (le_trans (le_max_right m x) (le_foldl_max ys _))
      · exact ih hx _

/-- Monotone allocator: one more than every consumed or outstanding nonce. -/
def freshApprovalNonce (consumed outstanding : List Nat) : Nat :=
  (consumed ++ outstanding).foldl max 0 + 1

/-- **H3.5.** The allocated nonce is neither consumed nor outstanding; with `consumed` read
from the recovered ledger this holds after replay recovery as well. -/
theorem freshApprovalNonce_fresh (consumed outstanding : List Nat) :
    freshApprovalNonce consumed outstanding ∉ consumed ∧
      freshApprovalNonce consumed outstanding ∉ outstanding := by
  constructor <;> intro h <;>
  · have := lt_foldl_max_succ (l := consumed ++ outstanding)
      (x := freshApprovalNonce consumed outstanding) (by simp [h]) 0
    simp [freshApprovalNonce] at this

/-- The synthetic probe nonce used by `Worker.dispatch` is never a consumed nonce. -/
theorem probe_nonce_fresh (consumed : List Nat) : consumed.foldl max 0 + 1 ∉ consumed := by
  intro h
  have := lt_foldl_max_succ h 0
  omega

/-- **Counterexample (rejected allocator).** Allocating `length(host approvals) + 1` collides
with a nonce restored into the ledger's consumed list after restart. -/
theorem length_allocator_collides :
    let hostApprovals : List Nat := []
    let restoredConsumed : List Nat := [1]
    hostApprovals.length + 1 ∈ restoredConsumed := by
  decide

/-- Host approval references carry the boot epoch that issued them. -/
structure ApprovalRef where
  boot : Nat
  nonce : Nat
  deriving DecidableEq

/-- References are honoured only in the boot epoch that issued them. -/
def refValid (currentBoot : Nat) (r : ApprovalRef) : Bool := decide (r.boot = currentBoot)

/-- **H3.5.** After a restart (boot epoch increment), no reference issued in an earlier
boot can authorize a fresh effect. -/
theorem refs_invalid_after_restart (r : ApprovalRef) {boot : Nat} (h : r.boot ≤ boot) :
    refValid (boot + 1) r = false := by
  simp [refValid]
  omega

end Mathguard.Release
