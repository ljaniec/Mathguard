module

public import Mathlib.Data.List.Infix

/-!
# G1 — generic control-layer decision kernel

The ledger kernels (`Mathguard.Spec`) protect one high-value tool. The AI Control Layer brief
asks for a gateway that governs *every* interaction (prompts, model calls, tool/MCP calls,
model-artifact loads) from a centralized, live-editable policy. This module is the pure,
executable decision core for that gateway:

* `Decision` is a set of independent restriction flags (`deny`, `ask`, `redact`) plus reason
  codes; combining two decisions takes the union of restrictions, so no stage can relax
  another (no fake total order between ALLOW/ASK/REDACT/BLOCK);
* `hardDecision` is the deterministic layer (authentication, step limit, signature feed,
  model/tool allowlists, irreversible-action approval, artifact hash pinning and unsafe
  formats, PII thresholds); `semanticDecision` is the AI layer, including the configured
  fallback when the classifier times out or returns malformed output;
* `PolicyStore` keeps the last valid policy: an invalid reload is rejected and, with no
  valid policy ever loaded, every interaction is denied (fail closed);
* `sessionStep` runs one interaction, counts dispatches and appends exactly one audit event.

The main results are restrict-only composition, fail-closed reload, the step bound for
runaway loops, monotonicity of the whole gate under policy tightening (what judges do when
they edit the policy live), feed-signature blocking, and audit-log completeness.

Everything is computable and is compiled to C with the rest of the library. Detectors that
produce `piiScore` and the semantic `risk` are trusted adapter inputs; their accuracy is not
claimed.
-/

@[expose] public section

namespace Mathguard.Control

/-- Configurable strictness level of the semantic fallback. -/
inductive Strictness where
  | permissive | balanced | strict
  deriving DecidableEq, Repr

/-- Numeric rank of a strictness level (higher is stricter). -/
def Strictness.rank : Strictness → Nat
  | .permissive => 0
  | .balanced => 1
  | .strict => 2

/-- Reason codes reported to the audit log and dashboard. -/
inductive Reason where
  | noValidPolicy | unauthenticated | stepLimit | signatureMatch
  | modelNotAllowed | toolNotAllowed | irreversibleNeedsApproval
  | artifactNotPinned | unsafeArtifactFormat
  | piiRedacted | piiBlocked
  | semanticReview | semanticBlocked | semanticUnavailable
  deriving DecidableEq, Repr

/-- Serialisation formats of model artifacts. Pickle-based and unknown formats can execute
code on load and are never admitted (a structural rule, not a configurable one). -/
inductive ArtifactFormat where
  | safetensors | gguf | onnx | pickle | unknown
  deriving DecidableEq, Repr

/-- Formats that can be loaded without code execution. -/
def ArtifactFormat.safe : ArtifactFormat → Bool
  | .safetensors | .gguf | .onnx => true
  | .pickle | .unknown => false

/-- What the intercepted interaction tries to do. Identifiers are canonical numeric IDs
assigned by the ingress adapter from the catalog. -/
inductive Kind where
  | prompt
  | modelCall (model : Nat)
  | toolCall (tool : Nat)
  | artifactLoad (hash : Nat) (format : ArtifactFormat)
  deriving DecidableEq, Repr

/-- One intercepted interaction, after authentication and canonicalisation. `content` is the
tokenised payload (prompt, tool arguments, retrieved document or model output). -/
structure Interaction where
  principal : Nat
  authenticated : Bool
  kind : Kind
  content : List Nat
  /-- Score of the deterministic PII/secret detector (0–100). -/
  piiScore : Nat
  /-- A trusted, server-side approval record exists for this exact interaction. -/
  approved : Bool
  deriving DecidableEq, Repr

/-- Result of the semantic (AI) guard. -/
inductive SemanticResult where
  | risk (score : Nat)
  | timeout
  | malformed
  deriving DecidableEq, Repr

/-- The centralized control policy (one catalog snapshot). -/
structure ControlPolicy where
  strictness : Strictness
  allowedModels : List Nat
  allowedTools : List Nat
  irreversibleTools : List Nat
  pinnedArtifacts : List Nat
  signatures : List (List Nat)
  piiRedactAt : Nat
  piiBlockAt : Nat
  semReviewAt : Nat
  semBlockAt : Nat
  maxSteps : Nat
  deriving DecidableEq, Repr

/-- Schema-level validation of a candidate policy. -/
def ControlPolicy.valid (p : ControlPolicy) : Bool :=
  decide (p.piiRedactAt ≤ p.piiBlockAt ∧ p.semReviewAt ≤ p.semBlockAt ∧ 0 < p.maxSteps)

/-- A decision is a set of restrictions; an interaction is dispatched only if it is neither
denied nor waiting for approval. `redact` means the payload is delivered only after
redaction. -/
structure Decision where
  deny : Bool
  ask : Bool
  redact : Bool
  reasons : List Reason
  deriving DecidableEq, Repr

/-- No restriction. -/
def Decision.pass : Decision := ⟨false, false, false, []⟩

/-- A single restriction flag with its reason. -/
def Decision.denyBy (r : Reason) : Decision := ⟨true, false, false, [r]⟩
def Decision.askBy (r : Reason) : Decision := ⟨false, true, false, [r]⟩
def Decision.redactBy (r : Reason) : Decision := ⟨false, false, true, [r]⟩

/-- Union of restrictions. -/
def Decision.combine (a b : Decision) : Decision :=
  ⟨a.deny || b.deny, a.ask || b.ask, a.redact || b.redact, a.reasons ++ b.reasons⟩

/-- Whether the interaction may be dispatched. -/
def Decision.executes (d : Decision) : Bool := !d.deny && !d.ask

/-- `d.AtMost e`: `e` imposes every restriction that `d` imposes. -/
def Decision.AtMost (d e : Decision) : Prop :=
  (d.deny = true → e.deny = true) ∧ (d.ask = true → e.ask = true) ∧
    (d.redact = true → e.redact = true)

/-- Restriction raised when `c` holds. -/
def Decision.when (c : Bool) (d : Decision) : Decision := if c then d else .pass

/-- Does the content contain any feed signature as a contiguous subsequence? -/
def signatureHit (sigs : List (List Nat)) (content : List Nat) : Bool :=
  sigs.any (fun s => decide (s <:+: content))

/-- Checks that depend on the kind of interaction. -/
def kindDecision (p : ControlPolicy) (i : Interaction) : Decision :=
  match i.kind with
  | .prompt => .pass
  | .modelCall m => .when (decide (m ∉ p.allowedModels)) (.denyBy .modelNotAllowed)
  | .toolCall t =>
      (Decision.when (decide (t ∉ p.allowedTools)) (.denyBy .toolNotAllowed)).combine
        (.when (decide (t ∈ p.irreversibleTools) && !i.approved)
          (.askBy .irreversibleNeedsApproval))
  | .artifactLoad h f =>
      (Decision.when (decide (h ∉ p.pinnedArtifacts)) (.denyBy .artifactNotPinned)).combine
        (.when (!f.safe) (.denyBy .unsafeArtifactFormat))

/-- PII / secret thresholds: redact at or above `piiRedactAt`, block at or above
`piiBlockAt`. -/
def piiDecision (p : ControlPolicy) (i : Interaction) : Decision :=
  (Decision.when (decide (p.piiRedactAt ≤ i.piiScore)) (.redactBy .piiRedacted)).combine
    (.when (decide (p.piiBlockAt ≤ i.piiScore)) (.denyBy .piiBlocked))

/-- The deterministic (non-AI) layer. `steps` is the number of interactions already
dispatched in this session. -/
def hardDecision (p : ControlPolicy) (steps : Nat) (i : Interaction) : Decision :=
  (Decision.when (!i.authenticated) (.denyBy .unauthenticated)).combine <|
  (Decision.when (decide (p.maxSteps ≤ steps)) (.denyBy .stepLimit)).combine <|
  (Decision.when (signatureHit p.signatures i.content) (.denyBy .signatureMatch)).combine <|
  (kindDecision p i).combine (piiDecision p i)

/-- Fallback when the semantic guard is unavailable: permissive passes with an alert,
balanced asks for review, strict also denies. -/
def fallbackDecision (s : Strictness) : Decision :=
  ⟨decide (2 ≤ s.rank), decide (1 ≤ s.rank), false, [.semanticUnavailable]⟩

/-- The semantic (AI) layer. -/
def semanticDecision (p : ControlPolicy) : SemanticResult → Decision
  | .risk r =>
      (Decision.when (decide (p.semReviewAt ≤ r)) (.askBy .semanticReview)).combine
        (.when (decide (p.semBlockAt ≤ r)) (.denyBy .semanticBlocked))
  | .timeout => fallbackDecision p.strictness
  | .malformed => fallbackDecision p.strictness

/-- The hybrid gate: deterministic restrictions joined with semantic restrictions. -/
def gate (p : ControlPolicy) (steps : Nat) (i : Interaction) (sem : SemanticResult) :
    Decision :=
  (hardDecision p steps i).combine (semanticDecision p sem)

/-! ## Policy store with last-known-good reload -/

/-- The active policy, if any valid one has been loaded, with an activation epoch and a
counter of rejected reloads (shown as an alarm on the dashboard). -/
structure PolicyStore where
  active : Option ControlPolicy
  epoch : Nat
  rejectedReloads : Nat
  deriving DecidableEq, Repr

/-- Store before any policy is loaded. -/
def PolicyStore.empty : PolicyStore := ⟨none, 0, 0⟩

/-- Live reload: a valid candidate becomes active under a new epoch; an invalid one is
rejected and the last valid policy stays active. -/
def PolicyStore.reload (st : PolicyStore) (cand : ControlPolicy) : PolicyStore :=
  if cand.valid then ⟨some cand, st.epoch + 1, st.rejectedReloads⟩
  else { st with rejectedReloads := st.rejectedReloads + 1 }

/-- Apply a sequence of reload attempts. -/
def PolicyStore.reloadAll (st : PolicyStore) (cands : List ControlPolicy) : PolicyStore :=
  cands.foldl PolicyStore.reload st

/-! ## Session transition and audit log -/

/-- One audit event: the decision and the policy epoch that produced it. -/
structure Event where
  epoch : Nat
  decision : Decision
  deriving DecidableEq, Repr

/-- Per-session state: dispatched-interaction counter and append-only audit log. -/
structure Session where
  steps : Nat
  log : List Event
  deriving DecidableEq, Repr

/-- Fresh session. -/
def Session.empty : Session := ⟨0, []⟩

/-- Decision of the gateway for the current store; fail closed without a valid policy. -/
def storeDecision (st : PolicyStore) (s : Session) (i : Interaction) (sem : SemanticResult) :
    Decision :=
  match st.active with
  | none => .denyBy .noValidPolicy
  | some p => gate p s.steps i sem

/-- Process one interaction: decide, count a dispatch if it executes, log one event. -/
def sessionStep (st : PolicyStore) (s : Session) (i : Interaction) (sem : SemanticResult) :
    Session × Decision :=
  let d := storeDecision st s i sem
  (⟨if d.executes then s.steps + 1 else s.steps, s.log ++ [⟨st.epoch, d⟩]⟩, d)

/-- Run a session over a list of interactions under a fixed store. -/
def sessionRun (st : PolicyStore) (s : Session) (xs : List (Interaction × SemanticResult)) :
    Session :=
  xs.foldl (fun s x => (sessionStep st s x.1 x.2).1) s

/-- Number of denied events in an audit log (dashboard metric). -/
def blockedCount (log : List Event) : Nat :=
  (log.filter (fun e => e.decision.deny)).length

/-- `q` is at least as strict as `p`: smaller allowlists, more irreversible tools and
signatures, lower thresholds and step limit, stricter fallback. -/
def Stricter (q p : ControlPolicy) : Prop :=
  (∀ m ∈ q.allowedModels, m ∈ p.allowedModels) ∧
  (∀ t ∈ q.allowedTools, t ∈ p.allowedTools) ∧
  (∀ t ∈ p.irreversibleTools, t ∈ q.irreversibleTools) ∧
  (∀ h ∈ q.pinnedArtifacts, h ∈ p.pinnedArtifacts) ∧
  (∀ sig ∈ p.signatures, sig ∈ q.signatures) ∧
  q.piiRedactAt ≤ p.piiRedactAt ∧ q.piiBlockAt ≤ p.piiBlockAt ∧
  q.semReviewAt ≤ p.semReviewAt ∧ q.semBlockAt ≤ p.semBlockAt ∧
  q.maxSteps ≤ p.maxSteps ∧ p.strictness.rank ≤ q.strictness.rank

/-! ## Memory isolation -/

/-- An entry of the agent's persistent memory / retrieval index, tagged with its owner. -/
structure MemoryEntry where
  owner : Nat
  content : List Nat
  deriving DecidableEq, Repr

/-- Retrieval through the gateway returns only entries owned by the caller. -/
def recall (mem : List MemoryEntry) (principal : Nat) : List MemoryEntry :=
  mem.filter (fun e => e.owner == principal)

/-! ## Decision algebra -/

@[simp] theorem Decision.combine_deny (a b : Decision) :
    (a.combine b).deny = (a.deny || b.deny) := rfl
@[simp] theorem Decision.combine_ask (a b : Decision) :
    (a.combine b).ask = (a.ask || b.ask) := rfl
@[simp] theorem Decision.combine_redact (a b : Decision) :
    (a.combine b).redact = (a.redact || b.redact) := rfl

theorem Decision.executes_eq_true_iff (d : Decision) :
    d.executes = true ↔ d.deny = false ∧ d.ask = false := by
  simp [Decision.executes]

/-- A combined decision executes iff both parts execute: no stage can relax another. -/
theorem Decision.combine_executes (a b : Decision) :
    (a.combine b).executes = true ↔ a.executes = true ∧ b.executes = true := by
  simp only [executes_eq_true_iff, combine_deny, combine_ask, Bool.or_eq_false_iff]
  tauto

theorem Decision.AtMost.refl (d : Decision) : d.AtMost d := ⟨id, id, id⟩

theorem Decision.AtMost.trans {a b c : Decision} (h₁ : a.AtMost b) (h₂ : b.AtMost c) :
    a.AtMost c :=
  ⟨h₂.1 ∘ h₁.1, h₂.2.1 ∘ h₁.2.1, h₂.2.2 ∘ h₁.2.2⟩

theorem Decision.AtMost.combine {a a' b b' : Decision} (ha : a.AtMost a') (hb : b.AtMost b') :
    (a.combine b).AtMost (a'.combine b') := by
  refine ⟨?_, ?_, ?_⟩ <;> simp only [combine_deny, combine_ask, combine_redact,
    Bool.or_eq_true] <;> rintro (h | h)
  exacts [Or.inl (ha.1 h), Or.inr (hb.1 h), Or.inl (ha.2.1 h), Or.inr (hb.2.1 h),
    Or.inl (ha.2.2 h), Or.inr (hb.2.2 h)]

theorem Decision.AtMost.combine_left (a b : Decision) : a.AtMost (a.combine b) := by
  refine ⟨?_, ?_, ?_⟩ <;> simp +contextual

theorem Decision.AtMost.combine_right (a b : Decision) : b.AtMost (a.combine b) := by
  refine ⟨?_, ?_, ?_⟩ <;> simp +contextual

theorem Decision.AtMost.when {c c' : Bool} {d : Decision} (h : c = true → c' = true) :
    (Decision.when c d).AtMost (Decision.when c' d) := by
  cases c <;> cases c' <;> simp_all [Decision.when, Decision.pass, Decision.AtMost]

/-- More restrictions can only prevent execution. -/
theorem Decision.AtMost.executes {d e : Decision} (h : d.AtMost e) (he : e.executes = true) :
    d.executes = true := by
  rw [executes_eq_true_iff] at he ⊢
  refine ⟨?_, ?_⟩
  · cases hd : d.deny
    · rfl
    · simpa [he.1] using h.1 hd
  · cases hd : d.ask
    · rfl
    · simpa [he.2] using h.2.1 hd

/-! ## Hybrid composition -/

/-- Every deterministic restriction survives into the final decision. -/
theorem hard_atMost_gate (p : ControlPolicy) (n : Nat) (i : Interaction)
    (sem : SemanticResult) : (hardDecision p n i).AtMost (gate p n i sem) :=
  Decision.AtMost.combine_left _ _

/-- Every semantic restriction survives into the final decision. -/
theorem semantic_atMost_gate (p : ControlPolicy) (n : Nat) (i : Interaction)
    (sem : SemanticResult) : (semanticDecision p sem).AtMost (gate p n i sem) :=
  Decision.AtMost.combine_right _ _

/-- A semantic "safe" verdict cannot override a deterministic denial or approval
requirement: whatever executes passed the deterministic layer. -/
theorem gate_executes_imp_hard {p : ControlPolicy} {n : Nat} {i : Interaction}
    {sem : SemanticResult} (h : (gate p n i sem).executes = true) :
    (hardDecision p n i).executes = true :=
  ((Decision.combine_executes _ _).1 h).1

/-- Whatever executes also passed the semantic layer. -/
theorem gate_executes_imp_semantic {p : ControlPolicy} {n : Nat} {i : Interaction}
    {sem : SemanticResult} (h : (gate p n i sem).executes = true) :
    (semanticDecision p sem).executes = true :=
  ((Decision.combine_executes _ _).1 h).2

/-- In strict mode an unavailable semantic guard (timeout) blocks. -/
theorem strict_timeout_denies {p : ControlPolicy} (hp : p.strictness = .strict) (n : Nat)
    (i : Interaction) : (gate p n i .timeout).deny = true := by
  simp [gate, semanticDecision, fallbackDecision, hp, Strictness.rank]

/-- In strict mode malformed semantic output blocks. -/
theorem strict_malformed_denies {p : ControlPolicy} (hp : p.strictness = .strict) (n : Nat)
    (i : Interaction) : (gate p n i .malformed).deny = true := by
  simp [gate, semanticDecision, fallbackDecision, hp, Strictness.rank]

/-- In balanced mode an unavailable semantic guard sends the interaction to review, so it is
not dispatched automatically. -/
theorem balanced_timeout_not_executed {p : ControlPolicy} (hp : p.strictness = .balanced)
    (n : Nat) (i : Interaction) : (gate p n i .timeout).executes = false := by
  simp [gate, semanticDecision, fallbackDecision, hp, Strictness.rank, Decision.executes]

/-- In permissive mode an unavailable semantic guard does not by itself restrict the
interaction, but the event carries the `semanticUnavailable` alert. -/
theorem permissive_timeout_alerts {p : ControlPolicy} (hp : p.strictness = .permissive)
    (n : Nat) (i : Interaction) :
    (gate p n i .timeout) = (hardDecision p n i).combine
      ⟨false, false, false, [.semanticUnavailable]⟩ := by
  simp [gate, semanticDecision, fallbackDecision, hp, Strictness.rank]

/-! ## Deterministic controls -/

theorem hardDecision_deny (p : ControlPolicy) (n : Nat) (i : Interaction) :
    (hardDecision p n i).deny = (!i.authenticated || decide (p.maxSteps ≤ n) ||
      signatureHit p.signatures i.content || (kindDecision p i).deny ||
      (piiDecision p i).deny) := by
  simp only [hardDecision, Decision.combine_deny]
  cases i.authenticated <;> cases decide (p.maxSteps ≤ n) <;>
    cases signatureHit p.signatures i.content <;>
    simp [Decision.when, Decision.denyBy, Decision.pass]

/-- Unauthenticated interactions are denied. -/
theorem unauthenticated_denied (p : ControlPolicy) (n : Nat) {i : Interaction}
    (hi : i.authenticated = false) (sem : SemanticResult) : (gate p n i sem).deny = true := by
  simp [gate, hardDecision_deny, hi]

/-- Content containing any signature from the attack feed is denied, whatever the semantic
guard says. -/
theorem signature_denied {p : ControlPolicy} {sig : List Nat} (hs : sig ∈ p.signatures)
    (n : Nat) {i : Interaction} (hc : sig <:+: i.content) (sem : SemanticResult) :
    (gate p n i sem).deny = true := by
  have : signatureHit p.signatures i.content = true := by
    simp only [signatureHit, List.any_eq_true, decide_eq_true_eq]
    exact ⟨sig, hs, hc⟩
  simp [gate, hardDecision_deny, this]

/-- A call to a model outside the allowlist is denied. -/
theorem model_not_allowed_denied {p : ControlPolicy} {m : Nat} (hm : m ∉ p.allowedModels)
    (n : Nat) {i : Interaction} (hk : i.kind = .modelCall m) (sem : SemanticResult) :
    (gate p n i sem).deny = true := by
  simp [gate, hardDecision_deny, kindDecision, hk, hm, Decision.when, Decision.denyBy]

/-- A call to a tool outside the allowlist is denied. -/
theorem tool_not_allowed_denied {p : ControlPolicy} {t : Nat} (ht : t ∉ p.allowedTools)
    (n : Nat) {i : Interaction} (hk : i.kind = .toolCall t) (sem : SemanticResult) :
    (gate p n i sem).deny = true := by
  simp [gate, hardDecision_deny, kindDecision, hk, ht, Decision.when, Decision.denyBy]

/-- An irreversible tool is never dispatched without a trusted approval record. -/
theorem irreversible_requires_approval {p : ControlPolicy} {t n : Nat} {i : Interaction}
    {sem : SemanticResult} (ht : t ∈ p.irreversibleTools) (hk : i.kind = .toolCall t)
    (hx : (gate p n i sem).executes = true) : i.approved = true := by
  have h := gate_executes_imp_hard hx
  rw [Decision.executes_eq_true_iff] at h
  cases ha : i.approved
  · exfalso
    have : (hardDecision p n i).ask = true := by
      simp [hardDecision, kindDecision, hk, ht, ha, Decision.when, Decision.askBy]
    simp [this] at h
  · rfl

/-- A model artifact is loaded only if its hash is pinned in the catalog and its format
cannot execute code on load. -/
theorem artifact_admitted_pinned_safe {p : ControlPolicy} {n h : Nat} {f : ArtifactFormat}
    {i : Interaction} {sem : SemanticResult} (hk : i.kind = .artifactLoad h f)
    (hx : (gate p n i sem).executes = true) : h ∈ p.pinnedArtifacts ∧ f.safe = true := by
  have h' := (Decision.executes_eq_true_iff _).1 (gate_executes_imp_hard hx)
  have hd := h'.1
  rw [hardDecision_deny] at hd
  simp only [Bool.or_eq_false_iff] at hd
  have hk' := hd.1.2
  simp only [kindDecision, hk, Decision.combine_deny, Bool.or_eq_false_iff] at hk'
  constructor
  · by_contra hn
    simp [Decision.when, hn, Decision.denyBy] at hk'
  · cases hf : f.safe
    · simp [Decision.when, hf, Decision.denyBy] at hk'
    · rfl

/-- Content whose PII score reaches the block threshold is denied. -/
theorem pii_block_denied {p : ControlPolicy} (n : Nat) {i : Interaction}
    (h : p.piiBlockAt ≤ i.piiScore) (sem : SemanticResult) :
    (gate p n i sem).deny = true := by
  simp [gate, hardDecision_deny, piiDecision, h, Decision.when, Decision.denyBy]

/-- Content whose PII score reaches the redaction threshold is delivered only redacted. -/
theorem pii_redact_flagged {p : ControlPolicy} (n : Nat) {i : Interaction}
    (h : p.piiRedactAt ≤ i.piiScore) (sem : SemanticResult) :
    (gate p n i sem).redact = true := by
  simp [gate, hardDecision, piiDecision, h, Decision.when, Decision.redactBy]

/-! ## Monotonicity under policy tightening -/

theorem signatureHit_mono {s s' : List (List Nat)} (h : ∀ x ∈ s, x ∈ s') (c : List Nat) :
    signatureHit s c = true → signatureHit s' c = true := by
  simp only [signatureHit, List.any_eq_true, decide_eq_true_eq]
  rintro ⟨x, hx, hc⟩
  exact ⟨x, h x hx, hc⟩

theorem kindDecision_mono {p q : ControlPolicy} (h : Stricter q p) (i : Interaction) :
    (kindDecision p i).AtMost (kindDecision q i) := by
  obtain ⟨hm, ht, hirr, hpin, -⟩ := h
  rcases i with ⟨_, _, k, _, _, _⟩
  cases k with
  | prompt => exact .refl _
  | modelCall m => exact .when (by simpa using fun h₁ h₂ => h₁ (hm m h₂))
  | toolCall t =>
    refine .combine (.when (by simpa using fun h₁ h₂ => h₁ (ht t h₂))) (.when ?_)
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    exact fun ⟨h₁, h₂⟩ => ⟨hirr t h₁, h₂⟩
  | artifactLoad hh f =>
    exact .combine (.when (by simpa using fun h₁ h₂ => h₁ (hpin hh h₂))) (.refl _)

theorem piiDecision_mono {p q : ControlPolicy} (h : Stricter q p) (i : Interaction) :
    (piiDecision p i).AtMost (piiDecision q i) := by
  obtain ⟨-, -, -, -, -, hr, hb, -⟩ := h
  exact .combine (.when (by simpa using fun h' => le_trans hr h'))
    (.when (by simpa using fun h' => le_trans hb h'))

theorem hardDecision_mono {p q : ControlPolicy} (h : Stricter q p) (n : Nat)
    (i : Interaction) : (hardDecision p n i).AtMost (hardDecision q n i) := by
  have hs := h.2.2.2.2.1
  have hmax := h.2.2.2.2.2.2.2.2.2.1
  exact .combine (.refl _) <| .combine (.when (by simpa using fun h' => le_trans hmax h')) <|
    .combine (.when (signatureHit_mono hs _)) <|
    .combine (kindDecision_mono h i) (piiDecision_mono h i)

theorem fallbackDecision_mono {s s' : Strictness} (h : s.rank ≤ s'.rank) :
    (fallbackDecision s).AtMost (fallbackDecision s') := by
  refine ⟨?_, ?_, ?_⟩ <;> simp [fallbackDecision] <;> omega

theorem semanticDecision_mono {p q : ControlPolicy} (h : Stricter q p) (sem : SemanticResult) :
    (semanticDecision p sem).AtMost (semanticDecision q sem) := by
  obtain ⟨-, -, -, -, -, -, -, hr, hb, -, hst⟩ := h
  cases sem with
  | risk r =>
      exact .combine (.when (by simpa using fun h' => le_trans hr h'))
        (.when (by simpa using fun h' => le_trans hb h'))
  | timeout => exact fallbackDecision_mono hst
  | malformed => exact fallbackDecision_mono hst

/-- Tightening the policy (as judges do when editing it live) can only add restrictions:
every deny, approval requirement and redaction under the looser policy remains. -/
theorem gate_mono {p q : ControlPolicy} (h : Stricter q p) (n : Nat) (i : Interaction)
    (sem : SemanticResult) : (gate p n i sem).AtMost (gate q n i sem) :=
  .combine (hardDecision_mono h n i) (semanticDecision_mono h sem)

/-- Anything dispatched under a stricter policy is also dispatched under the looser one. -/
theorem gate_mono_executes {p q : ControlPolicy} (h : Stricter q p) {n : Nat}
    {i : Interaction} {sem : SemanticResult} (hx : (gate q n i sem).executes = true) :
    (gate p n i sem).executes = true :=
  (gate_mono h n i sem).executes hx

/-! ## Policy store -/

/-- An invalid reload leaves the active policy and epoch unchanged. -/
theorem reload_invalid_keeps {st : PolicyStore} {c : ControlPolicy} (hc : c.valid = false) :
    (st.reload c).active = st.active ∧ (st.reload c).epoch = st.epoch := by
  simp [PolicyStore.reload, hc]

/-- A valid reload becomes active under a strictly larger epoch. -/
theorem reload_valid_activates {st : PolicyStore} {c : ControlPolicy} (hc : c.valid = true) :
    (st.reload c).active = some c ∧ (st.reload c).epoch = st.epoch + 1 := by
  simp [PolicyStore.reload, hc]

/-- The policy epoch never decreases. -/
theorem reload_epoch_mono (st : PolicyStore) (c : ControlPolicy) :
    st.epoch ≤ (st.reload c).epoch := by
  unfold PolicyStore.reload; split <;> simp

/-- Reloads preserve the invariant "the active policy, if any, is valid". -/
theorem reloadAll_preserves_valid (cs : List ControlPolicy) (st : PolicyStore)
    (hst : ∀ p, st.active = some p → p.valid = true) :
    ∀ p, (st.reloadAll cs).active = some p → p.valid = true := by
  induction cs generalizing st with
  | nil => exact hst
  | cons c cs ih =>
      refine ih (st.reload c) fun p hp => ?_
      unfold PolicyStore.reload at hp
      split at hp
      · rename_i hc; simp only [Option.some.injEq] at hp; exact hp ▸ hc
      · exact hst p hp

/-- Starting from the empty store, the active policy (if any) is always valid, whatever
sequence of candidate files is submitted. -/
theorem reloadAll_active_valid (cs : List ControlPolicy) {p : ControlPolicy}
    (h : (PolicyStore.empty.reloadAll cs).active = some p) : p.valid = true :=
  reloadAll_preserves_valid cs _ (by simp [PolicyStore.empty]) p h

/-- Without a valid policy every interaction is denied, nothing is dispatched, and the denial
is still logged. -/
theorem no_policy_fail_closed {st : PolicyStore} (hst : st.active = none) (s : Session)
    (i : Interaction) (sem : SemanticResult) :
    (sessionStep st s i sem).2.deny = true ∧ (sessionStep st s i sem).1.steps = s.steps ∧
      (sessionStep st s i sem).1.log = s.log ++ [⟨st.epoch, .denyBy .noValidPolicy⟩] := by
  simp [sessionStep, storeDecision, hst, Decision.denyBy, Decision.executes]

/-! ## Step limit, audit log, memory isolation -/

theorem sessionStep_steps_le {st : PolicyStore} {p : ControlPolicy} (hst : st.active = some p)
    {s : Session} (hs : s.steps ≤ p.maxSteps) (i : Interaction) (sem : SemanticResult) :
    (sessionStep st s i sem).1.steps ≤ p.maxSteps := by
  simp only [sessionStep, storeDecision, hst]
  split
  · rename_i hx
    have h := (Decision.executes_eq_true_iff _).1 (gate_executes_imp_hard hx)
    have hd := h.1
    rw [hardDecision_deny] at hd
    simp only [Bool.or_eq_false_iff, decide_eq_false_iff_not, not_le] at hd
    omega
  · exact hs

/-- Runaway loops are cut off: in any session run under an active policy, the number of
dispatched interactions never exceeds `maxSteps`. -/
theorem sessionRun_steps_le {st : PolicyStore} {p : ControlPolicy} (hst : st.active = some p)
    (xs : List (Interaction × SemanticResult)) {s : Session} (hs : s.steps ≤ p.maxSteps) :
    (sessionRun st s xs).steps ≤ p.maxSteps := by
  induction xs generalizing s with
  | nil => exact hs
  | cons x xs ih => exact ih (sessionStep_steps_le hst hs x.1 x.2)

/-- Every processed interaction appends exactly one event, at the end, to an append-only log. -/
theorem sessionStep_log (st : PolicyStore) (s : Session) (i : Interaction)
    (sem : SemanticResult) :
    (sessionStep st s i sem).1.log = s.log ++ [⟨st.epoch, (sessionStep st s i sem).2⟩] := rfl

/-- The audit log is complete: one event per interaction, earlier events preserved. -/
theorem sessionRun_log (st : PolicyStore) (s : Session)
    (xs : List (Interaction × SemanticResult)) :
    s.log <+: (sessionRun st s xs).log ∧
      (sessionRun st s xs).log.length = s.log.length + xs.length := by
  induction xs generalizing s with
  | nil => simp [sessionRun]
  | cons x xs ih =>
      obtain ⟨h₁, h₂⟩ := ih (sessionStep st s x.1 x.2).1
      refine ⟨List.IsPrefix.trans (by simp [sessionStep_log]) h₁, ?_⟩
      rw [List.length_cons]
      have : sessionRun st s (x :: xs) = sessionRun st (sessionStep st s x.1 x.2).1 xs := rfl
      rw [this, h₂, sessionStep_log]
      simp; omega

/-- The dashboard's blocked counter increases by one exactly on denied interactions. -/
theorem blockedCount_step (st : PolicyStore) (s : Session) (i : Interaction)
    (sem : SemanticResult) :
    blockedCount (sessionStep st s i sem).1.log =
      blockedCount s.log + if (sessionStep st s i sem).2.deny then 1 else 0 := by
  rw [sessionStep_log]
  simp only [blockedCount, List.filter_append, List.length_append]
  split <;> simp_all

/-- Memory retrieval never returns another principal's entries. -/
theorem recall_owned {mem : List MemoryEntry} {principal : Nat} {e : MemoryEntry}
    (h : e ∈ recall mem principal) : e.owner = principal := by
  simpa [recall] using (List.mem_filter.1 h).2

/-! ## Concrete fixtures (checked by `decide`) -/

/-- Demo catalog: model 1 allowed; tools 10 (read) and 11 (transfer, irreversible) allowed;
artifact hash 4242 pinned; one feed signature `[66, 67]`; balanced fallback. -/
def demoControlPolicy : ControlPolicy :=
  { strictness := .balanced, allowedModels := [1], allowedTools := [10, 11],
    irreversibleTools := [11], pinnedArtifacts := [4242], signatures := [[66, 67]],
    piiRedactAt := 50, piiBlockAt := 90, semReviewAt := 60, semBlockAt := 85,
    maxSteps := 3 }

/-- A benign authenticated prompt. -/
def demoPrompt : Interaction :=
  { principal := 1, authenticated := true, kind := .prompt, content := [1, 2, 3],
    piiScore := 0, approved := false }

theorem demo_control_policy_valid : demoControlPolicy.valid = true := by decide

theorem demo_benign_prompt_executes :
    (gate demoControlPolicy 0 demoPrompt (.risk 10)).executes = true := by decide

theorem demo_feed_signature_blocks :
    (gate demoControlPolicy 0 { demoPrompt with content := [5, 66, 67, 8] } (.risk 0)).deny =
      true := by decide

theorem demo_pii_redacted_not_blocked :
    (gate demoControlPolicy 0 { demoPrompt with piiScore := 70 } (.risk 0)) =
      ⟨false, false, true, [.piiRedacted]⟩ := by decide

theorem demo_pickle_artifact_blocked :
    (gate demoControlPolicy 0 { demoPrompt with kind := .artifactLoad 4242 .pickle }
      (.risk 0)).executes = false := by decide

theorem demo_transfer_waits_for_approval :
    (gate demoControlPolicy 0 { demoPrompt with kind := .toolCall 11 } (.risk 0)).executes =
      false := by decide

theorem demo_invalid_reload_keeps_last_good :
    ((PolicyStore.empty.reload demoControlPolicy).reload
      { demoControlPolicy with piiRedactAt := 95 }).active = some demoControlPolicy := by
  decide

end Mathguard.Control

end
