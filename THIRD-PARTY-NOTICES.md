# Dependency and model inventory

The runnable gateway/dashboard uses Python's standard library and browser APIs; no third-party Python/JavaScript runtime package or external UI CDN is required. The repository uses its pinned Lean/Mathlib project.

| Component | Version/source | License evidence / status |
|---|---|---|
| Lean | 4.28.0, `lean-toolchain` | Apache-2.0, checked official release `LICENSE`; preserve its third-party notices when distributing binaries |
| Mathlib | `8f9d9cff6bd728b17a24e163c9402775d9e6a365` | Apache-2.0, checked dependency `LICENSE` |
| Lake packages | Exact revisions in `lake-manifest.json` | Retain the packages' license files; Qq/aesop/proofwidgets/importGraph/LeanSearchClient/plausible Apache-2.0, Cli MIT, as inspected locally |
| Python | System Python 3.10+; development host 3.12.14 | Python distribution license/notices; see https://docs.python.org/3/license.html |
| Dashboard | Repository HTML/CSS/JS, system fonts | Original project code; no external theme/assets bundled |
| Local semantic/proposer model | Operator-selected; no weights bundled | **OPEN:** record exact model/weights revision, model-card URL, license and serving engine before submission |
| Test prompts / attack feed | Repository-authored inert synthetic fixtures | Development examples, not an external benchmark or claimed unseen corpus |
| OWASP | Primary guidance linked in threat review | Referenced guidance only; no endorsement/certification claim or full documents redistributed |

The project's own distribution license must be chosen by its owner; this notice does not assign one. A model's availability through a local server does not establish its redistribution rights. Include actual tools/models and AI assistance used in the final submission's resource list. The challenge sources require checking open-source licensing; they do not supply a particular model license.
