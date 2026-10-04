import ReleaseH1
/-! Emits the exact `executeJson`/`previewJson` command lines used by
`scripts/release_h1_native.py`. Run: `lake env lean scripts/release/H1Commands.lean`. -/
open Lean Mathguard Mathguard.Release

#eval IO.println s!"PREVIEW {(previewJson demoContext demoRequest).compress}"
#eval IO.println s!"EXECUTE {(executeJson demoContext demoRequest).compress}"
#eval IO.println s!"REPLAY {(executeJson { demoContext with now := 1000000, approval := some h1ExpiredApproval } demoRequest).compress}"
#eval IO.println s!"CONFLICT {(executeJson demoContext { demoRequest with amount := 2600, expectedRevision := 1 }).compress}"
