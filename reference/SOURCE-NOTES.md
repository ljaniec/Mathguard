# Source audit — 3 October 2026

The author reviewed the following PDFs from the uploaded archive `HackYeah 2026 - Rules for Participants-20261003T090052Z-1-001.zip`:

- `Partner Task [Goldman Sachs] - AI Control Layer/CRIETRIA AI Control Layer.pdf`
- `Partner Task [Goldman Sachs] - AI Control Layer/RULES AI Control Layer.pdf`

The repository contains our derived requirements and source notes, not a redistributed copy of the task archive. Full local text extractions were read during authoring.

## Material findings

The detailed brief requires a functional lightweight control layer mediating AI-system interactions, a centralized catalog, deterministic and semantic controls, external/local resource governance, consideration of historical exploits/externally supplied signatures, reporting, and an executable suite containing allowed and blocked/redacted examples. Judges can run the suite, use unprepared prompts, and change configuration/feeds. Architecture and performance telemetry are part of evaluation. Teams choose their own stack and resources; pre-existing agents and applications may be used.

The detailed criteria give 30/20/20/15/15 percent to robustness, architecture, security reporting, self-testing, and implementability/scalability respectively. The rules give 30/20/20/20/10. No mentor resolution of that discrepancy is recorded in this pack.

The rules state a 3 October 2026 23:00 start and 4 October 2026 23:00 submission deadline, one to six team members, and a maximum ten-slide PDF. The supplied text does not state the timezone beside those times. Confirm the operational schedule in HackTribe with the organizers. Prize pool: 15000 PLN, split 6000/5000/4000. Copyright of awarded solutions is not transferred to the sponsor under the supplied rules.

## External primary references

- https://hackyeah.pl/tasks-prizes
- https://lean-lang.org/doc/reference/latest/ValidatingProofs/
- https://lean-lang.org/doc/reference/latest/releases/v4.34.1/
- https://genai.owasp.org/llmrisk/llm01-prompt-injection/
- https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices

The Lean validation guidance distinguishes checking a proof term from reviewing its meaning, and describes additional trust introduced by native evaluation. The MCP guidance informs per-request authentication, scoped authority, private tool credentials, and separation of sessions from authentication. No broad compliance or certification claim follows from citing these sources.
