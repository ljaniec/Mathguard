# Dependency and model inventory

The runnable gateway/dashboard uses Python's standard library and browser APIs; no third-party Python/JavaScript runtime package or external UI CDN is required. The repository uses its pinned Lean/Mathlib project.

| Component | Version/source | License evidence / status |
|---|---|---|
| Lean | 4.28.0, `lean-toolchain` | Apache-2.0, checked official release `LICENSE`; preserve its third-party notices when distributing binaries |
| Mathlib | `8f9d9cff6bd728b17a24e163c9402775d9e6a365` | Apache-2.0, checked dependency `LICENSE` |
| Lake packages | Exact revisions in `lake-manifest.json` | Retain the packages' license files; Qq/aesop/proofwidgets/importGraph/LeanSearchClient/plausible Apache-2.0, Cli MIT, as inspected locally |
| Python | System Python 3.10+; development host 3.12.14 | Python distribution license/notices; see https://docs.python.org/3/license.html |
| Dashboard | Repository HTML/CSS/JS, system fonts | Original project code; no external theme/assets bundled |
| Local serving engine | Tested Ollama 0.35.1; operator-installed, not bundled | MIT, checked [official tagged LICENSE](https://github.com/ollama/ollama/blob/v0.35.1/LICENSE); retain its bundled third-party notices when redistributing the engine |
| Local semantic/proposer model | Tested `qwen2.5:1.5b-instruct`, Q4_K_M, digest `65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b`; no weights bundled | Apache-2.0, verified from the actual installed model; source, weight/license hashes, engine identity and finite results in [submission/model-record.json](submission/model-record.json) |
| Development assistance | Codex/ChatGPT for implementation/docs/visual refinement; Aristotle for Lean proof development | Development-only disclosure; no paid inference API is required by the runnable gateway. Accepted proof artifacts are independently rebuilt/audited. |
| Test prompts / attack feed | Repository-authored inert synthetic fixtures | Development examples, not an external benchmark or claimed unseen corpus |
| OWASP | Primary guidance linked in threat review | Referenced guidance only; no endorsement/certification claim or full documents redistributed |

The project's own distribution license must be chosen by its owner; this notice does not assign one. A model's availability through a local server does not establish its redistribution rights. The recorded model/license covers the exact tested weights, not every model an operator might substitute. Include actual tools/models and AI assistance used in the final submission's resource list. The challenge sources require checking open-source licensing; they do not supply a particular model license.

## Tools used to build, check and present Mathguard

This inventory records the tools used in the project work, including AI assistance and artifact production. The runnable control layer uses local inference. Cloud development services are disclosed separately from the software the judges need to install. Versions are given where the project records them; an unrecorded service/model version is not inferred.

| Tool or resource | Role in this project | Where it is used / evidence |
| --- | --- | --- |
| OpenAI Codex / ChatGPT, including collaborating coding agents | Implementation, security review, documentation, presentation refinement and release coordination | Development assistance; [plan progress](docs/verification/PLAN-PROGRESS.md), repository code and PR history |
| Aristotle | Assisted Lean proof development and requirements adaptation; returned artifacts were rebuilt and audited | Development assistance; [import audit](docs/verification/IMPORT-AUDIT.md), [integration audit](docs/verification/GENERAL-CONTROL-INTEGRATION.md), [remaining formalization handoff](aristotle/FINAL-HARDENING-HANDOFF.md) |
| Prelint | Automated PR review; feedback informed demo improvements and additional regression cases | Review service; [review and response](docs/verification/PRELINT-FOLLOWUP.md) |
| Fable compendium, supplied by the user | Requirements research input, attributed to Fable by the user; consulted through the supplied PDF and Aristotle adaptation | Input document rather than an installed runtime tool; [requirements recovery](docs/10-REQUIREMENTS-RECOVERY.md), [preserved adaptation](docs/12-ARISTOTLE-REQUIREMENTS-ADAPTATION.md) |
| OpenAI image generation in ChatGPT | Generated/refined identity artwork and the restrained presentation background | Design assistance; [current shield refinement prompt](submission/brand/CLASSIC-IDENTITY.md), [archived mark and background prompts](submission/brand/LOGO-PROMPT.md) |
| Git and GitHub, including the GitHub connector | Version control, source inspection, branches, PR publication and review | Development infrastructure; repository commit and PR history |
| Web search and Cloud Browser automation | Checked source documents and attempted browser-based dashboard acceptance | Research/review tools; [source notes](reference/SOURCE-NOTES.md), [capture provenance](evidence/dashboard-capture.json). Local dashboard navigation was blocked, so browser acceptance remains open. |
| Lean 4.28.0 | Checks formal definitions/proofs and compiles the worker that makes live gate decisions | Build tool and compiled runtime; [toolchain pin](lean-toolchain), [formal model](docs/05-FORMAL-MODEL.md), [worker](Mathguard/Worker.lean) |
| elan and Lake | Lean toolchain management, pinned dependency resolution and native builds | Build tooling; [build configuration](lakefile.toml), [release commands](scripts/check-lean.sh) |
| Mathlib and its Lake dependencies: Batteries, Qq, Aesop, ProofWidgets, importGraph, LeanSearchClient, Plausible and Cli | Formal-development dependency set; exact revisions are recorded, rather than treated as separately operated services | Build dependencies; [complete pinned manifest](lake-manifest.json), license inventory above |
| Python 3, its standard library and `unittest` | Gateway/SDK, policy parsing, detectors, provider adapters, auditing, setup and automated tests | Runtime and test tooling; [gateway](gateway/), [tests](tests/), [test receipt](evidence/integration.json). No third-party Python gateway package is required. |
| SQLite through Python `sqlite3` | Durable single-node command journal, state and sanitized audit records | Runtime storage; [state implementation](gateway/state.py), [release assurance](docs/verification/RELEASE-ASSURANCE.md) |
| GNU Make and Bash | Simple judge setup/run/test commands and repeatable release checks | Operator/build tooling; [Makefile](Makefile), [scripts](scripts/) |
| ripgrep (`rg`) and standard command-line utilities | Source search, diffs, file inspection and development checks | Development utilities; not extra gateway services |
| HTML, CSS, JavaScript and browser APIs | Interactive dashboard, controls, metrics and exports | Runtime UI; [dashboard source](dashboard/), [dashboard guide](docs/16-DASHBOARD-GUIDE.md) |
| Node.js, including built-in `vm` and `assert` | Dashboard DOM/security tests and presentation automation | Test/build tooling; [dashboard tests](tests/test_dashboard.py). Node.js is needed for the complete test suite, not for serving the dashboard. |
| Ollama 0.35.1 | Local inference server for semantic inspection and proposal generation; tested with cloud features disabled | Runtime service; [engine/model record](submission/model-record.json), [live rehearsal](evidence/live-local-rehearsal.json) |
| Qwen2.5 1.5B Instruct, Q4_K_M; earlier Qwen2.5 0.5B trial | The 1.5B weights are the selected local classifier/proposer model. The 0.5B trial was rejected after benign-case failures. | Runtime model / development trial; [selected model record](submission/model-record.json), [failed baseline](evidence/live-development-evaluation-05-baseline.json) |
| OpenAI `@oai/artifact-tool` and presentation validation helpers | Created/edited PPTX slides, native tables, notes and previews; checked package integrity, layout and re-import | Artifact production; [editable deck](submission/Mathguard-HackYeah-2026.pptx), [design review](submission/brand/DESIGN-REVIEW.md) |
| LibreOffice Impress | Converted the presentation to PDF | Artifact production; the [presentation PDF](submission/Mathguard-HackYeah-2026.pdf) records Impress and LibreOfficeDev in its creator/producer metadata |
| Nimbus Sans, Nimbus Roman and Nimbus Mono PS | Presentation typography | Design assets; [font and visual review](submission/brand/DESIGN-REVIEW.md) |
| jsdom 30.1.1 | Ran the existing dashboard reporting JavaScript in a non-networked DOM using actual gateway responses | Capture-only dependency; [capture provenance](evidence/dashboard-capture.json) |
| WeasyPrint 70.0 | Laid out the frozen dashboard HTML as an offline document | Capture-only dependency; [capture provenance](evidence/dashboard-capture.json) |
| PyMuPDF 1.26.6 | PDF inspection and rasterization of dashboard evidence views | Artifact inspection/capture tooling; [capture provenance](evidence/dashboard-capture.json), [overview](submission/reporting/dashboard-overview.png), [audit view](submission/reporting/dashboard-audit.png) |

The dashboard evidence images are offline renders of real gateway responses, not live browser screenshots. The slide/capture tooling is not a requirement for running the submitted component. AI-generated code and proof suggestions are checked by the project's build, audit and finite test procedures; using an assistance tool does not extend the stated security guarantees. [Release assurance](docs/verification/RELEASE-ASSURANCE.md) gives those boundaries.
