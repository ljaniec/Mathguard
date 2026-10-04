# Release hardening (outside the production build)

* `RuntimeSpec.lean` — the unchanged definition-only handoff model.
* `ReleaseH1.lean` — H1: exact financial worker transition, proved against `Worker.dispatch`.
* `ReleaseDispatch.lean` — every accepted worker command, invariants, monotonicity, and
  exact-response replay (grounded parts of H2).
* `ReleaseReload.lean` — worker-level `configure` / `control_configure` facts (part of H5).
* `ReleaseApproval.lean` — generic approval binding, admission model, nonce freshness (H3).

Build with `lake build MathguardRelease` (library `MathguardRelease`, not a default target).
Results, assumptions and fingerprints: `docs/verification/RELEASE-HARDENING-RESULTS.md`.
Axiom report: `lake env lean scripts/release/ReleaseAxioms.lean`.
Native H1 cases: `python3 scripts/release_h1_native.py`.
