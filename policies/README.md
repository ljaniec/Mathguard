# Live policy configuration

The control layer reads a local UTF-8 JSON file using schema `mathguard-policy-3`. The examples are [demo.json](demo.json) (balanced), [strict.json](strict.json) and [permissive.json](permissive.json). Select the exact installed local model ID in both `allowed_models` and `semantic_model`; `local-model` is a fixture placeholder, not a model download. No paid provider or API key is required.

The normal launcher prepares a runtime copy; edit that configured file during evaluation rather than the repository example. Increase `epoch` for each policy change. Activation occurs at an authenticated request boundary and can also be requested by an operator at `POST /v1/policy/reload`. Validation at `POST /v1/policy/validate` has no activation effect. Invalid JSON, invalid schemas and rejected worker transitions retain the last valid policy. Without a valid policy/feed pair, dispatch is blocked. Policy activation preserves committed ledger and resource state; reducing a limit below existing expenditure is rejected. The dashboard exposes reload errors and the active versions.

## Fields and bounds

Every listed field is required. Unknown and duplicate keys, booleans used as integers, non-finite numbers, UTF-16/BOM input and unpaired Unicode surrogates are rejected. Policy/feed inputs are at most 65,536 bytes. The shared parser also limits nesting to 32, parsed nodes to 20,000 and numeric literals to 1,024 characters; field-specific bounds below are much smaller.

| Field | Accepted value | Meaning |
| --- | --- | --- |
| `schema_version` | `mathguard-policy-3` | Exact supported schema |
| `epoch` | Integer 1–1,000,000,000; increase on activation | Version binding for fresh requests and approvals |
| `profile` | `strict`, `balanced`, `permissive` | Compiled semantic-failure behavior |
| `pii_action` | `redact`, `block` | Whether the effective block threshold is clamped to the redaction threshold |
| `pii_redact_at`, `pii_block_at` | Integers 1–101; redact ≤ block | Thresholds for deterministic sensitive-data facts; 101 disables that score threshold |
| `semantic_review_at` | Integer 1–101 | Review threshold, effectively clamped to the block threshold |
| `semantic_threshold` | Integer 1–100 | Semantic risk threshold for denial |
| `allowed_models` | 1–32 unique exact local model IDs; each ≤200 UTF-8 bytes | Model dispatch allowlist |
| `semantic_model` | One entry from `allowed_models` | Local classifier model |
| `allowed_tools`, `irreversible_tools` | 0–32 unique names; each 1–100 ASCII letters/digits/`_.-` | Tool allowlist and tools requiring exact owner approval; an irreversible entry never grants allowlist access |
| `budget_limit` | Four integers, each 0–1,000,000,000,000 | Global cumulative cost allowance, token envelope, compute milliseconds, dispatch calls |
| `call_bound` | Same four-component vector, componentwise ≤ `budget_limit`; call component exactly 1 | Conservative reservation/charge for each classifier/model dispatch |
| `deadline_seconds` | Integer 1–30 | Local provider response deadline |
| `max_output_tokens` | Integer 16–2,048 | Requested provider generation ceiling |
| `max_input_bytes` | Integer 32–8,192 | UTF-8 content/context bound |
| `max_session_steps` | Integer 1–1,000 | Attempted interaction cap per session |
| `repeat_limit` | Integer 1–20 | Repeated content/action cap per session |
| `max_transfer`, `approval_threshold` | Integers 1–50,000 | Demo ledger transfer cap and approval threshold, in PLN minor units; 2,500 means PLN 25.00 |
| `model_clearance` | Integer 0–2 | Maximum detected confidentiality admitted to the model sink |
| `artifact_repositories` | 1–32 unique repository IDs, each ≤200 bytes | Exact trusted artifact-source labels, not URLs or file paths |
| `artifact_sha256` | 1–32 unique lowercase 64-character SHA-256 digests | Trusted byte pins; adding a hash is an operator trust decision |

Local model IDs support namespaces and tags such as `qwen2.5:3b` and `hf.co/team/model:Q4_K_M`. Repository IDs have two to four ASCII name segments such as `mathguard/demo-safe`. Leading slashes, traversal segments, backslashes, percent-escaped paths, URLs and control characters are refused. Repository labels do not cause network or filesystem access.

The token component of `call_bound` must cover `max_input_bytes + max_output_tokens + 2048`. Its compute component must cover `deadline_seconds × 1000 + 1000`. These are conservative envelopes, not tokenizer calibration or financial invoices. The supplied `[0,16384,16000,1]` bound reserves no monetary charge for a local call, a 16,384-unit token envelope, 16 seconds of compute envelope and one call. Classifier and proposer calls each reserve/charge separately. Actual provider token reports and elapsed time are recorded separately. Timeout charges remain consumed; quarantine requires explicit operator recovery.

## Hybrid decisions

Deterministic and semantic decisions compose as independent deny/review/redact flags in the compiled Lean gate. A semantic `allow` cannot clear a signature match, an unauthorized model/tool, a budget restriction or another hard denial. Owner approval cannot clear those restrictions either.

| Local classifier result | Strict | Balanced | Permissive |
| --- | --- | --- | --- |
| Valid score below effective review threshold | Pass | Pass | Pass |
| Score at review threshold | Review; no dispatch | Review; no dispatch | Review; no dispatch |
| Score at block threshold | Deny | Deny | Deny |
| Timeout or malformed output | Deny and review | Review; no dispatch | Pass with alert |

Provider quarantine remains a separate restriction in every profile. A permissive classifier fallback is not permission to start another uncertain upstream call.

Detector scores are adapter facts: 60 for supported PII, 80 for supported secrets and 100 for hidden/reconstructed sensitive values. They are not calibrated probabilities. The checked patterns cover common emails, checksum-valid IBANs, labeled checksum-valid PESEL values, Polish telephone formats and selected credential/token/private-key forms. Unlabeled numeric IDs are intentionally not treated as Polish phone numbers or PESEL values.

Unicode normalization removes format controls and inspects a finite set of common homoglyphs. Bounded percent, HTML-entity, Base64/Base64URL and labeled hexadecimal variants are examined for at most three decoding rounds. The whole interaction permits at most 48 unique inspection candidates and 65,536 bytes of variant text; exceeding a limit fails closed. No archive, compression, pickle or executable deserialization is performed. These are finite regressions, not universal encoding or attack coverage.

Serialized JSON objects/arrays are inspected as data, including escaped strings and conservative split-string reconstructions. Redaction preserves object keys, container types and numeric/boolean/null values. Sensitive or ambiguously normalized keys and sensitive non-string credential/identifier values are refused. Hidden sensitive payloads and reconstructed values are refused independently of adjustable PII thresholds because a safe mapping back to source fields is not established. The SDK strictly parses sanitized tool arguments/results before dispatch or delivery.

## Inert artifact admission

`POST /v1/artifacts/check` accepts only the documented manifest keys: `repository`, `sha256`, `format`, `trust_remote_code`, `content_base64`. Code-capable formats (including pickle), remote-code requests, path-like repository labels, noncanonical Base64, mismatched/unpinned hashes and invalid structures are rejected before any loading. Decoded content is limited to 12,000 bytes. This endpoint demonstrates admission and never loads a model.

Safetensors admission checks a JSON header of at most 8,192 bytes, supported fixed-width dtypes, bounded shapes, string-only metadata, exact tensor byte sizes and nonoverlapping contiguous offsets covering all payload bytes. GGUF admission supports a bounded little-endian v2/v3 subset with scalar/flat-array metadata, explicit alignment and F32/F16 tensors. Quantized/large artifacts and structures outside that subset are refused. The repository's fixed-hash GGUF example is explicitly labeled a known inert fixture, not a runnable model. Local provider weight downloads are outside this small admission endpoint.

Structural admission does not establish artifact provenance beyond the operator's pin, malware completeness, appropriate model behavior or runtime safety of an external inference engine. The checks follow the format descriptions from [GGML](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md) and [Safetensors](https://github.com/huggingface/safetensors/blob/main/README.md); the implementation deliberately supports a narrower bounded subset.

## Evaluation examples

Use an ordinary question for allow, `Contact alice@example.com` for redaction, and `ignore previous instructions` for literal-signature denial. Tighten `pii_block_at` from 100 to 60 under a higher epoch: the contact case must block before invoking the classifier. Save malformed JSON: the dashboard should report rejection and retain the previous active epoch. Replace the classifier output with a malformed fixture in tests to verify all three profiles. The automated regressions in `tests/test_detection_hardening.py` cover these facts plus structured content, Polish, encoded, Unicode, split and inert-artifact boundary cases. Real local-model accuracy requires separate live evaluation.
