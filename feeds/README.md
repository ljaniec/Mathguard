# Data-only signature feed

[demo-signatures.json](demo-signatures.json) is a **synthetic defensive fixture set**. It is not a subscribed threat-intelligence service, a historical exploit corpus or proof of comprehensive prompt-injection detection. Its entries demonstrate English/Polish instruction overrides, unsafe deserialization, remote model code and a shell-pipe pattern. All interactions use the same compiled literal-signature restriction; a local semantic `allow` cannot override a match.

The feed is a configured local UTF-8 JSON file. Operators edit it and increase `version`; an authenticated request or explicit operator reload validates the candidate and activates it atomically with the effective controls. A stale or invalid candidate retains the last valid version. If there is no valid policy/feed pair, execution is blocked. The dashboard and audit metadata show the active version and reload failures. File access is local; `source` records provenance and never triggers fetching or code execution.

```json
{
  "schema_version": "mathguard-signatures-1",
  "version": 2,
  "source": "Operator-reviewed synthetic regression examples",
  "signatures": [
    {"id": "OVERRIDE_EN", "contains": "ignore previous instructions", "reason": "PROMPT_INJECTION"}
  ]
}
```

Exactly `schema_version`, `version`, `source` and `signatures` are required. Unknown/duplicate fields and wrong types are rejected. The file is at most 65,536 bytes. `version` is an integer 1–1,000,000,000. `source` must be a nonblank string of at most 300 UTF-8 bytes without control characters. There are at most 100 signatures. Each entry has exactly `id`, `contains` and `reason`; ID/reason are 1–64 uppercase ASCII letters/digits/underscores, IDs are unique, and `contains` is nonblank literal text of at most 200 UTF-8 bytes without control/format characters.

Matching normalizes Unicode and whitespace and uses case-folded literal UTF-8 bytes. Inspection includes the bounded decoded/Unicode variants documented in [the policy guide](../policies/README.md), session history, indirect tool/agent content and conservative structured-string reconstruction. An entry such as `(a+)+$` remains literal punctuation: it is never evaluated as a regular expression. There is no decompression, deserialization, command invocation or arbitrary code in feed processing.

A literal feed may block a legitimate discussion that quotes a known attack. That is an explicit conservative policy tradeoff: test both the intended deny cases and nearby benign content when adding entries. Record an actual primary advisory/incident source in your review evidence before describing an entry as historical coverage. Do not turn synthetic examples into claims about unseen model accuracy. The semantic layer and allowlists remain necessary because no finite substring list can recognize every attack.
