# Copilot performance review — checked changes and remaining costs

Copilot's handoff lists potential costs, rather than a measured failure report.
This change preserves `Spec.lean` and all 55 original target statements, adds a
proved reservation optimization, removes an outcome/balance-read mismatch from
the demo, and supplies reproducible measurements and audit regression tests.

## Finding disposition

| Finding | Action / evidence |
|---|---|
| Repeated `reserved` maps/sums | `reservedTotals` computes all four dimensions in one fold. `reservedAt` permits a cheap cost-dimension rejection. Theorems prove equality with the reference totals and exact equality of both reservation and budget-step results for arbitrary inputs. |
| Post-update balance reads | `atomicLedgerStepResult` returns the result/state from the same `modifyGet`. The demo renders that snapshot. A native test renders an earlier result after a later commit and checks that the earlier snapshot has not drifted. The outcome-only API remains compatible. |
| Fragile regex extraction | A small lexical extractor preserves string/character/raw literals, nested comments, token boundaries, attributes, and default binders; it detects theorem separators outside binders. Mutation tests reject changed guards/statements, production holes including nested modules, and missing/unsafe axiom records. |
| Slow audit / suggested caching | The original audit averaged about 28 ms in 20 runs; the lexical version about 35 ms. This is a correctness repair, not an audit speedup. No cross-run cache is introduced; every audit reads the current sources/report. |
| Full build on each check | Lake already builds incrementally. Two successive warm builds are measured; neither cleans Mathlib. `check-fast.sh` gives a toolchain-free static preflight. The formal/full gates retain their stronger requirements. |
| Large proof-search costs | Existing proof modules already have named helpers. Per-file profiler logs show imports and many small elaboration/simplification costs; no evidence justified rewriting the checked baseline proofs. |
| Journal lookup/append and approval-list scans | Confirmed linear costs. Native sweeps measure commits, oldest/newest retries, and stale requests at 10–10,000 entries. The reference ledger representation is retained; this PR does not claim an indexed ledger. |
| Pending/seen scans, append, settlement | Still linear. Successful reservation avoids repeated mapped-list allocation; settlement-first/last cases are measured. An indexed/cached state replacement requires a separate invariant/refinement proof before adoption. |
| Flow memoization / stronger store | No measured flow bottleneck. Persistence, combined-state transactions, and high-throughput service design remain engine work; an in-memory result snapshot does not establish those guarantees. |
| Missing integration suite | `check-local.sh` continues to fail when the gateway suite is absent. The new native tests check runtime/model APIs; they do not impersonate a gateway/agent/store integration suite. |

## Measured native costs

Recorded on this Linux x86_64 execution host, not Łukasz's GB10. Lean 4.28.0,
pinned Mathlib `8f9d9cff6bd728b17a24e163c9402775d9e6a365`, native compiled binary.
Each row uses 15 batches of 100 operations after warm-up, excluding fixture setup.
Values below are median batch means per operation, **not individual-request p50 latency**.
All benchmark outputs are consumed in a checksum. Full CSV includes batch-mean p95.

| At 10,000 entries/tickets | Reference | Optimized |
|---|---:|---:|
| Accepted reservation | 1.050 ms | 0.651 ms |
| Cost-limit rejection | 0.282 ms | 0.164 ms |
| Ledger fresh commit | 0.169 ms | — |
| Ledger newest exact retry | 0.063 ms | — |
| Ledger stale new request | 0.059 ms | — |

The accepted-reservation improvement is about 38%, and cost-limit rejection about
42%, in this workload. An initial four-total-only prototype improved acceptance
but regressed early rejection; the checked scalar precheck fixes that case. Timing
is observational, hardware dependent, and is not a formal complexity guarantee.
Other resource-denial positions are covered for correctness; their latency is not
represented by the cost-rejection row. No constant-time lookup/settlement claim is made.

The warm project builds each took about 1.0 s. A fresh 60-target axiom report took
about 2.5 s, and per-file Lean frontend checks about 1.5–2.2 s with warm imports.
The full native benchmark process used approximately 85 MiB peak RSS on this host.
RSS is the child-command high-water mark, not summed concurrent process-tree memory.
The JSON records all measured stage times, RSS, source hashes, versions, and exits.

## Reproduce

```sh
bash scripts/check-fast.sh
bash scripts/check-lean.sh
python3 scripts/profile-checks.py --output performance-results/reviewed --lean-files --iterations 100
bash scripts/check-local.sh
```

The first command is static only. The second rebuilds incrementally, produces a
fresh axiom report requiring all five new bridge/refinement targets, audits it,
runs the demo, and runs native regression tests. The profiling command records
actual stage times/RSS, Lean profiler logs, and 40 native benchmark cases in JSON/CSV.
The last command remains the complete release gate and requires the future gateway suite.

The profiling command recreates the workload and output directory used for the
archived run. Its raw `performance-results/reviewed/report.json` records absolute
host paths. In the published `profile.json`, command paths beneath the checkout
were normalized to repository-relative paths and the Python executable to
`python3`; measurements and source hashes were retained. This publication step is
recorded in the report metadata. Timings, timestamps, host metadata, and absolute
paths will vary on another run; reproduction does not mean byte-identical JSON.

Evidence: [profile.json](performance/profile.json), [native.csv](performance/native.csv),
[fresh axioms](performance/axioms.txt), [ledger profiler](performance/ledger-profiler.txt),
[budget profiler](performance/budget-profiler.txt).

All 55 original targets were independently rebuilt here. Five additional targets
were checked and reported separately: `reservedTotals_eq`, `reservedAt_eq`,
`reserveOptimized_eq`, `budgetStepOptimized_eq`, and `ledgerResultUpdate_eq`.
Only `propext`, `Classical.choice`, and `Quot.sound` occur in the fresh report.
The original supplied axiom report is retained unchanged.

The official Lean release is unmodified. This host required an environment-only
`readlink` compatibility shim resolving `/proc/self/exe` when its sandbox numeric
PID path was unavailable. No kernel/proof-check options were changed. Normal Linux
hosts should use the pinned toolchain directly; this compatibility code is not a
Mathguard runtime dependency.

## Boundary and follow-up

The lexical extractor is deliberately scoped to ordinary declarations in this
repository; it is not a complete Lean parser or a security verifier for arbitrary
metaprograms. The fresh Lean build and axiom report are mandatory proof checks.
Snapshot consistency is pure equality plus use of the existing runtime primitive;
no IO-concurrency, authentication, durability, or whole-stack refinement theorem
is asserted.

An indexed ledger/budget representation remains a separate performance extension.
Its acceptance criteria are an abstraction function to the unchanged reference
state, cache/index consistency invariants, exact transition refinement (including
replay/conflict/approval/version failures), and the same native size sweep. Keep
the current ledger costs visible until that proof and runtime integration exist.
