# Complete Optional Module: Incoming Email Classification, Knowledge-Grounded Draft Responses, and Foundry BART

**Example shared mailbox:** `service@instruo365.de`  
**Authentication:** application or workload identity  
**Safety default:** create drafts only, never automatically send  
**Applies to:** Copilot Studio standard harness and GitHub Copilot harness

---

# 1. Purpose

This optional module extends the shared-mailbox draft solution. The module detects or fetches received messages, classifies them using a governed table, optionally retrieves content from approved knowledge sources, generates a proposed answer, and places the answer as a draft reply in the configured shared mailbox.

Every generated draft contains a clearly removable internal routing block. The block lists all plausible classifications, target departments, and department email addresses. The existing prepare-send and human approval process remains mandatory.

The module supports three classification providers:

1. Deterministic example-phrase baseline.
2. A pretrained or fine-tuned BART-family classifier hosted on Microsoft Foundry managed compute or an Azure Machine Learning managed online endpoint.
3. An approved structured-output language model as an optional alternative.

Microsoft documents that Hugging Face models can be deployed from the Foundry catalog to managed compute and invoked through a secure REST endpoint. Microsoft also states that these models are third-party products and require license, security, legal, and model-risk review. citeturn11search142turn11search144 Azure Machine Learning managed online endpoints provide managed serving, scaling, security, monitoring, traffic splitting, and traffic mirroring for real-time inference. citeturn11search143turn11search145

---

# 2. End-to-end architecture

```mermaid
flowchart LR
    IN[Received email] --> TRIGGER[Webhook, delta job,<br/>event trigger, or supervised command]
    TRIGGER --> FETCH[Fetch complete email from Graph]
    FETCH --> CLASS[Classification provider]
    TABLE[Classification table] --> CLASS
    CLASS --> MULTI[All plausible classifications]
    MULTI --> KNOW{Knowledge enabled?}
    KNOW -->|Yes| RETRIEVE[Retrieve approved passages]
    KNOW -->|No| COMPOSE[Compose review draft]
    RETRIEVE --> COMPOSE
    COMPOSE --> BLOCK[Prepend removable routing block]
    BLOCK --> DRAFT[Create reply draft]
    DRAFT --> REVIEW[Human review]
    REVIEW --> PREPARE[Prepare-send]
    PREPARE --> APPROVE{Approve exact version?}
    APPROVE -->|Yes| SEND[Send existing draft]
    APPROVE -->|No| EDIT[Edit draft]
```

---

# 3. Classification table

Use this logical schema:

| Field | Type | Required | Purpose |
|---|---|---:|---|
| `uuid` | UUID/GUID | Yes | Stable classification identifier |
| `className` | string | Yes | Human-readable classification name |
| `classExamples` | multiline text or string array | Yes | Example phrases representing the class |
| `classTarget` | string | Yes | Responsible department |
| `classTargetEmail` | email | Yes | Department email address |
| `isActive` | boolean | Recommended | Enables or disables the record |
| `priority` | integer | Recommended | Deterministic tie-breaker |
| `updatedAt` | date/time | Recommended | Audit and cache invalidation |
| `modelLabel` | string | Recommended for BART | Stable machine label independent of display name |

Example:

```json
[
  {
    "uuid": "0d64c3fd-9060-4f08-a906-68a7311cbef8",
    "className": "Invoice question",
    "classExamples": [
      "I have a question about invoice 4711",
      "The amount on the invoice is incorrect",
      "Please send a copy of the invoice"
    ],
    "classTarget": "Finance",
    "classTargetEmail": "finance@instruo365.de",
    "isActive": true,
    "priority": 100,
    "modelLabel": "invoice_question"
  }
]
```

Rules:

- The classifier may only return rows present in this table.
- `classTargetEmail` must pass an explicit target-address allow-list.
- Display names may change, but `uuid` and `modelLabel` should remain stable.
- A BART model label maps back to exactly one active table row.
- When several classes are plausible, return every plausible match.
- When none is plausible, return an empty list and require human routing.

---

# 4. Required classification output

```json
{
  "messageId": "opaque-graph-message-id",
  "classifications": [
    {
      "className": "Invoice question",
      "classTarget": "Finance",
      "classTargetEmail": "finance@instruo365.de",
      "score": 0.87,
      "reason": "The message asks about an incorrect invoice amount."
    },
    {
      "className": "Contract question",
      "classTarget": "Legal Operations",
      "classTargetEmail": "legalops@instruo365.de",
      "score": 0.81,
      "reason": "The message also disputes a contract-related charge."
    }
  ],
  "needsHumanRoutingDecision": true,
  "unclassified": false,
  "provider": "foundry-bart",
  "modelVersion": "email-bart-3"
}
```

---

# 5. Mandatory removable routing block

Every automatically created response draft must contain this block at the top of the message body:

```text
--- please remove ---
classification: className(1), className(2), className(n)
department: classTarget(1), classTarget(2), classTarget(n)
email: classTargetEmail(1), classTargetEmail(2), classTargetEmail(n)
--- please remove ---

```

For an actual multi-class result:

```text
--- please remove ---
classification: Invoice question, Contract question
department: Finance, Legal Operations
email: finance@instruo365.de, legalops@instruo365.de
--- please remove ---

```

## 5.1 HTML representation

Use an identifiable HTML wrapper so a reviewer or cleanup function can remove it reliably:

```html
<div data-internal-routing-block="true"
     style="border:2px solid #d13438;background:#fff4f4;padding:12px;font-family:Segoe UI,Arial,sans-serif;font-size:12px;color:#111;">
  <strong>--- please remove ---</strong><br>
  <strong>classification:</strong> Invoice question, Contract question<br>
  <strong>department:</strong> Finance, Legal Operations<br>
  <strong>email:</strong> finance@instruo365.de, legalops@instruo365.de<br>
  <strong>--- please remove ---</strong>
</div>
<br>
```

Do not put the block in the subject. Do not place it after the customer-facing answer, where it is easier to overlook.

## 5.2 Configuration

```dotenv
INCLUDE_ROUTING_BLOCK=true
ROUTING_BLOCK_POSITION=TOP
REQUIRE_ROUTING_BLOCK_REMOVAL_BEFORE_SEND=true
```

## 5.3 Routing block generator

```python
from html import escape


def join_values(values: list[str]) -> str:
    return ", ".join(value.strip() for value in values if value.strip())


def build_routing_block(classifications: list[dict]) -> str:
    names = join_values([item["className"] for item in classifications])
    targets = join_values([item["classTarget"] for item in classifications])
    emails = join_values([item["classTargetEmail"] for item in classifications])

    if not classifications:
        names = "Unclassified"
        targets = "Manual review"
        emails = ""

    return f"""
<div data-internal-routing-block="true"
     style="border:2px solid #d13438;background:#fff4f4;padding:12px;font-family:Segoe UI,Arial,sans-serif;font-size:12px;color:#111;">
  <strong>--- please remove ---</strong><br>
  <strong>classification:</strong> {escape(names)}<br>
  <strong>department:</strong> {escape(targets)}<br>
  <strong>email:</strong> {escape(emails)}<br>
  <strong>--- please remove ---</strong>
</div>
<br>
""".strip()
```

## 5.4 Detect and remove the block

```python
from bs4 import BeautifulSoup


def routing_block_present(html: str) -> bool:
    soup = BeautifulSoup(html, "html.parser")
    return soup.find(attrs={"data-internal-routing-block": "true"}) is not None


def remove_routing_block(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    block = soup.find(attrs={"data-internal-routing-block": "true"})
    if block:
        next_node = block.find_next_sibling("br")
        block.decompose()
        if next_node:
            next_node.decompose()
    return str(soup)
```

Add `beautifulsoup4>=4.12,<5` to the Python dependencies.

## 5.5 Send guard

The prepare-send operation must reject a draft while the block remains if `REQUIRE_ROUTING_BLOCK_REMOVAL_BEFORE_SEND=true`:

```python
async def prepare_send(self, message_id: str) -> dict:
    draft = await self.graph.get_draft(message_id)
    body_html = draft.get("body", {}).get("content", "")
    if (
        self.settings.require_routing_block_removal_before_send
        and routing_block_present(body_html)
    ):
        raise ValueError(
            "ROUTING_BLOCK_PRESENT: remove the internal routing block before approval"
        )
    return await self.approvals.prepare(draft)
```

Optionally expose a separate reviewed cleanup operation:

```text
remove_internal_routing_block
```

That operation must remove only the wrapper carrying `data-internal-routing-block="true"`, re-read the draft afterward, and require a new prepare-send approval.

---

# 6. Harness mapping: tool versus skill

```mermaid
flowchart TD
    H{Harness} -->|Copilot Studio standard harness| CS{Integration path}
    H -->|GitHub Copilot harness| GH{Integration path}
    CS -->|MCP server| CSMCP[Classification, knowledge, draft, and cleanup are MCP tools.<br/>Agent instructions define sequence.]
    CS -->|Custom connector| CSCC[Capabilities are connector operations/tools.<br/>Event trigger or agent flow starts workflow.]
    GH -->|Executable in skill| GHEX[Capabilities are executable commands.<br/>SKILL.md governs selection and safety.]
    GH -->|MCP server| GHMCP[Capabilities are MCP tools.<br/>SKILL.md governs sequence and review.]
```

### Copilot Studio standard harness plus MCP

Implement as MCP tools:

```text
classify_incoming_email
retrieve_answer_knowledge
create_grounded_response_draft
remove_internal_routing_block
```

### Copilot Studio standard harness plus custom connector

Implement as connector tools:

```text
ClassifyIncomingEmail
RetrieveAnswerKnowledge
CreateGroundedResponseDraft
RemoveInternalRoutingBlock
```

### GitHub Copilot harness plus executable skill

Implement commands:

```text
classify-email
retrieve-knowledge
create-response-draft
remove-routing-block
```

### GitHub Copilot harness plus MCP

Use the same MCP tools as the Copilot Studio MCP path and add workflow instructions in `SKILL.md`.

---

# 7. Fetch and trigger workflow

```mermaid
flowchart TD
    T([Choose inbound trigger]) --> Q{Near-real-time required?}
    Q -->|Yes| W[Graph change-notification webhook]
    Q -->|No| D[Scheduled message delta query]
    W --> Q1[Validate, queue, and acknowledge]
    Q1 --> WORKER[Background worker]
    D --> WORKER
    WORKER --> FETCH[Get full message from Graph]
    FETCH --> CLASSIFY[Classify]
    CLASSIFY --> DRAFT[Create draft reply]
```

Microsoft Graph supports application-permission subscriptions for messages in shared mailboxes and can deliver change notifications through webhooks, Event Hubs, or Event Grid. citeturn9search126turn9search128 Message delta query is a per-folder pull mechanism and returns opaque next/delta links that should be preserved for subsequent synchronization. citeturn9search139turn9search141turn9search143

For Copilot Studio, event triggers can activate agents autonomously when external events occur, require generative orchestration, and receive payloads through connectors. The trigger connector uses the agent maker's account. citeturn9search132turn9search133 Keep Graph webhook validation in the workload-identity mailbox service, then pass a narrow work item to the agent flow.

For GitHub Copilot, run webhook/delta acquisition in an external worker. Use the harness for supervised commands and tool calls, not as the continuous mailbox listener.

---

# 8. Classification provider abstraction

```python
from typing import Protocol


class ClassificationProvider(Protocol):
    async def classify(
        self,
        subject: str,
        body: str,
        active_rules: list["ClassificationRule"],
    ) -> "ClassificationResult": ...
```

Provider factory:

```python
def build_classifier(settings, repository):
    mode = settings.classification_provider.lower()
    if mode == "rules":
        return RuleBasedClassifier(
            settings.classification_min_score,
            settings.classification_ambiguity_delta,
        )
    if mode == "foundry-bart":
        return FoundryBartClassifier(
            endpoint=settings.bart_endpoint,
            deployment=settings.bart_deployment,
            audience=settings.bart_audience,
            minimum_score=settings.classification_min_score,
            ambiguity_delta=settings.classification_ambiguity_delta,
        )
    if mode == "structured-model":
        return StructuredModelClassifier(...)
    raise RuntimeError(f"Unsupported classification provider: {mode}")
```

Configuration:

```dotenv
CLASSIFICATION_PROVIDER=foundry-bart
CLASSIFICATION_MIN_SCORE=0.62
CLASSIFICATION_AMBIGUITY_DELTA=0.08
BART_ENDPOINT=https://<endpoint-host>/score
BART_DEPLOYMENT=email-bart-v3
BART_AUDIENCE=https://ml.azure.com
```

The exact endpoint URL, audience, and request schema must be taken from the deployed endpoint's consume/code sample. Microsoft documentation confirms a managed deployment provides a REST endpoint, but the exact scoring schema depends on the deployment and serving implementation. citeturn11search142turn11search143turn11search144

---

# 9. BART feasibility and design choice

## 9.1 Feasibility conclusion

A BART-family model is a viable alternative when the objective is stable, high-volume text classification and you have representative labelled email data. It is not automatically multi-label: the classification head, training loss, thresholding, and serving code must be designed for multi-label output.

Use one of two BART strategies:

```mermaid
flowchart TD
    B{BART strategy} --> Z[Pretrained zero-shot classifier]
    B --> F[Fine-tuned multi-label sequence classifier]
    Z --> Z1[Fast proof of concept<br/>labels provided at inference]
    F --> F1[Production candidate<br/>requires labelled data and retraining]
    Z1 --> EVAL[Evaluate]
    F1 --> EVAL
    EVAL --> Q{Meets per-class precision,<br/>recall, and routing-risk thresholds?}
    Q -->|Yes| DEPLOY[Deploy behind provider contract]
    Q -->|No| IMPROVE[Improve data, labels, thresholds, or provider]
```

### Pretrained zero-shot option

A model based on BART and trained for natural-language inference can score candidate labels supplied at request time. This avoids an initial fine-tuning project, but must be evaluated on the organization's actual email languages and terminology.

### Fine-tuned multi-label option

Use a BART encoder-decoder or sequence-classification variant with one output logit per stable `modelLabel`. Train with binary cross entropy and apply a sigmoid per class. Select all labels above their configured threshold, optionally including labels within an ambiguity window of the highest score.

## 9.2 When to choose BART

```mermaid
flowchart TD
    S([Choose classification provider]) --> Q1{Enough representative labelled emails?}
    Q1 -->|No| Z[Start with rules or zero-shot BART]
    Q1 -->|Yes| Q2{Stable taxonomy and high recurring volume?}
    Q2 -->|Yes| F[Fine-tuned BART candidate]
    Q2 -->|No| R[Rules or structured model]
    F --> Q3{Model endpoint operations,<br/>monitoring, and retraining accepted?}
    Q3 -->|Yes| FB[Use Foundry-hosted fine-tuned BART]
    Q3 -->|No| R
    Z --> E[Evaluate and collect corrections]
    E --> Q1
```

Use BART only after checking the model license, data handling, language coverage, model risk, and endpoint cost. Microsoft explicitly notes that Hugging Face models are third-party products and that customers are responsible for license compliance and evaluation. citeturn11search142turn11search144

---

# 10. Build training data

Convert reviewed classification examples and labelled historical emails into JSONL.

Multi-label format:

```jsonl
{"id":"case-001","text":"Question about incorrect invoice 4711","labels":["invoice_question"]}
{"id":"case-002","text":"The contract and invoice amount are wrong","labels":["contract_question","invoice_question"]}
{"id":"case-003","text":"I cannot sign in and receive error AADSTS...","labels":["technical_support"]}
```

Do not use unreviewed classification examples as the only production training data. Split by conversation/thread, not random individual message, to reduce leakage between training and evaluation sets.

Training-data export code:

```python
import json
from pathlib import Path


def export_training_jsonl(reviewed_cases: list[dict], output: str) -> None:
    path = Path(output)
    with path.open("w", encoding="utf-8") as handle:
        for case in reviewed_cases:
            record = {
                "id": case["id"],
                "text": f"{case['subject']}\n{case['bodyText']}",
                "labels": sorted(set(case["modelLabels"])),
            }
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
```

Create and version a label map:

```json
{
  "invoice_question": 0,
  "contract_question": 1,
  "technical_support": 2
}
```

---

# 11. Fine-tune BART for multi-label classification

Reference training script:

```python
import json
import numpy as np
from datasets import load_dataset
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    DataCollatorWithPadding,
    Trainer,
    TrainingArguments,
)

MODEL_NAME = "facebook/bart-base"
LABEL_MAP = json.load(open("label-map.json", encoding="utf-8"))
ID_TO_LABEL = {value: key for key, value in LABEL_MAP.items()}

raw = load_dataset(
    "json",
    data_files={
        "train": "train.jsonl",
        "validation": "validation.jsonl",
        "test": "test.jsonl",
    },
)
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)


def preprocess(batch):
    encoded = tokenizer(
        batch["text"],
        truncation=True,
        max_length=1024,
    )
    encoded["labels"] = [
        [1.0 if label in labels else 0.0 for label in LABEL_MAP]
        for labels in batch["labels"]
    ]
    return encoded

encoded = raw.map(preprocess, batched=True, remove_columns=raw["train"].column_names)
model = AutoModelForSequenceClassification.from_pretrained(
    MODEL_NAME,
    num_labels=len(LABEL_MAP),
    problem_type="multi_label_classification",
    id2label=ID_TO_LABEL,
    label2id=LABEL_MAP,
)


def sigmoid(values):
    return 1 / (1 + np.exp(-values))


def metrics(result):
    probabilities = sigmoid(result.predictions)
    predictions = probabilities >= 0.5
    expected = result.label_ids.astype(bool)
    tp = np.logical_and(predictions, expected).sum()
    fp = np.logical_and(predictions, np.logical_not(expected)).sum()
    fn = np.logical_and(np.logical_not(predictions), expected).sum()
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"micro_precision": precision, "micro_recall": recall, "micro_f1": f1}

arguments = TrainingArguments(
    output_dir="outputs/email-bart",
    learning_rate=2e-5,
    per_device_train_batch_size=8,
    per_device_eval_batch_size=8,
    num_train_epochs=4,
    eval_strategy="epoch",
    save_strategy="epoch",
    load_best_model_at_end=True,
    metric_for_best_model="micro_f1",
    greater_is_better=True,
    report_to=[],
)

trainer = Trainer(
    model=model,
    args=arguments,
    train_dataset=encoded["train"],
    eval_dataset=encoded["validation"],
    tokenizer=tokenizer,
    data_collator=DataCollatorWithPadding(tokenizer),
    compute_metrics=metrics,
)
trainer.train()
trainer.evaluate(encoded["test"])
trainer.save_model("model/email-bart")
tokenizer.save_pretrained("model/email-bart")
```

This is a reference training implementation. Hyperparameters, class imbalance handling, threshold calibration, multilingual requirements, and model choice must be validated on the organization's data.

---

# 12. BART scoring service

`score.py` for a custom managed online deployment:

```python
import json
import os
import numpy as np
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

model = None
tokenizer = None
label_map = None


def init():
    global model, tokenizer, label_map
    model_dir = os.environ["AZUREML_MODEL_DIR"]
    model = AutoModelForSequenceClassification.from_pretrained(model_dir)
    tokenizer = AutoTokenizer.from_pretrained(model_dir)
    label_map = model.config.id2label
    model.eval()


def run(raw_data):
    request = json.loads(raw_data)
    texts = request.get("texts", [])
    if not texts or len(texts) > 32:
        return {"error": "texts must contain between 1 and 32 items"}
    encoded = tokenizer(
        texts,
        padding=True,
        truncation=True,
        max_length=1024,
        return_tensors="pt",
    )
    with torch.no_grad():
        logits = model(**encoded).logits
        probabilities = torch.sigmoid(logits).cpu().numpy()
    results = []
    for row in probabilities:
        scores = [
            {"label": label_map[str(index)] if str(index) in label_map else label_map[index],
             "score": float(score)}
            for index, score in enumerate(row)
        ]
        results.append(sorted(scores, key=lambda item: item["score"], reverse=True))
    return {"predictions": results}
```

`environment.yml`:

```yaml
name: email-bart-inference
channels:
  - conda-forge
dependencies:
  - python=3.11
  - pip
  - pip:
      - azureml-inference-server-http
      - torch
      - transformers
      - numpy
```

`endpoint.yml`:

```yaml
$schema: https://azuremlschemas.azureedge.net/latest/managedOnlineEndpoint.schema.json
name: email-bart-endpoint
auth_mode: aad_token
```

`deployment.yml`:

```yaml
$schema: https://azuremlschemas.azureedge.net/latest/managedOnlineDeployment.schema.json
name: email-bart-v3
endpoint_name: email-bart-endpoint
model: azureml:email-bart:3
code_configuration:
  code: ./inference
  scoring_script: score.py
environment:
  conda_file: ./inference/environment.yml
  image: mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04:latest
instance_type: Standard_DS3_v2
instance_count: 1
```

Microsoft's managed-online-endpoint documentation states that online endpoints provide scalable HTTPS/REST real-time inference and that managed endpoints handle serving, scaling, securing, and monitoring. citeturn11search143turn11search145 Verify the schema version, supported instance type, quota, and endpoint authentication in the target subscription before deployment.

Deployment commands:

```bash
az extension add -n ml
az ml model create --name email-bart --path ./model/email-bart --version 3
az ml online-endpoint create --file endpoint.yml
az ml online-deployment create --file deployment.yml --all-traffic
az ml online-endpoint show --name email-bart-endpoint
```

Foundry's current Hugging Face managed-compute experience is documented as preview and may not be available identically in every region or portal experience. citeturn11search144 If the exact BART model is not available in the Foundry catalog, register the fine-tuned model and deploy it through the associated managed online endpoint workflow.

---

# 13. Foundry BART classification provider

```python
import httpx
from azure.identity.aio import DefaultAzureCredential


class FoundryBartClassifier:
    def __init__(
        self,
        endpoint: str,
        audience: str,
        minimum_score: float,
        ambiguity_delta: float,
    ) -> None:
        self.endpoint = endpoint
        self.audience = audience
        self.minimum_score = minimum_score
        self.ambiguity_delta = ambiguity_delta
        self.credential = DefaultAzureCredential(
            exclude_interactive_browser_credential=True
        )

    async def classify(self, subject: str, body: str, active_rules: list):
        token = await self.credential.get_token(f"{self.audience}/.default")
        text = f"{subject}\n{body}"
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                self.endpoint,
                headers={
                    "Authorization": f"Bearer {token.token}",
                    "Content-Type": "application/json",
                },
                json={"texts": [text]},
            )
            response.raise_for_status()
            scores = response.json()["predictions"][0]

        rules_by_label = {rule.modelLabel: rule for rule in active_rules}
        known = [item for item in scores if item["label"] in rules_by_label]
        known.sort(key=lambda item: item["score"], reverse=True)
        best = known[0]["score"] if known else 0.0
        selected = [
            item for item in known
            if item["score"] >= self.minimum_score
            or (
                best >= self.minimum_score
                and best - item["score"] <= self.ambiguity_delta
            )
        ]
        matches = []
        for item in selected:
            rule = rules_by_label[item["label"]]
            matches.append({
                "className": rule.className,
                "classTarget": rule.classTarget,
                "classTargetEmail": str(rule.classTargetEmail),
                "score": item["score"],
                "reason": "Selected by the configured BART classification model.",
            })
        return {
            "classifications": matches,
            "needsHumanRoutingDecision": len(matches) != 1,
            "unclassified": len(matches) == 0,
            "provider": "foundry-bart",
        }
```

Do not use a static endpoint key when managed identity and Entra authentication are available. Restrict the calling workload through Azure RBAC and network controls.

---

# 14. Link BART into each orchestration path

## 14.1 Copilot Studio standard harness with MCP

BART is an internal classification provider behind the MCP tool. The agent should never call the model endpoint directly.

```mermaid
flowchart LR
    CS[Copilot Studio standard harness] --> MCP[classify_incoming_email tool]
    MCP --> SELECT[Classification provider factory]
    SELECT --> BART[Foundry BART endpoint]
    BART --> MAP[Validate labels against classification table]
    MAP --> RESULT[Multi-label result]
    RESULT --> DRAFT[create_grounded_response_draft tool]
```

Steps:

1. Set `CLASSIFICATION_PROVIDER=foundry-bart` on the MCP service.
2. Grant the MCP workload identity permission to invoke the model endpoint.
3. Keep BART endpoint details out of agent instructions.
4. MCP `classify_incoming_email` fetches the email, loads active classes, calls BART, validates labels, and returns all matches.
5. MCP `create_grounded_response_draft` optionally retrieves knowledge, generates the answer, prepends the routing block, and creates a reply draft.
6. MCP `remove_internal_routing_block` removes the marked block after explicit review.
7. Existing `prepare-send` refuses approval while the block remains.

## 14.2 Copilot Studio standard harness with custom connector

```mermaid
flowchart LR
    CS[Copilot Studio] --> CC[ClassifyIncomingEmail connector action]
    CC --> API[Mailbox REST API]
    API --> BART[Foundry BART endpoint]
    BART --> API
    API --> CC
    CS --> DRAFT[CreateGroundedResponseDraft action]
```

OpenAPI additions:

```yaml
paths:
  /v1/incoming/{messageId}/classify:
    post:
      operationId: ClassifyIncomingEmail
      summary: Classify a received email using the configured provider and return all plausible classes
  /v1/incoming/{messageId}/create-response-draft:
    post:
      operationId: CreateGroundedResponseDraft
      summary: Create a knowledge-grounded reply draft with an internal routing block
  /v1/drafts/{messageId}/remove-routing-block:
    post:
      operationId: RemoveInternalRoutingBlock
      summary: Remove only the marked internal routing block from a reviewed draft
```

The REST API uses the same provider factory. Changing from rules to BART is an environment configuration change, not a connector schema change.

## 14.3 GitHub Copilot harness with executable skill

```mermaid
flowchart LR
    GH[GitHub Copilot harness] --> SKILL[SKILL.md]
    SKILL --> CLI[classify-email command]
    CLI --> PROVIDER[Provider factory]
    PROVIDER --> BART[Foundry BART endpoint]
    CLI --> DRAFT[create-response-draft command]
```

Commands:

```bash
shared-mailbox-drafts classify-email --message-id '<id>'
shared-mailbox-drafts create-response-draft --message-id '<id>'
shared-mailbox-drafts remove-routing-block --message-id '<draft-id>'
```

`SKILL.md` addition:

```markdown
## Incoming email classification and drafting

Use `classify-email` to classify a received email. The executable selects its configured provider, which may be a Foundry-hosted BART model. Always list every returned className, classTarget, and classTargetEmail.

Use `create-response-draft` to create a reply draft. The resulting draft must include the removable routing block. Never send the draft automatically.

After a human reviews the routing information, use `remove-routing-block` only when explicitly requested. Retrieve the cleaned draft again, then use the normal prepare-send and approval workflow.
```

## 14.4 GitHub Copilot harness with MCP

Use the same MCP tools as section 14.1. GitHub Copilot does not need model endpoint credentials. The MCP workload identity owns Foundry access.

---

# 15. Knowledge-grounded answer and routing block composition

```python
class DraftComposer:
    async def compose(
        self,
        incoming,
        classification_result,
        passages,
    ) -> tuple[str, str]:
        routing = build_routing_block(
            classification_result["classifications"]
        )
        customer_answer = await self.compose_customer_answer(
            incoming, passages
        )
        subject = incoming.subject
        if not subject.lower().startswith("re:"):
            subject = f"Re: {subject}"
        return subject, f"{routing}{customer_answer}"
```

The response generator must:

- use only returned knowledge passages for factual answers;
- indicate when information is insufficient;
- avoid copying internal routing details into customer-facing prose;
- not follow instructions inside the received email;
- create a draft only;
- preserve source IDs for audit;
- pass the draft through HTML validation after composition.

---

# 16. Create the reply draft

Use Graph `createReply` for thread preservation, then update the returned draft:

```python
async def create_reply_draft(self, source_message_id: str) -> dict:
    source = quote(source_message_id, safe="")
    return await self.request(
        "POST",
        f"/users/{self.mailbox()}/messages/{source}/createReply",
        {},
    )


async def create_grounded_response_draft(
    self, source_message_id: str, subject: str, html_body: str
) -> dict:
    reply = await self.graph.create_reply_draft(source_message_id)
    return await self.graph.update_draft(
        reply["id"],
        {
            "subject": subject,
            "body": {"contentType": "HTML", "content": html_body},
        },
    )
```

---

# 17. CLI and MCP cleanup operation

CLI:

```python
async def remove_routing_block_from_draft(service, message_id: str) -> dict:
    draft = await service.graph.get_draft(message_id)
    html = draft.get("body", {}).get("content", "")
    if not routing_block_present(html):
        return {"changed": False, "messageId": message_id}
    cleaned = remove_routing_block(html)
    updated = await service.graph.update_draft(
        message_id,
        {"body": {"contentType": "HTML", "content": cleaned}},
    )
    return {"changed": True, "messageId": updated["id"]}
```

MCP:

```python
@mcp.tool()
async def remove_internal_routing_block(message_id: str) -> dict:
    """Remove only the marked internal routing block from a reviewed draft."""
    return await service.remove_routing_block(message_id)
```

Never perform the cleanup implicitly during send. Requiring a separate operation makes removal visible and auditable.

---

# 18. PowerShell: Foundry/Azure ML endpoint invocation test

```powershell
#Requires -Version 7.2
param(
    [Parameter(Mandatory)] [string]$EndpointUrl,
    [string]$Audience = 'https://ml.azure.com',
    [string]$Text = 'The amount on invoice 4711 is incorrect.'
)

Import-Module Az.Accounts
Connect-AzAccount
$token = (Get-AzAccessToken -ResourceUrl $Audience).Token

$body = @{
    texts = @($Text)
} | ConvertTo-Json -Depth 5

Invoke-RestMethod `
    -Method Post `
    -Uri $EndpointUrl `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType 'application/json' `
    -Body $body |
    ConvertTo-Json -Depth 10
```

Use the audience and scoring URL shown by the deployed endpoint's consume page. The exact values can differ by deployment type, so do not infer them from this example.

## Assign endpoint invocation access

The exact role assignment depends on the Foundry or Azure Machine Learning resource type and tenant governance. Microsoft documents Azure RBAC requirements for Foundry managed-compute deployment and invocation, including Foundry User for calling a deployment in the current Foundry experience. citeturn11search144 Assign the least-privileged role to the MCP/API workload identity at the narrowest supported scope, then verify invocation and remove any broader temporary role.

---

# 19. Model evaluation and operations

Evaluate each candidate provider on the same frozen test set:

```text
testCaseId
subject
body
expectedModelLabels
expectedClassUUIDs
expectedTargets
expectedTargetEmails
expectedHumanReview
language
```

Measure:

- per-class precision and recall;
- micro and macro F1;
- exact multi-label set match;
- unclassified detection;
- wrong-department routing rate;
- confidence calibration;
- draft groundedness;
- unsupported-claim rate;
- human correction rate;
- latency and cost per classified message.

Use traffic mirroring or controlled split traffic to compare model versions where supported. Azure ML documentation explicitly describes multiple deployments, traffic splitting, and mirrored traffic for managed online endpoints. citeturn11search143

Store with every result:

```text
provider
model name
model version
table version
threshold version
classification UUIDs
scores
source message ID hash
draft message ID hash
human corrections
```

Trigger retraining or review when:

- the classification taxonomy changes;
- a new recurring class appears;
- wrong-target rate exceeds the approved threshold;
- language distribution changes;
- label examples or business ownership change;
- model or tokenizer version changes.

---

# 20. Security requirements for Foundry BART

- Use workload identity and Entra authentication where supported.
- Do not expose the model endpoint as an agent tool.
- The mailbox service is the only component allowed to invoke it.
- Restrict endpoint invocation with Azure RBAC.
- Use private networking where required and supported.
- Do not log raw emails at the model endpoint.
- Minimize message content before inference.
- Validate every returned label against the current classification table.
- Reject unknown labels.
- Apply timeouts, retries, request-size limits, and circuit breaking.
- Keep the deterministic provider available as an explicit fallback only if its behavior is approved.
- Record model version with every decision.
- Review Hugging Face model licensing and supply-chain risk. Microsoft notes these models are third-party offerings and require customer evaluation. citeturn11search142turn11search144

---

# 21. Fallback orchestration

```mermaid
flowchart TD
    EMAIL[Email] --> BART[Foundry BART]
    BART --> OK{Endpoint succeeded?}
    OK -->|No| RULES[Approved deterministic fallback]
    OK -->|Yes| CONF{At least one label above threshold?}
    CONF -->|Yes| RESULT[Return all plausible matches]
    CONF -->|No| REVIEW[Unclassified, human review]
    RULES --> RCONF{Approved rule match?}
    RCONF -->|Yes| RESULT
    RCONF -->|No| REVIEW
    RESULT --> DRAFT[Create draft with routing block]
```

Do not route automatically on a low-confidence fallback. Do not silently change providers. Include `provider` and `modelVersion` in the result and audit record.

---

# 22. Step-by-step implementation plan

## Phase 1: Routing block

1. Add the three routing-block configuration settings.
2. Add the generator, detector, and removal functions.
3. Prepend the block to every classification-generated draft.
4. Add cleanup as a separate CLI, MCP, and connector operation.
5. Add a prepare-send guard that rejects drafts containing the block.
6. Test zero, one, and multiple classifications.

## Phase 2: Provider abstraction

1. Add `ClassificationProvider`.
2. Wrap the existing deterministic classifier.
3. Add provider selection through environment configuration.
4. Add provider/model version to results and audit.
5. Preserve identical output schemas across providers.

## Phase 3: BART proof of concept

1. Export active table labels and reviewed examples.
2. Evaluate a pretrained zero-shot BART-family candidate.
3. Establish a frozen multi-label test set.
4. Record per-class and routing-risk metrics.
5. Decide whether sufficient labelled data exists for fine-tuning.

## Phase 4: Fine-tuning

1. Create reviewed train, validation, and test JSONL files.
2. Create a stable label map using `modelLabel`.
3. Train a multi-label BART model.
4. Calibrate global or per-class thresholds.
5. Validate languages, long-message truncation, imbalance, and adversarial messages.
6. Register the approved model artifact and model card.

## Phase 5: Foundry deployment

1. Confirm whether the chosen Hugging Face model is available in the current Foundry project.
2. If available, deploy it using managed compute and use the generated consume contract.
3. Otherwise, register the fine-tuned artifact and deploy it as a managed online endpoint.
4. Configure Entra/Azure RBAC invocation.
5. Configure networking, scaling, logs, and alerts.
6. Test the endpoint with the supplied PowerShell script.
7. Put endpoint URL and audience in protected configuration.

## Phase 6: Harness integration

1. Copilot Studio MCP: configure the MCP service provider as `foundry-bart`.
2. Copilot Studio custom connector: keep OpenAPI unchanged except for classification/draft/cleanup operations.
3. GitHub Copilot executable: add the classify, create-draft, and cleanup commands.
4. GitHub Copilot MCP: reuse the same MCP tools.
5. Never give a harness direct model endpoint credentials.

## Phase 7: Production controls

1. Enforce removable-block detection before approval.
2. Keep auto-send disabled.
3. Enable durable idempotency and approval replay protection.
4. Monitor endpoint availability, latency, drift, and class distribution.
5. Record human corrections for controlled retraining.
6. Re-run evaluation after every model, threshold, or taxonomy change.

---

# 23. Acceptance criteria

The extension is ready only when:

- every generated classification draft contains the exact removable routing block;
- the block includes every returned `className`, `classTarget`, and `classTargetEmail`;
- zero matches produce `Unclassified` and `Manual review`;
- the block is placed at the top and marked with `data-internal-routing-block="true"`;
- prepare-send rejects a draft while the block remains;
- cleanup removes only the marked block and is audited;
- all provider outputs are validated against the classification table;
- BART unknown labels are rejected;
- multi-label thresholds are evaluated and versioned;
- Foundry/model endpoint access uses least privilege;
- harnesses never receive model endpoint credentials;
- knowledge-generated statements use returned passages only;
- drafts are never sent automatically;
- the existing version-bound human approval remains mandatory;
- model, table, threshold, classification, and draft versions are auditable;
- all zero-class, single-class, and multi-class tests pass.

---

# 24. Reference documentation

- [Deploy Hugging Face models in the current Microsoft Foundry experience](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/hugging-face-models)
- [Deploy Hugging Face models in Foundry classic](https://learn.microsoft.com/en-us/azure/foundry-classic/how-to/deploy-models-managed-hugging-face)
- [Deploy Hugging Face models to Azure Machine Learning online endpoints](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-deploy-models-from-huggingface?view=azureml-api-2)
- [Deploy models to managed online endpoints](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-deploy-online-endpoints?view=azureml-api-2)
- [Microsoft Graph Outlook change notifications](https://learn.microsoft.com/en-us/graph/outlook-change-notifications-overview)
- [Microsoft Graph message delta query](https://learn.microsoft.com/en-us/graph/delta-query-messages)
- [Copilot Studio event triggers](https://learn.microsoft.com/en-us/microsoft-copilot-studio/authoring-triggers-about)


---

# Appendix A: Dataverse Tracking, Email Deep Links, and Original Email Layout

# Updated Optional Module: Original Email, Routing Block, and Dataverse Classification Audit

**Example mailbox:** `service@instruo365.de`  
**Authentication:** application or workload identity  
**Default:** create and update drafts only; never send automatically

This document is a self-contained update to the shared-mailbox classification design. It adds:

1. The original sender address as the first line of the removable block.
2. The original email below the generated answer in every reply draft.
3. A Dataverse data model that records the original email, draft email, every proposed classification, the final classification, override status, override reason, and reviewer comments.
4. Outlook on the web deep links for the original and draft messages.
5. Python code, REST/MCP contracts, and PowerShell provisioning examples.

---

# 1. Required draft layout

Every generated reply draft must have this order:

```text
1. Removable internal routing block
2. Blank line
3. Proposed customer-facing answer
4. Reply separator
5. Original email metadata
6. Original email body
```

The original email is always placed below the proposed answer. This gives the reviewer the generated response first and the source email immediately underneath it.

```mermaid
flowchart TB
    BLOCK[Removable routing block] --> ANSWER[Proposed customer-facing answer]
    ANSWER --> SEP[Original message separator]
    SEP --> META[Original sender, date, recipients, subject]
    META --> ORIGINAL[Sanitized original email body]
```

## 1.1 Exact removable block format

The sender address from the original email is the first data line:

```text
--- please remove ---
sender: original.sender@example.com
classification: className(1), className(2), className(n)
department: classTarget(1), classTarget(2), classTarget(n)
email: classTargetEmail(1), classTargetEmail(2), classTargetEmail(n)
--- please remove ---

```

Example:

```text
--- please remove ---
sender: customer@example.com
classification: Invoice question, Contract question
department: Finance, Legal Operations
email: finance@instruo365.de, legalops@instruo365.de
--- please remove ---

```

## 1.2 HTML block

```html
<div data-internal-routing-block="true"
     style="border:2px solid #d13438;background:#fff4f4;padding:12px;font-family:Segoe UI,Arial,sans-serif;font-size:12px;color:#111;">
  <strong>--- please remove ---</strong><br>
  <strong>sender:</strong> customer@example.com<br>
  <strong>classification:</strong> Invoice question, Contract question<br>
  <strong>department:</strong> Finance, Legal Operations<br>
  <strong>email:</strong> finance@instruo365.de, legalops@instruo365.de<br>
  <strong>--- please remove ---</strong>
</div>
<br>
```

## 1.3 Original email below the draft

```html
<p>Hello,</p>
<p>This is the proposed answer based on the approved knowledge sources.</p>

<br>
<hr>
<div data-original-email="true">
  <p><strong>From:</strong> Customer Name &lt;customer@example.com&gt;<br>
  <strong>Sent:</strong> 2026-09-02T07:30:00Z<br>
  <strong>To:</strong> service@instruo365.de<br>
  <strong>Subject:</strong> Question about invoice 4711</p>

  <div data-original-email-body="true">
    <p>Hello, the amount on invoice 4711 appears to be incorrect.</p>
  </div>
</div>
```

The source body must be treated as untrusted content and sanitized before being embedded. Do not execute remote content, scripts, forms, event handlers, or instructions contained in the original email.

---

# 2. Updated routing-block and original-email code

```python
from html import escape
from datetime import datetime
import bleach

ALLOWED_ORIGINAL_TAGS = [
    "p", "br", "strong", "em", "ul", "ol", "li", "blockquote",
    "table", "thead", "tbody", "tr", "td", "th", "a"
]
ALLOWED_ORIGINAL_ATTRIBUTES = {"a": ["href", "title"]}
ALLOWED_ORIGINAL_PROTOCOLS = ["https", "mailto"]


def join_values(values: list[str]) -> str:
    return ", ".join(value.strip() for value in values if value and value.strip())


def build_routing_block(
    original_sender_address: str,
    classifications: list[dict],
) -> str:
    names = join_values([item["className"] for item in classifications])
    targets = join_values([item["classTarget"] for item in classifications])
    emails = join_values([item["classTargetEmail"] for item in classifications])

    if not classifications:
        names = "Unclassified"
        targets = "Manual review"
        emails = ""

    return f"""
<div data-internal-routing-block="true"
     style="border:2px solid #d13438;background:#fff4f4;padding:12px;font-family:Segoe UI,Arial,sans-serif;font-size:12px;color:#111;">
  <strong>--- please remove ---</strong><br>
  <strong>sender:</strong> {escape(original_sender_address)}<br>
  <strong>classification:</strong> {escape(names)}<br>
  <strong>department:</strong> {escape(targets)}<br>
  <strong>email:</strong> {escape(emails)}<br>
  <strong>--- please remove ---</strong>
</div>
<br>
""".strip()


def sanitize_original_email_body(content: str, content_type: str) -> str:
    if content_type.lower() != "html":
        return f"<pre>{escape(content)}</pre>"
    return bleach.clean(
        content,
        tags=ALLOWED_ORIGINAL_TAGS,
        attributes=ALLOWED_ORIGINAL_ATTRIBUTES,
        protocols=ALLOWED_ORIGINAL_PROTOCOLS,
        strip=True,
    )


def build_original_email_section(message: dict) -> str:
    sender = message.get("sender", {}).get("emailAddress", {})
    sender_name = sender.get("name", "")
    sender_address = sender.get("address", "")
    recipients = message.get("toRecipients", [])
    to_line = join_values([
        item.get("emailAddress", {}).get("address", "")
        for item in recipients
    ])
    original_body = message.get("body", {})
    safe_body = sanitize_original_email_body(
        original_body.get("content", ""),
        original_body.get("contentType", "HTML"),
    )
    sender_display = (
        f"{escape(sender_name)} &lt;{escape(sender_address)}&gt;"
        if sender_name else escape(sender_address)
    )
    return f"""
<br>
<hr>
<div data-original-email="true">
  <p><strong>From:</strong> {sender_display}<br>
  <strong>Sent:</strong> {escape(message.get('receivedDateTime', ''))}<br>
  <strong>To:</strong> {escape(to_line)}<br>
  <strong>Subject:</strong> {escape(message.get('subject', ''))}</p>
  <div data-original-email-body="true">{safe_body}</div>
</div>
""".strip()


def build_complete_draft_body(
    message: dict,
    classifications: list[dict],
    proposed_answer_html: str,
) -> str:
    sender_address = (
        message.get("sender", {})
        .get("emailAddress", {})
        .get("address", "")
    )
    routing = build_routing_block(sender_address, classifications)
    original = build_original_email_section(message)
    return f"{routing}<br>{proposed_answer_html}{original}"
```

## Important reply-body behavior

Microsoft Graph supports creating a draft reply and subsequently updating that draft. citeturn12view156turn12search160 This design explicitly builds the complete body, including the original email section, rather than assuming a particular Outlook client rendering. The implementation should compare a sample `createReply` body in the target tenant before deciding whether to replace the whole body or preserve Graph-generated quoted content.

---

# 3. Deep links to original and draft messages

Microsoft Graph's message resource includes a `webLink` property described as a URL that opens the message in Outlook on the web. The user may be prompted to sign in, and the URL cannot be used in an iframe. citeturn12view156

Therefore, it is possible to store deep links for both the original email and the draft, provided Graph returns `webLink` for each fetched message.

## 3.1 Fetch identifiers and deep-link properties

Add these properties to `$select`:

```text
id,internetMessageId,changeKey,conversationId,webLink,subject,sender,
receivedDateTime,body,toRecipients,isDraft,parentFolderId
```

Python:

```python
MESSAGE_SELECT = (
    "id,internetMessageId,changeKey,conversationId,webLink,subject,sender,"
    "receivedDateTime,body,toRecipients,isDraft,parentFolderId"
)
```

## 3.2 Which identifiers to store

Store all of the following:

- Graph message `id`
- `internetMessageId` for the received email when available
- `conversationId`
- `changeKey`
- `webLink`
- mailbox address
- draft Graph message `id`
- draft `changeKey`
- draft `webLink`

Microsoft documents that a message's default Graph ID can change when an item is moved between containers. It also documents the `Prefer: IdType="ImmutableId"` header as a way to request immutable identifiers, with lifecycle limitations where applicable. citeturn12view156turn12search157

Recommended Graph request header:

```http
Prefer: IdType="ImmutableId"
```

The draft ID should not be treated as the permanent ID of the subsequently sent item. Keep the tracking record, original identifiers, draft identifiers, and final-send audit data separately.

## 3.3 Dataverse URL columns

Store `webLink` values in Dataverse URL columns:

```text
originalEmailWebLink
draftEmailWebLink
```

A model-driven app can display URL columns as selectable links, subject to normal user permissions and Outlook sign-in. Do not construct Outlook links manually when Graph provides `webLink`.

---

# 4. Recommended Dataverse data model

Use two custom tables rather than putting an arbitrary number of classifications into one row.

```mermaid
erDiagram
    EMAIL_PROCESSING ||--o{ CLASSIFICATION_DECISION : contains
    EMAIL_PROCESSING {
        guid processingId PK
        string processingName
        string mailboxAddress
        string originalGraphMessageId
        string originalInternetMessageId
        string originalConversationId
        string originalChangeKey
        url originalEmailWebLink
        string originalSenderAddress
        string originalSubject
        string draftGraphMessageId
        string draftChangeKey
        url draftEmailWebLink
        boolean classificationOverrideRequired
        text overrideComment
        string processingStatus
        datetime classifiedOn
        datetime draftCreatedOn
    }
    CLASSIFICATION_DECISION {
        guid decisionId PK
        guid processingId FK
        guid classificationUuid
        string className
        string classTarget
        string classTargetEmail
        decimal score
        text classificationReason
        boolean selectedByClassifier
        boolean isFinalClassification
        boolean wasOverwritten
        text overrideComment
        string provider
        string modelVersion
        datetime decidedOn
    }
```

## 4.1 Email Processing table

Suggested display name:

```text
Email Classification Processing
```

Suggested logical name with example publisher prefix:

```text
ins_emailclassificationprocessing
```

Columns:

| Display name | Suggested schema name | Type | Purpose |
|---|---|---|---|
| Processing | `ins_name` | Text, primary name | Human-readable tracking name |
| Mailbox address | `ins_mailboxaddress` | Email/Text | Shared mailbox |
| Original Graph message ID | `ins_originalgraphmessageid` | Multiline text | Graph ID, potentially long |
| Original Internet message ID | `ins_originalinternetmessageid` | Multiline text | RFC message identifier |
| Original conversation ID | `ins_originalconversationid` | Multiline text | Conversation correlation |
| Original change key | `ins_originalchangekey` | Multiline text | Version observed during processing |
| Original email link | `ins_originalemailweblink` | URL | Graph `webLink` |
| Original sender address | `ins_originalsenderaddress` | Email | Sender of received message |
| Original subject | `ins_originalsubject` | Text | Message subject |
| Draft Graph message ID | `ins_draftgraphmessageid` | Multiline text | Draft Graph ID |
| Draft change key | `ins_draftchangekey` | Multiline text | Draft version |
| Draft email link | `ins_draftemailweblink` | URL | Draft Graph `webLink` |
| Override required | `ins_overrideRequired` | Yes/No | Reviewer indicates classification needs change |
| Override comment | `ins_overridecomment` | Multiline text | Required when override is activated |
| Processing status | `ins_processingstatus` | Choice | Received, Classified, Draft created, Review, Approved, Sent, Failed |
| Classified on | `ins_classifiedon` | Date and time | Classification timestamp |
| Draft created on | `ins_draftcreatedon` | Date and time | Draft timestamp |

## 4.2 Classification Decision table

Suggested display name:

```text
Email Classification Decision
```

Suggested logical name:

```text
ins_emailclassificationdecision
```

Create one row for every proposed classification.

| Display name | Suggested schema name | Type | Purpose |
|---|---|---|---|
| Decision | `ins_name` | Text, primary name | Human-readable row name |
| Processing record | `ins_processingid` | Lookup | Parent Email Processing row |
| Classification UUID | `ins_classificationuuid` | Text/GUID | Source classification identity |
| Classification | `ins_classname` | Text | `className` snapshot |
| Department | `ins_classtarget` | Text | `classTarget` snapshot |
| Department email | `ins_classtargetemail` | Email | `classTargetEmail` snapshot |
| Score | `ins_score` | Decimal | Provider score |
| Classification reason | `ins_classificationreason` | Multiline text | Why the classification was proposed |
| Selected by classifier | `ins_selectedbyclassifier` | Yes/No | Proposed by automated classifier |
| Final classification | `ins_isfinalclassification` | Yes/No | Selected after review |
| Was overwritten | `ins_wasoverwritten` | Yes/No | Automated proposal changed by reviewer |
| Override comment | `ins_overridecomment` | Multiline text | Explanation of manual change |
| Provider | `ins_provider` | Text/Choice | rules, Foundry BART, structured model |
| Model version | `ins_modelversion` | Text | Deployed model version |
| Decided on | `ins_decidedon` | Date and time | Decision timestamp |

## 4.3 Override semantics

The user requested a flag indicating that classification must be overwritten and a comment when someone overwrites it. Use this controlled workflow:

```mermaid
stateDiagram-v2
    [*] --> Classified
    Classified --> ReviewRequired: zero or multiple classes
    Classified --> ReviewRequired: reviewer sets Override required = Yes
    ReviewRequired --> Overwritten: reviewer selects final class and enters comment
    Overwritten --> ReadyForDraft: comment present and one or more final classes selected
    Classified --> ReadyForDraft: accepted without override
    ReadyForDraft --> DraftCreated
```

Rules:

1. `Override required = Yes` means the automated result must not be treated as final.
2. When override is required, `Override comment` is mandatory.
3. Set `wasOverwritten = Yes` on automated decision rows that are no longer final.
4. Create or update the final decision rows with `isFinalClassification = Yes`.
5. Preserve the original automated rows; do not delete them.
6. Record reviewer identity and modification timestamp through Dataverse ownership/audit capabilities or explicit reviewer columns.
7. Regenerate the removable draft block from final classifications after an override.
8. Any draft change invalidates the earlier prepare-send approval.

---

# 5. Dataverse processing workflow

```mermaid
sequenceDiagram
    participant Worker
    participant Graph
    participant Classifier
    participant DV as Dataverse
    participant Drafts as Shared mailbox Drafts
    participant Reviewer

    Worker->>Graph: Fetch original email including webLink
    Graph-->>Worker: IDs, sender, body, webLink
    Worker->>DV: Upsert Email Processing row
    Worker->>Classifier: Classify message
    Classifier-->>Worker: All proposed classifications and reasons
    loop Every proposed classification
        Worker->>DV: Create Classification Decision row
    end
    Worker->>Drafts: Create reply draft with routing block and original below
    Drafts-->>Worker: Draft IDs, changeKey, webLink
    Worker->>DV: Update processing row with draft references
    Reviewer->>DV: Accept or set override required and comment
    Worker->>Drafts: Rebuild routing block after override
```

---

# 6. Upsert and persistence code

Dataverse alternate keys are intended for identifying records by business columns when the Dataverse primary GUID is not available. They can be used through the Dataverse Web API, and key columns must be configured on the table. citeturn12search150turn12search153turn12search154

Recommended alternate key on Email Processing:

```text
mailboxAddress + originalInternetMessageId
```

If `internetMessageId` is unavailable or contains values unsuitable for the selected key design, use a deterministic SHA-256 tracking key stored in a single-line text column:

```python
import hashlib


def processing_external_key(mailbox: str, internet_message_id: str, graph_id: str) -> str:
    source = f"{mailbox.lower()}|{internet_message_id or graph_id}"
    return hashlib.sha256(source.encode("utf-8")).hexdigest()
```

Suggested alternate key:

```text
ins_externalkey
```

## 6.1 Dataverse client

```python
import httpx
from azure.identity.aio import DefaultAzureCredential


class DataverseClient:
    def __init__(self, environment_url: str) -> None:
        self.base = environment_url.rstrip("/")
        self.credential = DefaultAzureCredential(
            exclude_interactive_browser_credential=True
        )

    async def headers(self) -> dict:
        token = await self.credential.get_token(f"{self.base}/.default")
        return {
            "Authorization": f"Bearer {token.token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
        }

    async def create(self, entity_set: str, payload: dict) -> str | None:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{self.base}/api/data/v9.2/{entity_set}",
                headers={**await self.headers(), "Prefer": "return=representation"},
                json=payload,
            )
            response.raise_for_status()
            return response.json()

    async def patch(self, relative_path: str, payload: dict) -> None:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.patch(
                f"{self.base}/api/data/v9.2/{relative_path}",
                headers=await self.headers(),
                json=payload,
            )
            response.raise_for_status()
```

## 6.2 Create tracking row

Actual entity-set and lookup navigation names depend on the publisher prefix and generated metadata. Replace example names with values from the target environment.

```python
async def create_processing_record(dv, mailbox: str, original: dict) -> dict:
    sender = original.get("sender", {}).get("emailAddress", {})
    external_key = processing_external_key(
        mailbox,
        original.get("internetMessageId", ""),
        original["id"],
    )
    payload = {
        "ins_name": f"Email: {original.get('subject', '')[:80]}",
        "ins_externalkey": external_key,
        "ins_mailboxaddress": mailbox,
        "ins_originalgraphmessageid": original["id"],
        "ins_originalinternetmessageid": original.get("internetMessageId"),
        "ins_originalconversationid": original.get("conversationId"),
        "ins_originalchangekey": original.get("changeKey"),
        "ins_originalemailweblink": original.get("webLink"),
        "ins_originalsenderaddress": sender.get("address"),
        "ins_originalsubject": original.get("subject"),
        "ins_overrideRequired": False,
        "ins_processingstatus": 100000000,
    }
    return await dv.create("ins_emailclassificationprocessings", payload)
```

## 6.3 Store every classification

```python
async def store_classification_decisions(
    dv,
    processing_id: str,
    classifications: list[dict],
    provider: str,
    model_version: str,
) -> None:
    for item in classifications:
        payload = {
            "ins_name": item["className"],
            "ins_classificationuuid": item["uuid"],
            "ins_classname": item["className"],
            "ins_classtarget": item["classTarget"],
            "ins_classtargetemail": item["classTargetEmail"],
            "ins_score": item.get("score"),
            "ins_classificationreason": item.get("reason"),
            "ins_selectedbyclassifier": True,
            "ins_isfinalclassification": False,
            "ins_wasoverwritten": False,
            "ins_provider": provider,
            "ins_modelversion": model_version,
            "ins_ProcessingId@odata.bind": (
                f"/ins_emailclassificationprocessings({processing_id})"
            ),
        }
        await dv.create("ins_emailclassificationdecisions", payload)
```

## 6.4 Update draft identifiers and link

```python
async def attach_draft_reference(dv, processing_id: str, draft: dict) -> None:
    await dv.patch(
        f"ins_emailclassificationprocessings({processing_id})",
        {
            "ins_draftgraphmessageid": draft["id"],
            "ins_draftchangekey": draft.get("changeKey"),
            "ins_draftemailweblink": draft.get("webLink"),
            "ins_processingstatus": 100000002,
        },
    )
```

## 6.5 Apply override

```python
async def apply_classification_override(
    dv,
    processing_id: str,
    override_comment: str,
    final_decision_ids: list[str],
    automatic_decision_ids: list[str],
) -> None:
    if not override_comment.strip():
        raise ValueError("Override comment is required")

    await dv.patch(
        f"ins_emailclassificationprocessings({processing_id})",
        {
            "ins_overrideRequired": True,
            "ins_overridecomment": override_comment,
            "ins_processingstatus": 100000003,
        },
    )

    for decision_id in automatic_decision_ids:
        await dv.patch(
            f"ins_emailclassificationdecisions({decision_id})",
            {
                "ins_wasoverwritten": True,
                "ins_isfinalclassification": False,
                "ins_overridecomment": override_comment,
            },
        )

    for decision_id in final_decision_ids:
        await dv.patch(
            f"ins_emailclassificationdecisions({decision_id})",
            {
                "ins_isfinalclassification": True,
                "ins_overridecomment": override_comment,
            },
        )
```

Review the generated relationship navigation name before using `@odata.bind` in production.

---

# 7. Model-driven app review interface

Suggested main form for Email Classification Processing:

```text
Header
- Processing status
- Override required
- Owner/reviewer

Original email section
- Sender
- Subject
- Original email link
- Received/classified time

Draft section
- Draft email link
- Draft created time
- Draft change key

Classification decisions subgrid
- Classification
- Department
- Department email
- Score
- Reason
- Final classification
- Was overwritten

Override section
- Override required
- Override comment
```

Business rule recommendation:

```mermaid
flowchart TD
    FLAG{Override required = Yes?}
    FLAG -->|No| OPTIONAL[Override comment optional]
    FLAG -->|Yes| REQUIRE[Override comment required]
    REQUIRE --> FINAL{At least one final classification?}
    FINAL -->|No| BLOCK[Block Ready for Draft / Approved status]
    FINAL -->|Yes| REBUILD[Rebuild routing block and invalidate approval]
```

Enable Dataverse auditing on both custom tables and on the override/final-classification columns according to organizational policy.

---

# 8. REST, MCP, and executable additions

## MCP tools

```text
get_classification_processing_record
set_classification_override
rebuild_draft_routing_block
open_original_email_link
open_draft_email_link
```

`open_*_email_link` should return the stored URL rather than fetching the message. The client/user opens it under their own Outlook permissions.

## Custom connector operations

```text
GetClassificationProcessingRecord
SetClassificationOverride
RebuildDraftRoutingBlock
GetOriginalEmailLink
GetDraftEmailLink
```

## Executable-skill commands

```bash
shared-mailbox-drafts get-processing-record --processing-id '<guid>'
shared-mailbox-drafts set-classification-override --processing-id '<guid>' --input-file override.json
shared-mailbox-drafts rebuild-routing-block --processing-id '<guid>'
```

## GitHub Copilot/Copilot Studio instructions

```markdown
When creating a classification-generated response draft:

1. Include the sender address of the original email as the first line inside the removable routing block.
2. Include all plausible classifications, departments, and department email addresses.
3. Place the proposed answer below the routing block.
4. Place the sanitized original email below the proposed answer.
5. Store the original email IDs/link, every classification decision, and the resulting draft IDs/link in Dataverse.
6. If Override required is enabled, require a reviewer comment and final classification selection.
7. Rebuild the routing block from final classifications after an override.
8. Never send while the routing block remains.
9. Any override or draft update invalidates an earlier send approval.
```

---

# 9. PowerShell: create the Dataverse tables

The script below is a reference metadata-provisioning script using the Dataverse Web API. Run it first in a development environment. Publisher prefixes, choice values, entity-set names, relationship schema names, and metadata payloads must be validated against the target environment.

```powershell
#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$EnvironmentUrl,
    [string]$PublisherPrefix = 'ins'
)

$ErrorActionPreference = 'Stop'
Import-Module Az.Accounts
Connect-AzAccount

$EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
$token = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl).Token
$headers = @{
    Authorization = "Bearer $token"
    'Content-Type' = 'application/json'
    Accept = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version' = '4.0'
}

function Invoke-DataverseMetadataPost {
    param([string]$Path, [hashtable]$Body)
    Invoke-RestMethod `
        -Method Post `
        -Uri "$EnvironmentUrl/api/data/v9.2/$Path" `
        -Headers $headers `
        -Body ($Body | ConvertTo-Json -Depth 30)
}

function New-StringAttributeBody {
    param(
        [string]$SchemaName,
        [string]$DisplayName,
        [int]$MaxLength = 500,
        [string]$FormatName = 'Text'
    )
    return @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = 'None'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        DisplayName = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        MaxLength = $MaxLength
        FormatName = @{ Value = $FormatName }
    }
}

function Add-Attribute {
    param([string]$EntityLogicalName, [hashtable]$Definition)
    Invoke-DataverseMetadataPost `
        -Path "EntityDefinitions(LogicalName='$EntityLogicalName')/Attributes" `
        -Body $Definition | Out-Null
}

$processingSchema = "${PublisherPrefix}_EmailClassificationProcessing"
$processingLogical = "${PublisherPrefix}_emailclassificationprocessing"
$decisionSchema = "${PublisherPrefix}_EmailClassificationDecision"
$decisionLogical = "${PublisherPrefix}_emailclassificationdecision"

$processingEntity = @{
    '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
    SchemaName = $processingSchema
    DisplayName = @{ LocalizedLabels = @(@{ Label = 'Email Classification Processing'; LanguageCode = 1033 }) }
    DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = 'Email Classification Processings'; LanguageCode = 1033 }) }
    Description = @{ LocalizedLabels = @(@{ Label = 'Tracks original emails, drafts, and classification review.'; LanguageCode = 1033 }) }
    OwnershipType = 'UserOwned'
    IsActivity = $false
    HasActivities = $false
    HasNotes = $true
    PrimaryNameAttribute = "${PublisherPrefix}_name"
    Attributes = @(
        (New-StringAttributeBody -SchemaName "${PublisherPrefix}_Name" -DisplayName 'Processing' -MaxLength 200)
    )
}

$decisionEntity = @{
    '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
    SchemaName = $decisionSchema
    DisplayName = @{ LocalizedLabels = @(@{ Label = 'Email Classification Decision'; LanguageCode = 1033 }) }
    DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = 'Email Classification Decisions'; LanguageCode = 1033 }) }
    Description = @{ LocalizedLabels = @(@{ Label = 'Stores every proposed and final email classification.'; LanguageCode = 1033 }) }
    OwnershipType = 'UserOwned'
    IsActivity = $false
    HasActivities = $false
    HasNotes = $true
    PrimaryNameAttribute = "${PublisherPrefix}_name"
    Attributes = @(
        (New-StringAttributeBody -SchemaName "${PublisherPrefix}_Name" -DisplayName 'Decision' -MaxLength 200)
    )
}

if ($PSCmdlet.ShouldProcess($processingSchema, 'Create Dataverse table')) {
    Invoke-DataverseMetadataPost -Path 'EntityDefinitions' -Body $processingEntity | Out-Null
}
if ($PSCmdlet.ShouldProcess($decisionSchema, 'Create Dataverse table')) {
    Invoke-DataverseMetadataPost -Path 'EntityDefinitions' -Body $decisionEntity | Out-Null
}

$processingStrings = @(
    @('MailboxAddress','Mailbox address',320,'Email'),
    @('ExternalKey','External key',64,'Text'),
    @('OriginalGraphMessageId','Original Graph message ID',4000,'TextArea'),
    @('OriginalInternetMessageId','Original Internet message ID',4000,'TextArea'),
    @('OriginalConversationId','Original conversation ID',4000,'TextArea'),
    @('OriginalChangeKey','Original change key',4000,'TextArea'),
    @('OriginalEmailWebLink','Original email link',2000,'Url'),
    @('OriginalSenderAddress','Original sender address',320,'Email'),
    @('OriginalSubject','Original subject',500,'Text'),
    @('DraftGraphMessageId','Draft Graph message ID',4000,'TextArea'),
    @('DraftChangeKey','Draft change key',4000,'TextArea'),
    @('DraftEmailWebLink','Draft email link',2000,'Url'),
    @('OverrideComment','Override comment',4000,'TextArea')
)
foreach ($column in $processingStrings) {
    Add-Attribute -EntityLogicalName $processingLogical -Definition (
        New-StringAttributeBody `
            -SchemaName "${PublisherPrefix}_$($column[0])" `
            -DisplayName $column[1] `
            -MaxLength $column[2] `
            -FormatName $column[3]
    )
}

$decisionStrings = @(
    @('ClassificationUuid','Classification UUID',100,'Text'),
    @('ClassName','Classification',200,'Text'),
    @('ClassTarget','Department',200,'Text'),
    @('ClassTargetEmail','Department email',320,'Email'),
    @('ClassificationReason','Classification reason',4000,'TextArea'),
    @('OverrideComment','Override comment',4000,'TextArea'),
    @('Provider','Provider',100,'Text'),
    @('ModelVersion','Model version',100,'Text')
)
foreach ($column in $decisionStrings) {
    Add-Attribute -EntityLogicalName $decisionLogical -Definition (
        New-StringAttributeBody `
            -SchemaName "${PublisherPrefix}_$($column[0])" `
            -DisplayName $column[1] `
            -MaxLength $column[2] `
            -FormatName $column[3]
    )
}

function Add-BooleanAttribute {
    param([string]$EntityLogicalName,[string]$SchemaName,[string]$DisplayName)
    $body = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
        SchemaName = $SchemaName
        DisplayName = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        RequiredLevel = @{ Value = 'None'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        DefaultValue = $false
        OptionSet = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
            TrueOption = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = 'Yes'; LanguageCode = 1033 }) } }
            FalseOption = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = 'No'; LanguageCode = 1033 }) } }
        }
    }
    Add-Attribute -EntityLogicalName $EntityLogicalName -Definition $body
}

Add-BooleanAttribute $processingLogical "${PublisherPrefix}_OverrideRequired" 'Override required'
Add-BooleanAttribute $decisionLogical "${PublisherPrefix}_SelectedByClassifier" 'Selected by classifier'
Add-BooleanAttribute $decisionLogical "${PublisherPrefix}_IsFinalClassification" 'Final classification'
Add-BooleanAttribute $decisionLogical "${PublisherPrefix}_WasOverwritten" 'Was overwritten'

Write-Host 'Create the processing-to-decision one-to-many relationship, decimal score, choices, date/time columns, alternate key, forms, views, business rules, and auditing in a solution after verifying generated metadata names.'
```

## 9.1 Why the script stops short of all customization

The script creates the core tables and text/URL/boolean columns. The relationship, choices, decimal precision, date/time behavior, alternate key, forms, views, business rules, and auditing should be created and validated in a development solution because their generated logical/navigation names and publisher context are environment-specific. Dataverse supports defining alternate keys through Power Apps or programmatically; alternate keys can then be used by the Web API to reference rows. citeturn12search150turn12search153turn12search154

---

# 10. Manual Dataverse completion steps

1. Add both tables to an unmanaged development solution.
2. Create a one-to-many relationship from Email Classification Processing to Email Classification Decision.
3. Add a decimal score column to Decision, with precision suitable for values from 0 to 1.
4. Add date/time columns for classified, draft-created, and decided timestamps.
5. Create the Processing Status choice.
6. Create an alternate key on `External key`.
7. Add both URL columns to the main form.
8. Add a Decisions subgrid to the Processing form.
9. Add the override business rule requiring a comment when the flag is enabled.
10. Add a validation flow or plug-in preventing Ready/Approved status without a final classification after override.
11. Enable auditing for both tables and key override/final-decision columns according to policy.
12. Create security roles separating read, classify, override, and administration permissions.
13. Add views for Unclassified, Multiple matches, Override required, Draft created, and Failed.
14. Export the managed solution for test and production.

---

# 11. Deep-link limitations and operational behavior

- Store Graph-provided `webLink`; do not invent the Outlook URL. The `webLink` opens the message in Outlook on the web and may require sign-in. It cannot be used inside an iframe. citeturn12view156
- The reviewer still needs permission to the shared mailbox.
- Message IDs can change when messages move unless immutable identifiers are requested; sent drafts also undergo a lifecycle transition. citeturn12view156turn12search157turn12search160
- After sending, retain the draft link as historical data but do not assume it still identifies the sent item.
- If a stable link cannot be opened after lifecycle changes, provide a recovery action that searches the scoped mailbox by stored `internetMessageId`, `conversationId`, subject, and timestamps, then refreshes the stored `webLink` after human/operator validation.

---

# 12. Updated processing algorithm

```python
async def process_message(message_id: str) -> dict:
    original = await graph.get_inbox_message(
        message_id,
        select=MESSAGE_SELECT,
        prefer_immutable_id=True,
    )

    processing = await records.upsert_processing(original)
    rules = await classification_repository.list_active()
    result = await classifier.classify(original, rules)
    await records.store_all_decisions(processing.id, result)

    passages = await knowledge.retrieve(original, result)
    proposed_answer = await composer.compose_customer_answer(
        original, result, passages
    )
    complete_body = build_complete_draft_body(
        original,
        result.classifications,
        proposed_answer,
    )

    draft = await graph.create_reply_draft(original["id"])
    draft = await graph.update_draft(
        draft["id"],
        {"body": {"contentType": "HTML", "content": complete_body}},
        select="id,changeKey,webLink,isDraft",
    )

    await records.attach_draft(processing.id, draft)
    return {
        "processingId": processing.id,
        "originalEmailWebLink": original.get("webLink"),
        "draftEmailWebLink": draft.get("webLink"),
        "classifications": result.classifications,
        "draftMessageId": draft["id"],
    }
```

---

# 13. Override and draft-regeneration workflow

```mermaid
flowchart TD
    REVIEW[Reviewer opens Dataverse record] --> FLAG{Override required?}
    FLAG -->|No| ACCEPT[Mark proposed decision final]
    FLAG -->|Yes| COMMENT[Enter mandatory override comment]
    COMMENT --> SELECT[Select/create final classification decision]
    SELECT --> PRESERVE[Keep automated decisions and mark overwritten]
    PRESERVE --> REBUILD[Rebuild routing block from final decisions]
    ACCEPT --> REBUILD
    REBUILD --> UPDATE[Update draft and its changeKey/webLink]
    UPDATE --> INVALIDATE[Invalidate previous approval]
    INVALIDATE --> HUMAN[Review cleaned customer answer]
```

The original email section remains unchanged during routing-block regeneration. Only the marked internal block is replaced.

---

# 14. Acceptance criteria

The update is complete only when:

- the original sender address is the first information line in the removable block;
- the proposed answer appears above the original email;
- the sanitized original email appears below the generated answer;
- the original and draft Graph IDs, change keys, and Graph-provided web links are stored;
- every proposed classification is stored as a separate Decision row;
- the classification reason, provider, score, and model version are stored;
- the override flag is available on the processing row;
- an override comment is mandatory when the flag is set;
- automated decisions are preserved when overwritten;
- final decisions are explicitly marked;
- routing-block regeneration uses final classifications;
- any override invalidates an earlier send approval;
- prepare-send rejects drafts while the removable block remains;
- Dataverse security roles and auditing are configured;
- deep links are tested with users who have shared-mailbox access;
- no URL is manually constructed when Graph supplies `webLink`.

---

# 15. Reference documentation

- [Microsoft Graph message resource and webLink property](https://learn.microsoft.com/en-us/graph/api/resources/message?view=graph-rest-1.0)
- [Microsoft Graph get message](https://learn.microsoft.com/en-us/graph/api/message-get?view=graph-rest-1.0)
- [Microsoft Graph Outlook mail API overview](https://learn.microsoft.com/en-us/graph/api/resources/mail-api-overview?view=graph-rest-1.0)
- [Create and send Outlook messages](https://learn.microsoft.com/en-us/graph/outlook-create-send-messages)
- [Define Dataverse alternate keys](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/define-alternate-keys-reference-records)
- [Use Dataverse alternate keys through the Web API](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/use-alternate-key-reference-record)
- [Work with Dataverse alternate keys programmatically](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/define-alternate-keys-entity)

---

# Appendix B, Optional: Power Apps Classification Administration and Review Workbench

## B.1 Purpose

This optional component provides a model-driven Power App for two separate responsibilities:

1. Maintaining the classification catalog and its example phrases.
2. Reviewing classification results, recording overrides with comments, and requesting creation of a revised response draft.

The Power App is not required for the basic classifier. It is recommended when business owners need governed, audited maintenance and review without editing code.

## B.2 Optional Dataverse tables

Use these four tables:

1. **Classification**: one row per classification.
2. **Classification Example**: one row per example phrase, related to Classification.
3. **Email Classification Processing**: one row per original email processing run.
4. **Email Classification Decision**: one row per proposed or final classification.

Optionally add **Draft Revision** to preserve every regenerated draft reference.

```mermaid
erDiagram
    CLASSIFICATION ||--o{ CLASSIFICATION_EXAMPLE : has
    EMAIL_PROCESSING ||--o{ CLASSIFICATION_DECISION : contains
    CLASSIFICATION ||--o{ CLASSIFICATION_DECISION : references
    EMAIL_PROCESSING ||--o{ DRAFT_REVISION : creates

    CLASSIFICATION {
        guid classificationId PK
        string className
        string modelLabel
        string classTarget
        string classTargetEmail
        integer priority
        boolean isActive
    }
    CLASSIFICATION_EXAMPLE {
        guid exampleId PK
        guid classificationId FK
        string exampleText
        string language
        boolean isActive
    }
    EMAIL_PROCESSING {
        guid processingId PK
        string originalGraphMessageId
        url originalEmailWebLink
        string draftGraphMessageId
        url draftEmailWebLink
        boolean overrideRequired
        text overrideComment
        string processingStatus
    }
    CLASSIFICATION_DECISION {
        guid decisionId PK
        guid processingId FK
        guid classificationId FK
        decimal score
        text classificationReason
        boolean selectedByClassifier
        boolean isFinalClassification
        boolean wasOverwritten
        text overrideComment
    }
    DRAFT_REVISION {
        guid revisionId PK
        guid processingId FK
        integer revisionNumber
        string draftGraphMessageId
        url draftWebLink
        string generationReason
        boolean activeRevision
        datetime generatedOn
    }
```

## B.3 Classification administration app

Create a model-driven Power App named **Email Classification Administration**.

### Screen/view 1: Classification Overview

Show:

- Classification name
- Model label
- Target department
- Target email address
- Priority
- Active status
- Modified on
- Number of active examples, using a rollup or calculated presentation where appropriate

Commands:

- New classification
- Edit classification
- Activate/deactivate classification
- Clone classification, implemented by a Power Automate flow if required

### Screen/form 2: Classification Detail

Main fields:

```text
className
modelLabel
classTarget
classTargetEmail
priority
isActive
```

Add a subgrid for related **Classification Example** rows.

Validation:

- `className`, `modelLabel`, `classTarget`, and `classTargetEmail` are required.
- `modelLabel` must be unique and stable after model training.
- `classTargetEmail` must be in an approved target domain or allow-list.
- Deactivation must not delete historical Classification Decision rows.
- Changing `modelLabel` after BART training requires a controlled label-map/model update.

### Screen/form 3: Classification Example

Fields:

```text
Parent Classification
Example Text
Language
Active
Source/Comment, optional
```

Store each example as a separate child row rather than one multiline field. This supports unlimited examples, multilingual examples, selective deactivation, audit, and clean BART training exports.

### Suggested views

- Active classifications
- Inactive classifications
- Classifications without active examples
- Duplicate or similar model labels
- Examples by language
- Recently modified classifications

## B.4 Classification review workbench

Create a second model-driven app or an additional app area named **Email Classification Review**.

### Processing dashboard

Provide views or charts for:

```text
Received
Classified
Single match
Multiple matches
Unclassified
Override required
Draft created
Draft regenerated
Approved
Sent
Failed
```

### Processing review form

Header:

- Processing status
- Override required
- Owner/reviewer
- Classification provider
- Model version

Original email section:

- Original sender address
- Original subject
- Received date
- Original email deep link
- Original Graph ID and Internet message ID, hidden from normal reviewers if desired

Draft section:

- Current draft deep link
- Current draft revision
- Draft created date
- Draft change key

Classification Decisions subgrid:

- Classification
- Department
- Department email
- Score
- Classification reason
- Provider
- Model version
- Selected by classifier
- Final classification
- Was overwritten
- Override comment

Override section:

- Override required
- Override comment
- Final classification selector or editable decisions subgrid

### Business rules

```mermaid
flowchart TD
    FLAG{Override required = Yes?}
    FLAG -->|No| ACCEPT[Allow acceptance of automated result]
    FLAG -->|Yes| COMMENT{Override comment present?}
    COMMENT -->|No| BLOCK1[Block completion]
    COMMENT -->|Yes| FINAL{At least one final classification selected?}
    FINAL -->|No| BLOCK2[Block completion]
    FINAL -->|Yes| READY[Set status Reclassification approved]
    ACCEPT --> READY2[Set automated decision final]
```

Rules:

1. When `Override required = Yes`, make `Override comment` mandatory.
2. Require at least one final classification before setting the processing row to Reclassification approved.
3. Preserve every automated decision row.
4. Set `wasOverwritten = Yes` on rejected automated decisions.
5. Set `isFinalClassification = Yes` on the reviewed final decisions.
6. Do not permit the reviewer to type an arbitrary department email. It must come from an active Classification record.
7. Enable Dataverse auditing on the override flag, comment, final classification, reviewer, and status fields.

### Optional command buttons

- Open original email
- Open current draft
- Accept proposed classifications
- Mark override required
- Apply reclassification
- Request new draft
- Remove internal routing block

The open commands use the stored Graph-provided `webLink`. The user still requires permission to the shared mailbox.

## B.5 Power Fx examples

Require a comment when override is enabled:

```powerfx
If(
    togOverrideRequired.Value && IsBlank(Trim(txtOverrideComment.Text)),
    Notify("Enter an override comment before saving.", NotificationType.Error),
    SubmitForm(frmProcessing)
)
```

Open the original email:

```powerfx
If(
    !IsBlank(ThisItem.'Original email link'),
    Launch(ThisItem.'Original email link'),
    Notify("No Outlook link is stored for this message.", NotificationType.Warning)
)
```

Request draft regeneration by updating state:

```powerfx
If(
    togOverrideRequired.Value &&
    !IsBlank(Trim(txtOverrideComment.Text)) &&
    CountRows(Filter(galDecisions.AllItems, chkFinal.Value)) > 0,
    Patch(
        'Email Classification Processings',
        ThisItem,
        {
            'Override required': true,
            'Override comment': Trim(txtOverrideComment.Text),
            'Processing status': 'Processing status'.'Reclassification approved',
            'Draft regeneration requested': true
        }
    ),
    Notify(
        "Select a final classification and enter an override comment.",
        NotificationType.Error
    )
)
```

Logical names and choice syntax must be adjusted to the actual generated Dataverse schema.

---

# Appendix C, Optional: Automated Draft Regeneration after Reclassification

## C.1 Design decision

After a reviewer changes the final classification, the solution can either update the existing draft or create a new draft revision.

Recommended default: **create a new reply draft revision and retain the previous draft reference in Dataverse**. This improves auditability and avoids silently replacing a draft that another reviewer may have opened.

```mermaid
flowchart TD
    REVIEW[Reviewer saves final classifications] --> TRIGGER[Dataverse row-change trigger]
    TRIGGER --> VALIDATE[Validate flag, comment, and final decisions]
    VALIDATE --> FETCH[Fetch original email]
    FETCH --> KNOWLEDGE[Retrieve knowledge using final classes]
    KNOWLEDGE --> COMPOSE[Compose revised answer]
    COMPOSE --> BLOCK[Create new routing block]
    BLOCK --> NEWDRAFT[Create new reply draft]
    NEWDRAFT --> REVISION[Create Draft Revision row]
    REVISION --> CURRENT[Update current draft reference]
    CURRENT --> INVALIDATE[Invalidate previous send approval]
```

## C.2 Dataverse trigger

Use a Power Automate cloud flow or equivalent governed workflow.

Trigger:

```text
Microsoft Dataverse: When a row is added, modified or deleted
Change type: Modified
Table: Email Classification Processing
Scope: Organization or the narrowest permitted scope
```

Filter/guard conditions:

```text
Draft regeneration requested = Yes
Override required = Yes
Override comment is not empty
Processing status = Reclassification approved
Regeneration lock is not set
```

Because triggers may be delivered more than once, use a regeneration request ID or row-version/idempotency record.

## C.3 Flow steps

1. Acquire a processing lock or mark `Regeneration in progress`.
2. Load the Email Classification Processing row.
3. Load all related Classification Decision rows where `isFinalClassification = Yes`.
4. Fail safely if there are no final classifications.
5. Load the original email from Graph using the stored mailbox and original message identifier.
6. Refresh the original `webLink` if the stored link is missing and Graph returns one.
7. Retrieve optional knowledge using only final classifications.
8. Compose the revised customer-facing answer.
9. Build the removable routing block from final classifications, with the original sender as the first line.
10. Place the sanitized original email below the revised answer.
11. Create a new reply draft in the configured shared mailbox.
12. Fetch the new draft's ID, change key, and `webLink`.
13. Mark the prior Draft Revision as inactive.
14. Create a new Draft Revision row with reason `Classification override` and the review comment.
15. Update the processing row's current draft ID/link/revision.
16. Clear `Draft regeneration requested` and the processing lock.
17. Set status to `Draft regenerated`.
18. Invalidate any previous prepare-send approval.
19. On failure, set a controlled failure status and retain the original draft references.

## C.4 REST/MCP action used by the flow

Expose a single controlled operation:

```text
POST /v1/processings/{processingId}/regenerate-draft
```

or MCP tool:

```text
regenerate_draft_after_reclassification
```

Input:

```json
{
  "processingId": "dataverse-guid",
  "requestId": "idempotency-guid"
}
```

The service itself loads the final decisions from Dataverse. Do not let the flow or model submit arbitrary classTargetEmail values.

## C.5 Regeneration service skeleton

```python
async def regenerate_draft_after_reclassification(
    processing_id: str,
    request_id: str,
) -> dict:
    if not await idempotency.claim(f"draft-regeneration:{request_id}"):
        return {"status": "duplicate", "requestId": request_id}

    processing = await records.get_processing(processing_id)
    if not processing.overrideRequired:
        raise ValueError("Override required flag is not set")
    if not processing.overrideComment.strip():
        raise ValueError("Override comment is required")

    final_classes = await records.get_final_classifications(processing_id)
    if not final_classes:
        raise ValueError("At least one final classification is required")

    original = await graph.get_inbox_message(processing.originalGraphMessageId)
    passages = await knowledge.retrieve(
        query=f"{original['subject']}\n{original['body']['content']}",
        class_names=[item.className for item in final_classes],
        limit=5,
    )
    answer = await composer.compose_customer_answer(
        original, final_classes, passages
    )
    body = build_complete_draft_body(
        original,
        [item.model_dump(mode="json") for item in final_classes],
        answer,
    )

    draft = await graph.create_reply_draft(original["id"])
    draft = await graph.update_draft(
        draft["id"],
        {"body": {"contentType": "HTML", "content": body}},
    )

    revision = await records.create_draft_revision(
        processing_id=processing_id,
        draft=draft,
        generation_reason="Classification override",
        generation_comment=processing.overrideComment,
    )
    await records.set_current_draft(processing_id, draft, revision)
    await approvals.invalidate_for_processing(processing_id)
    await idempotency.complete(f"draft-regeneration:{request_id}")
    return {
        "status": "draft-regenerated",
        "processingId": processing_id,
        "draftMessageId": draft["id"],
        "draftEmailWebLink": draft.get("webLink"),
        "revisionNumber": revision.revisionNumber,
    }
```

## C.6 Optional update-in-place mode

If the organization explicitly prefers one draft, configure:

```dotenv
DRAFT_REGENERATION_MODE=update-existing
```

Before updating, re-fetch the draft and compare its change key with Dataverse. If another user changed it, stop and require review. Preserve the previous generated content or change metadata in Dataverse for audit.

Recommended default:

```dotenv
DRAFT_REGENERATION_MODE=create-new-revision
```

---

# Appendix D, Optional: Dynamics 365 Customer Service Case Instead of a Draft

## D.1 Purpose

After classification, the solution can create a Dynamics 365 Customer Service case instead of creating a draft. This is appropriate when the incoming message represents work that should be tracked through case ownership, queue routing, status, and service processes.

This is an alternative post-classification action, not a mandatory component.

```dotenv
POST_CLASSIFICATION_ACTION=draft
```

Supported values:

```text
draft
case
draft-and-case
review-required
```

## D.2 Decision tree

```mermaid
flowchart TD
    CLASS[Classification completed] --> OVERRIDE{Override required?}
    OVERRIDE -->|Yes| REVIEW[Wait for final reviewed classification]
    OVERRIDE -->|No| ACTION{Configured or policy-selected action}
    REVIEW --> ACTION
    ACTION -->|draft| DRAFT[Create response draft]
    ACTION -->|case| CASE[Create Customer Service case]
    ACTION -->|draft-and-case| BOTH[Create case and associated response draft]
    ACTION -->|review-required| HUMAN[Human chooses action]
    CASE --> ROUTE[Queue/routing process]
    BOTH --> ROUTE
```

## D.3 Rules

1. When override is required, case creation must wait for final reviewed classifications.
2. Prefer one case with one primary classification and related secondary classifications.
3. Do not create one case per class by default because that can duplicate work and communications.
4. Use an idempotency key based on the processing record to prevent duplicate cases.
5. Store the resulting case ID, case number, link, creation time, and routing result on the processing record or a Case Creation History child row.
6. Preserve every automated and reviewed classification decision.
7. If `draft-and-case` is selected, associate the draft revision with the created case in Dataverse.

## D.4 Data mapping

| Source | Customer Service target |
|---|---|
| Original subject | Case title |
| Original sender/contact resolution | Customer lookup where confidently resolved |
| Original email body | Case description or related email activity |
| Primary final classification | Case category/custom classification lookup |
| Secondary final classifications | Related classification rows or formatted secondary-class field |
| `classTarget` | Queue/routing input |
| `classTargetEmail` | Routing metadata, not automatically a case customer |
| Classification reason | Internal case classification explanation |
| Original email link | Custom URL field on the case or processing record |
| Processing ID | External/idempotency correlation field |

Do not create a new Contact automatically from an arbitrary sender without an approved customer-resolution and duplicate-detection process.

## D.5 Dataverse extensions

Add to Email Classification Processing:

```text
Case created
Case ID
Case number
Case URL
Case created on
Post-classification action
```

Optional child table:

```mermaid
erDiagram
    EMAIL_PROCESSING ||--o{ CASE_CREATION_HISTORY : creates
    CASE_CREATION_HISTORY {
        guid caseHistoryId PK
        guid processingId FK
        guid caseId
        string caseNumber
        url caseUrl
        string primaryClassification
        string targetQueue
        string creationReason
        datetime createdOn
        boolean active
    }
```

## D.6 Case creation service

```python
import hashlib


async def create_customer_service_case(processing_id: str) -> dict:
    processing = await records.get_processing(processing_id)
    final_classes = await records.get_final_classifications(processing_id)
    if processing.overrideRequired and not final_classes:
        raise ValueError("Reviewed final classification is required")
    if not final_classes:
        final_classes = await records.get_accepted_automatic_classifications(processing_id)
    if not final_classes:
        raise ValueError("No accepted classification is available")

    original = await graph.get_inbox_message(processing.originalGraphMessageId)
    primary = sorted(final_classes, key=lambda item: (-item.priority, -item.score))[0]
    idempotency_key = hashlib.sha256(
        f"case|{processing_id}".encode("utf-8")
    ).hexdigest()

    existing = await records.find_case_by_external_key(idempotency_key)
    if existing:
        return {"status": "existing", "caseId": existing.caseId}

    contact = await customer_resolver.resolve_by_email(
        original["sender"]["emailAddress"]["address"]
    )

    payload = {
        "title": original.get("subject") or "Email request",
        "description": original.get("body", {}).get("content", ""),
        "ins_externalprocessingkey": idempotency_key,
        "ins_primaryclassification": primary.className,
        "ins_classificationreason": primary.classificationReason,
        "ins_originalemailweblink": original.get("webLink"),
    }
    if contact:
        payload["customerid_contact@odata.bind"] = f"/contacts({contact.id})"

    case = await dataverse.create("incidents", payload)
    await routing.route_case(
        case_id=case["incidentid"],
        target_department=primary.classTarget,
        target_email=primary.classTargetEmail,
    )
    await records.attach_case(processing_id, case, idempotency_key)
    return {
        "status": "case-created",
        "caseId": case["incidentid"],
        "caseNumber": case.get("ticketnumber"),
    }
```

The exact queue/routing API and field mappings depend on the Customer Service configuration. Implement routing through the organization's approved queue, unified routing, assignment, or flow design rather than inferring a queue from an email address.

## D.7 Power Automate alternative

Trigger:

```text
Dataverse row modified
Processing status = Classified or Reclassification approved
Post-classification action = case or draft-and-case
Case created = No
```

Flow steps:

1. Load the processing row and final classification decisions.
2. Stop if override is required but no final classification exists.
3. Check the external case/idempotency key.
4. Resolve the sender to an existing Account or Contact according to approved rules.
5. Create the Customer Service Case row.
6. Add original email content as description or create/associate an Email activity according to the organization's Customer Service design.
7. Route the case using the configured department-to-queue mapping.
8. Store case ID, case number, URL, creation time, and routing target.
9. If `draft-and-case`, invoke the normal draft-generation operation.
10. Mark `Case created = Yes` only after successful creation and persistence.

## D.8 Harness mapping

### Copilot Studio MCP

```text
create_customer_service_case
```

### Copilot Studio custom connector

```text
CreateCustomerServiceCase
```

### GitHub Copilot executable skill

```bash
shared-mailbox-drafts create-case --processing-id '<guid>'
```

### GitHub Copilot MCP

Use the shared `create_customer_service_case` MCP tool.

Tool descriptions must state that the operation creates a Customer Service case and does not merely draft an email. Restrict case creation to an authorized role and maintain the same idempotency and audit controls as draft creation.

## D.9 Power App additions

Add to the Classification Review form:

- Post-classification action
- Case created
- Case number
- Case link
- Case status
- Target queue
- Created on

Commands:

- Create case
- Open case
- Create draft instead
- Create case and draft

Hide or disable commands when override requirements are incomplete.

---

# Appendix E: Consolidated Optional Acceptance Criteria

The optional Power Apps and Customer Service elements are ready only when:

- business users can create and maintain Classifications and related Example rows;
- model labels remain unique and governed;
- reviewers can open original and draft email links when they have mailbox access;
- all proposed classification rows and reasons are visible;
- override requires a comment and final classification;
- automated results are preserved after override;
- draft regeneration is idempotent and creates an auditable revision by default;
- rebuilt drafts contain the reviewed routing block and original email below the answer;
- old send approvals are invalidated after reclassification;
- the case path waits for reviewed classification when required;
- duplicate case creation is prevented;
- customer resolution does not create arbitrary contacts;
- queue/routing mappings are governed configuration;
- draft, case, both, and review-required actions are explicit;
- Dataverse security roles and auditing cover administrative and review operations;
- all optional components can be disabled without breaking the base classification workflow.

---

# Appendix F: Dataverse as the Single Source of Truth and Additional Implementation Recommendations

## F.1 Architectural principle

Dataverse is the authoritative system of record for configuration, processing state, classifications, human decisions, draft revisions, case references, policy versions, and audit information.

Execution services are stateless or reconstructable wherever practical:

```mermaid
flowchart TB
    DV[(Dataverse Single Source of Truth)]
    DV --> POLICY[Classification and action policies]
    DV --> TAXONOMY[Classification catalog and examples]
    DV --> PROCESS[Email processing state]
    DV --> DECISIONS[Automated and reviewed decisions]
    DV --> REVISIONS[Draft and case revisions]
    DV --> VERSIONS[Prompt, model, table, and knowledge versions]

    MCP[MCP service] --> DV
    API[Custom connector API] --> DV
    EXE[GitHub Copilot skill executable] --> DV
    WORKER[Webhook and queue workers] --> DV

    MCP --> GRAPH[Microsoft Graph]
    API --> GRAPH
    EXE --> GRAPH
    WORKER --> GRAPH
    WORKER --> BART[Foundry BART endpoint]
    WORKER --> KNOWLEDGE[Knowledge retrieval service]
    WORKER --> CASES[Dynamics 365 Customer Service]
```

Rules:

1. Do not use local JSON files as production truth.
2. Do not treat an MCP server cache, Redis, Service Bus, or model endpoint as authoritative business state.
3. Redis may hold locks, short-lived approvals, and idempotency leases, but durable outcomes must be written to Dataverse.
4. Service Bus transports work; it does not own the processing result.
5. Outlook holds mailbox content, while Dataverse holds the governed processing and decision record.
6. The classifier proposes decisions; Dataverse records both proposals and human-reviewed outcomes.
7. Customer Service holds case execution state; Dataverse processing rows retain the correlation and decision history.

## F.2 Recommended state ownership

| Information | Authoritative location |
|---|---|
| Classification names, labels, targets, emails, examples | Dataverse Classification and Classification Example tables |
| Classification thresholds and action policy | Dataverse Classification Policy table |
| Original and draft message references | Dataverse Email Classification Processing and Draft Revision tables |
| Proposed and final classifications | Dataverse Classification Decision table |
| Human override flag, reason, comment, reviewer | Dataverse processing and decision rows |
| Prompt/model/knowledge/table versions | Dataverse Generation Configuration and processing snapshots |
| Short-lived mutex/approval token consumption | Redis or equivalent, with durable outcome copied to Dataverse |
| Queue delivery and dead letters | Azure Service Bus |
| Original email and draft content | Exchange Online, with governed references/snapshots in Dataverse |
| Customer Service case operational state | Dynamics 365 Customer Service, correlated from Dataverse |

---

# F.3 Add a Classification Policy layer

Insert a policy decision after classification and before drafting or case creation:

```mermaid
flowchart LR
    EMAIL[Incoming email] --> CLASSIFIER[Classification provider]
    CLASSIFIER --> POLICY[Dataverse Classification Policy]
    POLICY --> RESULT{Policy outcome}
    RESULT -->|Auto draft permitted| DRAFT[Create draft]
    RESULT -->|Case required| CASE[Create case]
    RESULT -->|Both permitted| BOTH[Create case and draft]
    RESULT -->|Review required| REVIEW[Power App review queue]
```

## F.3.1 Optional Classification Policy table

Suggested table: `Classification Policy`

| Field | Purpose |
|---|---|
| Policy name | Human-readable policy |
| Classification lookup | Optional class-specific policy |
| Minimum confidence | Minimum accepted provider score |
| Medium-confidence threshold | Review-band lower boundary |
| Ambiguity delta | Additional class inclusion tolerance |
| Allow automatic draft | Whether draft creation is allowed |
| Allow automatic case | Whether case creation is allowed |
| Allow draft and case | Whether both are allowed |
| Require review for multiple matches | Multi-label review control |
| Require review for external sender | Optional policy control |
| Post-classification action | Draft, Case, Both, Review |
| Effective from / until | Policy validity |
| Active | Operational switch |
| Policy version | Immutable version identifier |

The service loads the active policy from Dataverse and snapshots the policy ID/version onto every processing record.

```python
async def decide_post_classification_action(processing, result, policy):
    if result.unclassified:
        return "review-required"
    if len(result.classifications) > 1 and policy.requireReviewForMultipleMatches:
        return "review-required"
    best = max(item.score for item in result.classifications)
    if best < policy.mediumConfidenceThreshold:
        return "review-required"
    if policy.postClassificationAction == "case" and policy.allowAutomaticCase:
        return "case"
    if policy.postClassificationAction == "draft-and-case" and policy.allowDraftAndCase:
        return "draft-and-case"
    if policy.allowAutomaticDraft:
        return "draft"
    return "review-required"
```

---

# F.4 Add confidence bands

Avoid one global yes/no threshold as the only business control. Store confidence bands in Dataverse policy:

```text
High: eligible for configured automatic action
Medium: human review required
Low: manual classification required
Below minimum: unclassified
```

The actual numerical boundaries are organization-specific and must be calibrated from evaluation data. Do not hard-code generic values as production truth.

```mermaid
flowchart TD
    SCORE[Classifier score] --> BAND{Dataverse policy band}
    BAND -->|High| ACTION[Configured draft/case action]
    BAND -->|Medium| REVIEW[Human review]
    BAND -->|Low| MANUAL[Manual classification]
    BAND -->|Below minimum| UNCLASS[Unclassified]
```

Store the band and threshold version on the processing record.

---

# F.5 Prompt, model, knowledge, and taxonomy versioning

Add a `Generation Configuration` table or equivalent versioned configuration rows.

Required version fields:

```text
Prompt version
Classifier provider
Model name
Model version
Classification table version
Classification policy version
Knowledge provider
Knowledge index/version
Composer version
Routing block template version
```

Every draft or case operation stores the exact version IDs used. Do not overwrite versioned rows after they have been used. Create a new version and activate it.

```mermaid
erDiagram
    GENERATION_CONFIGURATION ||--o{ EMAIL_PROCESSING : used_by
    GENERATION_CONFIGURATION {
        guid configurationId PK
        string configurationVersion
        string promptVersion
        string provider
        string modelVersion
        string taxonomyVersion
        string policyVersion
        string knowledgeVersion
        string composerVersion
        boolean active
    }
```

---

# F.6 Store the exact classification snapshot

In addition to normalized Decision rows, store the complete provider response as a Dataverse multiline text snapshot:

```json
{
  "provider": "foundry-bart",
  "modelVersion": "email-bart-v3",
  "taxonomyVersion": "27",
  "policyVersion": "finance-routing-5",
  "classifications": [
    {
      "uuid": "...",
      "className": "Invoice question",
      "classTarget": "Finance",
      "classTargetEmail": "finance@instruo365.de",
      "score": 0.91,
      "reason": "..."
    }
  ]
}
```

Suggested field:

```text
Classification result snapshot JSON
```

The snapshot is immutable evidence. Normalized Decision rows remain the queryable business representation.

---

# F.7 Use Azure Service Bus between ingestion and processing

Preferred asynchronous flow:

```mermaid
flowchart LR
    GRAPH[Graph webhook] --> RECEIVER[Webhook receiver]
    RECEIVER --> SB[Azure Service Bus queue]
    SB --> WORKER[Classification worker]
    WORKER --> DV[(Dataverse)]
    WORKER --> DLQ[Dead-letter queue on controlled failure]
    DELTA[Delta reconciliation job] --> SB
```

Implementation recommendations:

1. Webhook receiver validates and acknowledges quickly.
2. Queue message contains only a processing/message reference and correlation ID, not an unnecessary full email body.
3. Use duplicate detection or application idempotency.
4. Use a dead-letter queue for poison messages.
5. Record queue correlation ID and delivery outcome in Dataverse.
6. Make workers safe to retry.
7. Do not retry send operations blindly.
8. Reconcile Graph notifications with scheduled delta processing.

Dataverse remains authoritative even though Service Bus carries work.

---

# F.8 Add a human-review SLA

Add optional fields to Email Classification Processing:

```text
Review required
Review assigned to
Review team
Review started on
Review due on
Review completed on
Review outcome
Escalation level
```

Suggested review calculation flow:

```mermaid
flowchart TD
    REQUIRED[Review required] --> ASSIGN[Assign user/team]
    ASSIGN --> DUE[Set due time from Dataverse SLA policy]
    DUE --> OPEN{Completed?}
    OPEN -->|No and due approaching| REMIND[Notify reviewer]
    OPEN -->|No and overdue| ESCALATE[Escalate]
    OPEN -->|Yes| METRIC[Record completion duration and outcome]
```

Use a Dataverse SLA/policy record rather than a hard-coded duration where practical.

---

# F.9 Keep knowledge retrieval separate from classification

```mermaid
flowchart LR
    EMAIL[Email] --> CLASS[Classification service]
    TAXONOMY[(Dataverse taxonomy)] --> CLASS
    CLASS --> LABELS[Classifications]
    EMAIL --> QUERY[Knowledge query builder]
    LABELS --> QUERY
    QUERY --> KNOWLEDGE[Knowledge provider]
    KNOWLEDGE --> PASSAGES[Grounded passages]
    PASSAGES --> COMPOSER[Response composer]
```

Rules:

- Classification examples are training/routing data, not answer knowledge.
- Knowledge sources must return source metadata.
- The response composer uses only retrieved passages for factual answers.
- Store source IDs and retrieval version on the processing/draft revision record.
- A classification can succeed while knowledge retrieval fails; in that case create a review/acknowledgement draft rather than unsupported content.

---

# F.10 Add attachment processing as a separate optional pipeline

```mermaid
flowchart TD
    EMAIL[Email] --> BODY[Sanitized body text]
    EMAIL --> ATTACH{Attachments present?}
    ATTACH -->|No| CLASS[Classification]
    ATTACH -->|Yes| SCAN[Malware scanning]
    SCAN --> SAFE{Safe and supported?}
    SAFE -->|No| REVIEW[Human review]
    SAFE -->|Yes| EXTRACT[Supported text extraction]
    EXTRACT --> COMBINE[Combine bounded body and extracted signals]
    BODY --> COMBINE
    COMBINE --> CLASS
```

Requirements:

1. Do not open or execute attachments in the classifier worker.
2. Scan before extraction.
3. Allow-list MIME types and extensions.
4. Bound file size, page count, extracted text, and processing time.
5. Store attachment metadata and extraction status in Dataverse.
6. Store extracted content only when policy allows it.
7. Keep the extraction provider and version auditable.
8. Route unsupported or unsafe attachments to human review.

---

# F.11 Track classifier drift and correction feedback

Dataverse contains the necessary source rows for evaluation:

```text
Automated decisions
Scores
Final reviewed decisions
Override flags/comments
Provider/model versions
Taxonomy/policy versions
```

Create scheduled analytics that calculate:

- automatic acceptance rate;
- override rate;
- unclassified rate;
- multi-match rate;
- per-class precision/recall where reviewed labels exist;
- wrong-target rate;
- human correction rate;
- classification volume by class and language;
- latency and failure rate by provider/version.

```mermaid
flowchart LR
    DV[(Dataverse decisions)] --> METRICS[Evaluation job]
    METRICS --> REPORT[Power BI / model-driven dashboard]
    METRICS --> DRIFT{Approved threshold exceeded?}
    DRIFT -->|No| CONTINUE[Continue monitoring]
    DRIFT -->|Yes| REVIEW[Model/taxonomy review]
    REVIEW --> RETRAIN[Controlled retraining candidate]
    RETRAIN --> EVAL[Offline evaluation]
    EVAL --> APPROVE{Human approval}
    APPROVE -->|Yes| NEWVER[Activate new version]
    APPROVE -->|No| KEEP[Keep current model]
```

Never train directly from overrides without review, data-quality checks, privacy review, and a versioned training release.

---

# F.12 Future service and agent boundaries

Keep the initial implementation in one repository if that simplifies delivery, but separate domain modules:

```text
classification_service.py
classification_policy_service.py
knowledge_service.py
draft_service.py
case_service.py
review_service.py
attachment_service.py
audit_service.py
```

Potential future agent/tool boundaries:

```mermaid
flowchart LR
    ORCH[Orchestrator] --> CLASS[Classification capability]
    ORCH --> KNOW[Knowledge capability]
    ORCH --> RESP[Response drafting capability]
    ORCH --> CASE[Case capability]
    ORCH --> REVIEW[Review capability]
    CLASS --> DV[(Dataverse)]
    KNOW --> DV
    RESP --> DV
    CASE --> DV
    REVIEW --> DV
```

Do not split into multiple agents solely for code organization. Split when ownership, security boundary, lifecycle, scaling, or reuse justifies it. Dataverse remains the common source of truth.

---

# F.13 Additional Dataverse tables and fields

## Optional tables

```text
Classification Policy
Generation Configuration
Knowledge Retrieval Evidence
Attachment Processing
Review SLA Policy
Processing Event / Audit Correlation
```

## Optional fields on Email Classification Processing

```text
Classification snapshot JSON
Classification confidence band
Classification policy lookup/version
Generation configuration lookup/version
Review required
Review assigned to/team
Review started/due/completed timestamps
Knowledge retrieval status
Attachment processing status
Queue correlation ID
Current processing attempt
Last controlled error code
```

## Optional fields on Draft Revision

```text
Prompt version
Composer version
Knowledge version
Knowledge source IDs
Routing block template version
Classification snapshot hash
Generated body hash
```

---

# F.14 Dataverse write discipline

1. Use alternate keys or deterministic external keys for idempotent integration.
2. Use optimistic concurrency where supported for reviewer and worker updates.
3. Do not overwrite immutable snapshots.
4. Use status transitions rather than loosely coordinated booleans alone.
5. Validate transitions server-side, not only in Power Apps.
6. Keep human-review writes distinguishable from automation writes.
7. Enable auditing for policy, taxonomy, override, final decision, action, and version fields.
8. Store correlation IDs for Graph, model endpoint, queue, custom connector/MCP, and case actions.
9. Avoid storing complete email bodies in Dataverse unless retention and privacy policy explicitly require it; use scoped Graph references and hashes where sufficient.

---

# F.15 Revised implementation sequence

1. Finalize the Dataverse data model and status-transition model.
2. Create Classification, Classification Example, Policy, Processing, Decision, Draft Revision, and Generation Configuration tables.
3. Configure security roles, auditing, alternate keys, and business rules.
4. Build the Power Apps administration and review experiences.
5. Implement Graph ingestion and Service Bus queueing.
6. Implement idempotent workers that create/update Dataverse processing state.
7. Implement provider-neutral classification and policy evaluation.
8. Implement separate knowledge retrieval and response composing.
9. Add removable routing block and original-email section.
10. Add draft, case, both, and review-required post-classification actions.
11. Add human-review SLA and escalation.
12. Add optional attachment scan/extraction pipeline.
13. Add evaluation and drift reporting from reviewed Dataverse data.
14. Integrate MCP, custom connector, and executable adapters over the same domain services.
15. Test recovery from queue duplication, worker failure, Graph throttling, model failure, Dataverse concurrency, and uncertain send outcomes.
16. Publish versioned configurations only after evaluation and human approval.

---

# F.16 Revised acceptance criteria

The complete architecture is ready only when:

- Dataverse is the authoritative source for taxonomy, policy, processing state, decisions, overrides, revisions, versions, and correlations;
- all execution paths use the same Dataverse records and status model;
- classification policy is data-driven and versioned;
- confidence bands and thresholds are configurable and auditable;
- exact provider output is preserved as an immutable snapshot;
- Service Bus decouples ingestion from processing and supports dead-letter handling;
- human reviews have assignment, due date, completion, and escalation data;
- classification and knowledge retrieval remain separate capabilities;
- attachments are isolated behind scanning and bounded extraction;
- model drift and human corrections are reportable by model/taxonomy version;
- retraining data is reviewed and released through a controlled process;
- service boundaries are modular even if initially deployed together;
- Redis, queues, models, and adapters are not treated as the business source of truth;
- every final draft or case can be reconstructed from Dataverse decisions, versions, evidence references, and mailbox/case identifiers.
