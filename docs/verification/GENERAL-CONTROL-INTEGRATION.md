# General-control integration verification

Verified on 2026-10-03T23:30:13.141526+00:00. Base: `09837a94ce1ecc237b58c22aead96adb6fb018df` (PR #4 already merged).
Source archive SHA-256: `95931aa331398833e0ded50da3dc1645ce0d4d86a8fcf3a08d251e6a839c3591`.
Aristotle requirements run: `ee5d328d-e8bc-4314-adc1-393b7ff9b6b7`; preceding Next run:
`6fe765d1-f56d-479f-abec-8894a2f99a0f`.

## Imported source provenance

The four production modules are byte-for-byte identical to the archive. Existing baseline
`Spec`/`Ledger`/`Budget`/`Flow` and performance-refinement definitions were preserved.

| Imported module | SHA-256 |
|---|---|
| `Mathguard/Control.lean` | `ebe09b1525b4d50ca4889acd0f756db5100a189552d2506940d2e649a96c3b65` |
| `Mathguard/Composite.lean` | `00dfcd6f3997592b2489e0b754720df6ce52d7ac36efc49d3cbe6dddf9635192` |
| `Mathguard/PolicyHistory.lean` | `761550f229de3e13c638272038b006670762677ef96b1114e0ff2285d55c968a` |
| `Mathguard/Wire.lean` | `421aa3e1452d42a7f6ce8130cd5fa43c9f8763726962b20ea3ee3b7918493252` |

Original C1/P1/W1 requests remain outside the production build in `aristotle/next/`.
The static comparison passed all 35 target statements and definitions, without weakening.
The original baseline supplied report is retained as `model-v1-supplied-axioms.txt`;
`axioms.txt` now contains the freshly generated full catalog.

## Checks performed

| Check | Result |
|---|---|
| Pinned Lean | 4.28.0, commit `7e01a1bf5c70fc6167d49c345d3bf80596e9a79b` |
| Pinned Mathlib | `8f9d9cff6bd728b17a24e163c9402775d9e6a365` |
| `lake build` | PASS; no warnings; imported modules and executables build |
| Fresh `lake env lean scripts/Axioms.lean` | PASS; 156 records: 55 baseline + 5 refinements + 43 Next + 53 Control |
| Static provenance / production-hole scan | PASS; unchanged baseline; no `sorry`, `admit`, arbitrary axioms or native-proof shortcuts |
| Axiom audit with `--require-extra --require-control` | PASS; allowed standard dependencies only; Control uses at most `propext`, `Quot.sound` |
| `lake exe mathguard` | PASS; ledger, budget, flow and G1 examples; 5 interactions with maxSteps 3 -> 3 dispatched, 5 logged, 2 blocked |
| `lake exe mathguard-tests` | PASS; snapshot and optimized-budget regressions preserved |
| Static-audit/parser regressions | PASS; 14 cases |
| Actual-worker gateway/provider/SDK regressions | PASS; 70 cases, zero failures/errors/skips |
| Dashboard JavaScript syntax + HTTP serving | PASS |
| `git diff --check` | PASS |

The canonical complete command is `make test` / `bash scripts/check-local.sh`.
Exact case results, source fingerprints, environment and worker SHA-256 are in
[`evidence/integration.json`](../../evidence/integration.json).
The worker binary for this run is `13368e2720221f70dfb714a77c0405b94a0fd1706e088f40237e098030b7bf32`.

The execution container needed an environment-only compatibility shim mapping the current
process's `/proc/<pid>/exe` lookup to `/proc/self/exe`, plus tar's `--no-same-owner` option.
Neither changes Lean proof checking or repository code. Normal installations use the documented
commands without these container workarounds. Downloaded dependencies remain outside git.

## Runtime assurance

`Mathguard.Control.hardDecision`/`storeDecision` decide the gateway's live controls; W1
`fromWire` decodes typed ledger requests. The 70-case suite tests actual compiled code with
clearly labeled classifier fixtures and a local provider-protocol HTTP fixture. It includes
hard-deny versus safe verdict, risk-review flags, all malformed profiles, timeout quarantine,
PII threshold tightening, split/encoded/Polish/indirect signatures, feed/tool edits, exact
single-use approvals, stale approval rejection, HTTP SDK callback/output filtering, resource
races and ledger replay. These are enforcement regressions, not measured detector accuracy.

C1/P1 composite/history and G1 step/log/recall theorems remain model evidence. The runtime
counts attempted requests conservatively and stores a bounded 2000-event metadata window;
it does not claim a durable append-only implementation or persistent retrieval model.

## Evidence still absent

No real local LLM inference, independent unseen detection score or final submission PDF was
produced by this run. A browser download returned truncated/non-ZIP archives, so browser
visual/operator QA is not claimed. Existing static HTTP/JS checks passed. The SDK is an
interception wrapper, not a complete MCP transport/OAuth server; arbitrary external effects,
crashes, distributed quota ownership and model-loader safety are outside the proofs.
