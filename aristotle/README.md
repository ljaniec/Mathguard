# Aristotle handoff — Mathguard model-v1

## What to send

Send `Spec.lean` plus **one** request file per run, together with the instructions below. The three runs share reviewed definitions but have independent proof targets. Start with `LedgerRequest.lean`, then `BudgetRequest.lean`, then `FlowRequest.lean`. If the service accepts one file only, use the standalone files generated in the deliverable bundle: they inline `Spec.lean` and remove the local `import Spec` line.

This pack does not assert the service's current upload limits or toolchain. Record the actual toolchain/Mathlib commit from its environment. The attached definitions are uncompiled authoring drafts; first perform a definition-only typecheck in that pinned workspace. Arithmetic, list/finite-sum APIs, and imports may require elaboration repairs. Repairs must preserve the specified functions and propositions. No proof has been completed in this pack.

## Common instructions to paste

You are proving a small executable supervisory-control kernel for **Mathguard**, an AI-agent gateway demonstrated on a simulated personal-account ledger. The agent/LLM is untrusted and may propose arbitrary requests. The formal objective is exact operational safety, not classifier accuracy, blockchain consensus, or a whole-bank theorem.

Read `Spec.lean` and the chosen request file. The request theorem holes are intentional. Replace all target holes with kernel-checkable proofs. Do not change definitions, weaken theorem statements, add invariant hypotheses that assume the desired conclusion, make all actions reject, or add arbitrary axioms. If a target is false or a definition needs a semantic correction, stop that target and provide the smallest counterexample and precise proposed change. Continue independent valid targets.

Elaboration-only repairs (imports, an equivalent decidability instance, local lemma names) are allowed if behavior and proposition meaning are unchanged. Identify each repair in the result summary. Avoid broad Mathlib builds: use a matching cache and targeted imports/builds. Do not rely on native execution for proofs: no `native_decide`, `decide +native`, arbitrary `axiom`, `sorry`, `admit`, unsafe declaration tricks, or kernel-skip settings. Use ordinary proof terms/tactics, `simp`, `omega`, finite-sum and list-fold lemmas.

Produce:

1. Definition-only typecheck result and exact toolchain/import commit.
2. Completed source with unchanged model-v1 semantics.
3. Every requested theorem, helper lemmas as needed, and positive witnesses.
4. `#print axioms` output for every exported target, with explicit disclosure of standard logical axioms and absence of `sorryAx`/compiler-trust shortcuts.
5. Build commands/result and any unresolved goals, clearly separated from checked theorems.
6. A concise explanation of the proof's assumptions and limits.

Do not report a partially admitted file as a fully verified kernel. No runtime service, database, parser, authentication, approval-signature, pricing, or classifier-accuracy theorem follows automatically from this request.

## Ledger-specific instructions

The ledger is closed, finite-account, one-currency, non-overdraft. Money is `Nat` minor units. Distinct endpoints and sufficient funds must be used to prove nontrivial conservation despite truncated subtraction. Fresh commits check owner/capability/beneficiary, policy epoch, state revision, caps, and exact high-value approval. Committed IDs are at most once. Exact retries return the old state and receipt; conflicts block. Journal and approval consumption update atomically in the model.

Proof order: frame/exactness/conservation; initial invariant; commit-precondition extraction; authorization/version/cap/approval lemmas; no-mutation/replay; full invariant preservation; trace induction; stale/reused/race corollaries; witnesses. Helper lookup and fold/append lemmas are expected.

`LedgerInvariant` is not an admission guard. Do not strengthen admission to “next state satisfies the invariant.” All theorems quantify over arbitrary account count. Keep accepted `n=3` examples. The trace function in this request uses fixed policy; one-step accounting preservation itself is policy-parametric. The serial same-revision result assumes sequential atomic transitions, not a formal real database proof.

The current overspend witness violates more than one guard; retain it, and add an isolated insufficient-funds witness if useful (larger policy cap, amount within cap and threshold/valid approval, source balance below amount). Add a legitimate high-value transfer with a bound approval and an exact boundary-expiry witness if the run has capacity; do not displace universal proofs to generate only concrete examples.

## Budget-specific instructions

Usage is a four-dimensional natural-number vector. Admission reserves before calls. Invariant is spent plus sum of pending bounds below limits, unique IDs, and pending IDs recorded in `seen`. Settlement removes a unique ticket and adds actual usage only when actual is at most the bound. Unknown/cancelled consumption charges full bound. Completed IDs cannot be reused. Reload can only lower limits to values still above spent plus reserved.

Use pending-ID uniqueness in the exact settlement theorem: filtering by ID removes exactly one ticket. Do not permit a duplicate ticket or erase `seen` to simplify proofs. The budget theorem guarantees accounted usage; actual provider behavior and bound computation remain assumptions. Show accepted reservation and denial of two six-unit requests against ten-unit limits.

## Flow-specific instructions

Labels have separate confidentiality and provenance axes. Join is componentwise maximum. Prove upper-bound/least-upper-bound/associativity and whole-context label monotonicity. Prove output gate enforces clearance and untrusted-data acceptance. Prove semantic conjunction/intersection can only restrict hard-permitted effects. Show both denied sensitive export and accepted internal/public exports.

Do not invent a total severity ordering between approval and redaction. Do not claim noninterference or perfect injection detection from these targets. Confidentiality/provenance labels are trusted model inputs. There is no declassification function in model-v1.

## Acceptance on return

The Codex implementation agent must independently rerun the pinned definition/proof checks, inspect theorem meanings against `docs/05-FORMAL-MODEL.md`, inspect axiom dependencies, and build the runtime from the reviewed definition hash. Aristotle success is not automatic permission to modify the production policy or skip integration tests.

If only some kernels finish, the dashboard must list exactly which targets are checked and which are pending. Keep the gateway fail closed and retain ordinary tests. A pending proof does not justify a fabricated verified badge.
