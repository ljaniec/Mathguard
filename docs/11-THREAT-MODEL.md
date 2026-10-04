# Threat analysis and coverage limits

This is our mapping from primary OWASP guidance to the implemented control layer, not a certification claim. The official challenge asks teams to consider broader ecosystem threats (brief p2). Review sources: [OWASP LLM/GenAI 2025](https://genai.owasp.org/llm-top-10/) and the [OWASP Agentic Applications 2026 document](https://genai.owasp.org/download/52117/?tmstv=1765059207), particularly its contents and at-a-glance taxonomy. Names below identify source categories; the implementation choices and limitations are our analysis.

| Agentic category | Current control / evidence | Remaining risk |
|---|---|---|
| ASI01 Goal hijack | Real-model classifier adapter, signatures, immutable hard gates; indirect-content test | Classifier accuracy and unseen attacks require live evaluation |
| ASI02 Tool misuse | Configurable tool allowlist, exact irreversible approvals, SDK call/result gates; dedicated typed ledger protocol | Tool-specific schema validation belongs to the integration; no MCP transport/OAuth server |
| ASI03 Identity/privilege abuse | Separate roles, principal-bound sessions, exact owner approval | Demo tokens/host isolation are deployment assumptions |
| ASI04 Supply chain | Allowlisted repository/digest, actual bounded byte hash, safe header checks, remote code denied | Configured provider weights/serving stack still need their own provenance check |
| ASI05 Unexpected code execution | No deserialization/execution of supplied artifacts; unsafe loader patterns blocked | No general sandbox or malware detector is claimed |
| ASI06 Memory/context poisoning | Bounded per-principal session history; separate confidentiality/trust; same input controls for documents/tools | No persistent/shared retrieval system is implemented |
| ASI07 Inter-agent communication | Explicit agent-message route and SDK; principal-bound session; identity never comes from generated arguments | No signed federation or generic multi-agent protocol claim |
| ASI08 Cascading failures | Conservative reservations, timeout quarantine, fail-closed worker, bounded ingress | No distributed recovery or upstream cancellation proof |
| ASI09 Human-agent trust exploitation | Explicit canonical approval card, separate human token, inert rendering | Social engineering remains possible; live operator rehearsal required |
| ASI10 Rogue agents | Hard action constraints, global resource cap, session step/repeat limits | No assurance that arbitrary agents lack independent host/network capabilities |

LLM-specific sensitive-data disclosure is addressed by finite input/output patterns and detected-label flow checks; arbitrary secrets can be missed. Output is rendered as inert text. The worker proves properties of typed operations, not the truthfulness of generated text. Misinformation/factual correctness is outside the current security claim. No shared vector database or training pipeline is present, so poisoning/embedding risks are constrained by omission rather than declared solved.

Historical-pattern fixtures cover instruction override, unsafe deserialization, remote model code and shell-pipe execution. Their source currently identifies them as synthetic defensive examples. Add primary advisories/incident references before calling them a maintained historical-exploit feed. Matching a string in a fixture is not proof that all variants of an exploit family are prevented.

Adversary: controls prompts, documents/tool text, generated output, JSON proposal fields, retry ordering and malicious timing. Trusted deployment base: gateway/worker binaries, the OS and private process boundary, configured credentials/policy authority, host clock, provider bounds, and actual model/weight provenance. Do not give a reference agent independent downstream credentials and then claim complete mediation based only on this gateway.

Primary infrastructure guidance also grounds the defensive examples: [Hugging Face's pickle security documentation](https://huggingface.co/docs/hub/security-pickle) explains execution risk during loading and limitations of scanning. Our implementation avoids deserialization entirely and verifies inert fixture bytes against a trusted digest. This is narrower than detecting every malicious model artifact. [Ollama's compatibility documentation](https://docs.ollama.com/api/openai-compatibility) is the integration reference for the local chat endpoint; installed server/model behavior still needs a live smoke test.
