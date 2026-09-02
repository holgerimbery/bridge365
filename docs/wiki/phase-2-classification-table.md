# Phase 2: Classification via Table

**Objective:** Integrate classification table, implement rule-based classifier, and route messages.

**Harnesses:** Copilot Studio standard harness (primary) + GitHub Copilot skill (parallel).

---

## 1. Classification Table Schema

Create a Dataverse table to store classification rules:

| Column Name | Display Name | Type | Required | Purpose |
|---|---|---|---|---|
| `ins_classificationid` | Classification | GUID (PK) | Yes | Unique identifier |
| `ins_classname` | Class Name | Text | Yes | Human-readable classification (e.g., "Invoice Question") |
| `ins_classexamples` | Class Examples | Multiline Text | Yes | Sample phrases (keyword triggers) |
| `ins_classtarget` | Department/Target | Text | Yes | Responsible department name |
| `ins_classtargetemail` | Department Email | Email | Yes | Routing email address |
| `ins_isactive` | Active | Yes/No | Yes | Enable/disable this classification |
| `ins_priority` | Priority | Integer | No | Tie-breaker (higher wins) |
| `ins_modellabel` | Model Label | Text | No | Stable ML model label (e.g., "invoice_question") |
| `ins_updatedate` | Last Updated | Date & Time | No | Audit and cache invalidation |

### 1.1 Sample Classifications

```json
[
  {
    "classificationId": "uuid-1",
    "className": "Invoice Question",
    "classExamples": [
      "I have a question about invoice",
      "The amount on the invoice is incorrect",
      "Please send a copy of the invoice"
    ],
    "classTarget": "Finance Department",
    "classTargetEmail": "finance@company.com",
    "isActive": true,
    "priority": 100,
    "modelLabel": "invoice_question"
  },
  {
    "classificationId": "uuid-2",
    "className": "Technical Support",
    "classExamples": [
      "I cannot sign in",
      "Cannot access",
      "Error: AADSTS"
    ],
    "classTarget": "IT Support",
    "classTargetEmail": "itsupport@company.com",
    "isActive": true,
    "priority": 90,
    "modelLabel": "technical_support"
  }
]
```

---

## 2. Rule-Based Classifier

Implement a deterministic classifier that matches email keywords against the classification table:

```python
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.

class RuleBasedClassifier:
    def __init__(self, min_score: float = 0.5, ambiguity_delta: float = 0.1):
        self.min_score = min_score
        self.ambiguity_delta = ambiguity_delta
    
    async def classify(self, subject: str, body: str, rules: list) -> dict:
        """Classify email by matching keywords from active rules."""
        text = f"{subject}\n{body}".lower()
        matches = []
        
        for rule in rules:
            if not rule['isActive']:
                continue
            
            examples = [ex.lower() for ex in rule['classExamples']]
            score = sum(1 for ex in examples if ex in text) / len(examples)
            
            if score > 0:
                matches.append({
                    'className': rule['className'],
                    'classTarget': rule['classTarget'],
                    'classTargetEmail': rule['classTargetEmail'],
                    'score': score,
                    'reason': f'Matched {sum(1 for ex in examples if ex in text)}/{len(examples)} example phrases'
                })
        
        # Sort by score descending
        matches.sort(key=lambda x: (x['score'], -rule.get('priority', 0)), reverse=True)
        
        return {
            'classifications': matches,
            'needsHumanRoutingDecision': len(matches) != 1,
            'unclassified': len(matches) == 0,
            'provider': 'rules',
            'modelVersion': '0.2.0'
        }
```

---

## 3. Classification Audit Table

Store classification results for every message:

| Column | Type | Purpose |
|---|---|---|
| `ins_auditid` | GUID | Audit record ID |
| `ins_messageid` | Text | Microsoft Graph message ID |
| `ins_classifications` | JSON | Array of classification results |
| `ins_provider` | Text | Classifier used (rules, BART, structured-model) |
| `ins_modelversion` | Text | Classifier version |
| `ins_createdon` | DateTime | Timestamp |

---

## 4. Copilot Studio Integration

### Skill Action: `ClassifyMessage`

**Input:**
- messageId (text)

**Output:**
```json
{
  "classifications": [
    {
      "className": "Invoice Question",
      "classTarget": "Finance",
      "classTargetEmail": "finance@company.com",
      "score": 0.87,
      "reason": "Matched 2/3 example phrases"
    }
  ],
  "needsHumanRoutingDecision": false,
  "unclassified": false,
  "provider": "rules",
  "modelVersion": "0.2.0"
}
```

### Connector Operation: `ClassifyMessage`

OpenAPI endpoint:
```yaml
/mailbox/classify:
  post:
    operationId: ClassifyMessage
    requestBody:
      required: true
      content:
        application/json:
          schema:
            type: object
            properties:
              messageId:
                type: string
    responses:
      '200':
        description: Classification result
        content:
          application/json:
            schema:
              type: object
              properties:
                classifications:
                  type: array
                needsHumanRoutingDecision:
                  type: boolean
                unclassified:
                  type: boolean
                provider:
                  type: string
                modelVersion:
                  type: string
```

---

## 5. GitHub Copilot Skill

CLI command:
```bash
shared-mailbox-drafts classify-message --mailbox "service@company.com" --message-id "<id>"
```

Returns the same JSON structure as Copilot Studio.

---

## 6. Setup Instructions

### 6.1 Create Classification Table

Run the provided PowerShell script:

```powershell
.\docs\wiki\scripts\setup-classification-table.ps1 `
  -EnvironmentUrl "https://org.crm.dynamics.com" `
  -PublisherPrefix "ins"
```

### 6.2 Populate Sample Classifications

```powershell
.\docs\wiki\scripts\create-sample-classifications.ps1 `
  -EnvironmentUrl "https://org.crm.dynamics.com" `
  -ClassificationsJson @"
[
  {
    "className": "Invoice Question",
    "classExamples": ["invoice", "amount", "receipt"],
    "classTarget": "Finance",
    "classTargetEmail": "finance@company.com"
  }
]
"@
```

---

## 7. Testing

### Test Rule-Based Classifier

```python
classifier = RuleBasedClassifier()
result = await classifier.classify(
    subject="Question about invoice 4711",
    body="The amount seems incorrect.",
    rules=[...]
)
assert result['unclassified'] == False
assert len(result['classifications']) > 0
```

### Test Copilot Studio Skill

1. Call `ClassifyMessage` with a test messageId
2. Verify classifications are returned
3. Check that Dataverse audit record is created

### Test GitHub Copilot Skill

```bash
shared-mailbox-drafts classify-message --mailbox "service@company.com" --message-id "test-id"
```

---

## 8. Troubleshooting

| Issue | Resolution |
|---|---|
| **No classifications returned** | Verify rule examples match email content; check case sensitivity |
| **Wrong department routed** | Review classification table priorities; adjust keyword examples |
| **Audit table not updated** | Check Dataverse connection; verify table permissions |

---

## 9. Next Steps

- Proceed to Phase 3: Draft Creation
- Implement routing block generation
- Integrate knowledge retrieval

---

## References

- [Dataverse table schema](https://learn.microsoft.com/power-apps/maker/data-platform/entity-overview)
- [Custom connector OpenAPI](https://learn.microsoft.com/connectors/custom-connectors/)
- [Rule-based NLP classification](https://en.wikipedia.org/wiki/Rule-based_machine_learning)

---

**Copyright & License**

(c) 2026 Holger Imbery (contact@holgerimbery.blog)

Licensed under the project LICENSE file.
