# Operator rehearsal and submission evidence

This checkpoint follows the P0 order in document10: executable evaluation, public-route demo, then submission PDF. Persistent storage remains P2. The compiled Lean modules and worker executable are unchanged from the fresh proof checkpoint.

## Repeatable offline workflow

```sh
make test
python3 scripts/rehearse-demo.py --output evidence/rehearsal.json
```

The second command starts an isolated loopback HTTP server, uses temporary policy/feed files and random role credentials, and closes all processes afterwards. It uses the actual Lean worker and an explicitly labeled **fixture** provider. It leaves the example policy/feed untouched. Its16 assertions cover normal allowance, PII redaction, indirect signature blocking, financial commit, approval issuance/commit, two exact retries, valid/invalid policy edits, signature addition/removal, exhausted budget and sanitized management/audit export. Policy and feed activation preserve financial state and prior charges. Source/worker hashes are included in the JSON report.

This is a reproducible HTTP workflow rehearsal. Browser rendering, human operation and live model behavior remain separate acceptance steps.

## Live local-model setup

Install/start the team's chosen local OpenAI-compatible serving engine and model. Record the exact serving-engine version, model ID, weight revision/digest, model-card/license URL and license in `submission/model-record.json`. Its pending fields must be completed by the operator; no model is inferred or bundled here.

Create a local policy copy with the installed ID in both model fields:

```sh
export MATHGUARD_MODEL_URL='http://127.0.0.1:11434/v1'
export MATHGUARD_MODEL_ID='<exact installed model ID>'
python3 - <<'PY'
import json, os
from pathlib import Path
p=json.loads(Path('policies/demo.json').read_text())
p['allowed_models']=[os.environ['MATHGUARD_MODEL_ID']]
p['semantic_model']=os.environ['MATHGUARD_MODEL_ID']
Path('/tmp/mathguard-live-policy.json').write_text(json.dumps(p,indent=2)+'\n')
PY
bash scripts/demo.sh --policy /tmp/mathguard-live-policy.json
```

Ollama's usual loopback example is shown; verify the installed service and supported JSON-response option. A `local-model` alias is not evidence of the actual installed model. The gateway runs with separate agent/owner/operator tokens printed only in its local console. Enter those in their corresponding dashboard fields, or export agent/operator tokens privately in a second terminal. Keep tokens out of the repository, recordings and screenshots.

## Live evaluator

Use an otherwise idle gateway instance. Instance-wide counters cannot attribute concurrent clients. The evaluator now requires **both** `MATHGUARD_AGENT_TOKEN` and `MATHGUARD_OPERATOR_TOKEN`; the operator token reads sanitized trace metadata, and is never given to the reference agent or model.

```sh
python3 scripts/evaluate-live.py --model "$MATHGUARD_MODEL_ID" \
  --corpus tests/development-prompts.jsonl --label development \
  --output evidence/live-development.json
python3 agent/run.py --model "$MATHGUARD_MODEL_ID" 'Pay Bob 25 PLN for lunch'
```

Use a fresh isolated instance if resource capacity is insufficient. Fifty cases is a parser bound, not a guarantee that the demo budget covers fifty two-call chats. Preserve policy/budget values in each evaluation report; do not silently reset state or increase limits during a run.

Reports include last-good policy/feed hashes, epoch/version, worker digest, instance ID, guard model ID, per-case trace-correlated provider stages, and deltas of successfully schema-validated semantic verdicts. Proposer/transport completion alone does not establish a valid guard verdict. The evaluation refuses fixture mode and a run without any validated live semantic call. Edits/restarts invalidate the run. Control errors make `valid_run` false; partial transport/schema failures retain sanitized evidence and return nonzero status.

| Disposition | Meaning |
|---|---|
| `allowed` | Input/output unchanged and released |
| `redacted` | Content released with input or output redaction |
| `detected_block` | Explicit signature, semantic denial or sensitive-data detector denial |
| `semantic_review` | Valid semantic review withheld content; reported separately |
| `control_error` | Outage, malformed verdict, quarantine, exhausted resource, schema or other control failure |

Expected `allow` requires unchanged dispositions. Expected `block` requires detector denial; a review is a separate conservative intervention. Benign denial/review/redaction are counted separately. Evaluable attack/benign denominators exclude control errors, which are always reported. The script provides raw sample counts, not a universal safety or accuracy percentage.

The checked-in corpus remains development data. A team member who did not tune the classifier must author a disjoint corpus for `--label independent-unseen`. That flag records a declaration, not proof of independence. Preserve its provenance/digest and do not retune on its outcomes while reporting it as unseen.

## Human demo acceptance

Open the dashboard on desktop and mobile. Rehearse prompt allowance, indirect attack, PII redaction, exact financial proposal/owner approval/retry, policy and feed edits, budget stop, and export. Verify inert rendering using HTML-looking input, no console errors, visible provider mode/quarantine/reload errors and usable controls. Capture screenshots with credentials removed. Do not record an unobserved model behavior or present fixture trials as live.

The ten-slide PDF and editable PPTX are under `submission/`. They describe current implementation/evidence and mark remaining live/browser/registration work. Confirm registered team/member details, installed model/license record and current judge-accessible links before uploading the PDF to HackTribe. No upload, final registration, organizer deadline confirmation or PR merge was performed by this checkpoint.
