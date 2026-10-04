# Prelint follow-up for PR #6

Review: [Prelint, 4 October 2026](https://github.com/ljaniec/Mathguard/pull/6#issuecomment-5975758229). The review approved the architecture with changes requested for demo clarity. It raised product concerns rather than inline code defects.

| Raised concern | Change or checked behavior | Status |
| --- | --- | --- |
| Shared 128-token cap can make explanatory answers look broken | README, judge quickstart, presenter tutorial and dashboard explain that replies may end at the cap. The active cap is displayed. The tested shared cap remains unchanged. | Guidance and UI fixed; separate stage caps deferred |
| Three-stage latency and resource overhead are unclear | State one measured benign CPU result: about 4.26 seconds across provider stages. Document three separately charged calls, their full bound and all component limits. The fresh sample compute budget permits 12 complete chats before other usage; 200 call slots alone is misleading. | Fixed |
| What happens to the known indirect public-paste prompt live? | Actual local Ollama/Qwen gateway follow-up: input still `risk=0`; proposer refused; output gate allowed that refusal. A separately constructed harmful output was semantically blocked. Evidence retains both responses/stages. No tool or data transfer occurred. | Investigated; input detection miss remains |
| Restart loses live sessions and approvals | On a successful status refresh, a changed instance invalidates stale UI session/approval/retry state, stops polling and asks for explicit reconnect. Credentials stay in tab memory. Same-directory `make run` restores journaled state without setup. No automatic action retry. | Fixed and regression tested |
| SDK allegedly collapses policy denials into callback failures | Policy admission already occurs outside callback exception handling. A regression checks `TOOL_NOT_ALLOWED` before any callback and `TRUSTED_CALLBACK_FAILURE` after an admitted callback raises. Document that callback effects can be uncertain and cannot be retried safely without tool-specific idempotency/status checks. | Existing distinction verified and documented |

The live result is in [prelint-indirect-live.json](../../evidence/prelint-indirect-live.json). Reproduce with `python3 scripts/probe-indirect-local.py` and already installed local weights. The script starts isolated loopback services with cloud disabled, performs real setup, uses the compiled Lean worker, downloads nothing, and exports no role credentials. Its `completed` field means both probes returned operationally valid decisions, not that both attacks were detected. This is known development evidence, not an unseen benchmark.

Focused regressions cover instance-change detection, unchanged-instance preservation, explicit reconnect, stale approval/retry clearing without network retry, and the SDK distinction before/after callback dispatch. The current [integration receipt](../../evidence/integration.json) records exact source and worker fingerprints. Browser visual/download QA and independent unseen detection evaluation remain open.

No classifier threshold, prompt, local-only restriction or deterministic denial was weakened. No new Lean theorem is claimed by this follow-up. The shared classifier/proposer cap remains a deliberate compatibility/performance tradeoff; splitting it needs a versioned schema and fresh CPU evaluation.
