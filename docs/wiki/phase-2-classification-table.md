# Phase 2: Classification via Dataverse Table

**Objective:** Store classification rules and audit results in Dataverse, and classify shared-mailbox messages using a Copilot Studio Prompt tool (with a future option to swap in a hosted model via Azure AI Foundry).

**Harness:** Copilot Studio custom connector + Dataverse (no code deployment required for the tables themselves).

---

## 1. Classification Rule Table Schema

Dataverse table storing the routing rules a message can be classified against. Defined as a reusable template in [`dataverse/schemas/classification-rule.schema.json`](../../dataverse/schemas/classification-rule.schema.json) and deployed with [`dataverse/scripts/deploy-dataverse-tables.ps1`](../../dataverse/scripts/deploy-dataverse-tables.ps1) - see Section 5.

| Column (logical name, `<prefix>_` omitted) | Display Name | Type | Required | Purpose |
|---|---|---|---|---|
| `classificationruleid` | Classification Rule | GUID (PK, auto) | Yes | Unique identifier |
| `classname` | Class Name | Text (primary column) | Yes | Human-readable classification (e.g., "Invoice Question") |
| `classexamples` | Class Examples | Multiline Text | Yes | Sample phrases/keywords, one per line - used as prompt context |
| `classtarget` | Target Department | Text | Yes | Responsible department name |
| `classtargetemail` | Target Email | Email | Yes | Routing email address |
| `isactive` | Active | Yes/No | Yes | Enable/disable this rule without deleting it |
| `priority` | Priority | Integer | No | Tie-breaker (higher wins) |
| `modellabel` | Model Label | Text | No | Stable label, e.g. `invoice_question` (for future Foundry/BART model mapping) |

`createdon`/`modifiedon` are standard Dataverse columns and track the audit timestamp automatically - no custom "last updated" column is needed.

### 1.1 Sample Classifications

Seeded by [`dataverse/scripts/seed-sample-classifications.ps1`](../../dataverse/scripts/seed-sample-classifications.ps1):

```json
[
  {
    "className": "Invoice Question",
    "classExamples": "invoice\nbilling\namount\nreceipt",
    "classTarget": "Finance Department",
    "classTargetEmail": "finance@company.com",
    "isActive": true,
    "priority": 100,
    "modelLabel": "invoice_question"
  },
  {
    "className": "Technical Support",
    "classExamples": "cannot sign in\nerror\nAADSTS\naccess denied",
    "classTarget": "IT Support",
    "classTargetEmail": "itsupport@company.com",
    "isActive": true,
    "priority": 95,
    "modelLabel": "technical_support"
  }
]
```

---

## 2. Classification Audit Table Schema

Dataverse table storing every classification result, for compliance and troubleshooting. Defined in [`dataverse/schemas/classification-audit.schema.json`](../../dataverse/schemas/classification-audit.schema.json).

| Column (logical name, `<prefix>_` omitted) | Display Name | Type | Required | Purpose |
|---|---|---|---|---|
| `classificationauditid` | Classification Audit | GUID (PK, auto) | Yes | Audit record ID |
| `messageid` | Message Id | Text (primary column) | Yes | Microsoft Graph message ID that was classified |
| `classificationresult` | Classification Result (JSON) | Multiline Text | Yes | Full classification response (classifications array, scores, reasons) |
| `provider` | Provider | Text | Yes | Classifier used, e.g. `copilot-prompt`, `bart-foundry` |
| `modelversion` | Model Version | Text | No | Classifier/model version identifier |
| `confidence` | Confidence | Decimal (0-1) | No | Top classification confidence score |
| `needshumanreview` | Needs Human Review | Yes/No | No | True when ambiguous/low-confidence and a human should confirm routing |
| `classificationruleid` | Matched Rule | Lookup -> Classification Rule | No | Optional link to the rule that matched |

---

## 3. Classification Engine

**Decision:** classification runs inside Copilot Studio using a **Prompt tool** (Generative AI prompt action) rather than a separate backend classifier service:

1. A Topic (or the agent's own orchestration, no Flow required) fetches the active rows from the Classification Rule table via the built-in Dataverse connector.
2. The Prompt tool receives the message text plus the fetched class list (name + examples) as grounding context, and returns a structured classification (JSON output schema: `classifications[]`, `needsHumanRoutingDecision`, `confidence`).
3. The result is written to the Classification Audit table via the Dataverse connector (or the `ClassifyMessage`/audit-write connector operation, once added - Section 4).

This can optionally be wrapped in a Power Automate flow instead of a Topic if a scheduled/triggered (rather than conversational) classification path is needed - the Dataverse tables and Prompt tool step are the same either way.

**Planned/future swap-in:** replace the built-in Studio model with a model hosted on **Azure AI Foundry** (e.g. `facebook/bart-large-mnli` for zero-shot classification, deployed as a managed real-time endpoint) called from the Prompt tool via a custom connector or Flow action. The Dataverse schema and audit trail above do not change - only the `provider`/`modellabel` values and the backing model call. This swap is **not implemented yet** and is tracked as a Phase 2 follow-up.

---

## 4. Copilot Studio Integration (Planned)

Once the Prompt tool flow above is built, add a `ClassifyMessage` custom connector operation (or reuse the existing backend if a server-side implementation is preferred) so classification can also be invoked outside the Prompt tool - the response shape is shared:

```json
{
  "classifications": [
    {
      "className": "Invoice Question",
      "classTarget": "Finance Department",
      "classTargetEmail": "finance@company.com",
      "score": 0.87,
      "reason": "Matches invoice/billing keywords"
    }
  ],
  "needsHumanRoutingDecision": false,
  "confidence": 0.87,
  "provider": "copilot-prompt",
  "modelVersion": "0.5.0"
}
```

---

## 5. Setup Instructions

### 5.1 Prerequisites

The Azure AD app registration used by `backend-service`/`custom-connector` (see `docs/wiki/phase-1-mailbox-setup.md`, Section 3) must be added as an **Application User** in the target Dataverse environment, with a security role granting Customization permissions (e.g. **System Customizer**):

1. [Power Platform Admin Center](https://admin.powerplatform.com) -> your environment -> **Settings** -> **Users + permissions** -> **Application users** -> **+ New app user**
2. Select the app registration, assign the **System Customizer** role, and save.

Add to `.env` in the repo root:

```
DATAVERSE_ENVIRONMENT_URL=https://org.crm.dynamics.com
DATAVERSE_PUBLISHER_PREFIX=b365
```

### 5.2 Deploy the Tables

```powershell
.\dataverse\scripts\deploy-dataverse-tables.ps1
```

Idempotent - creates the Classification Rule and Classification Audit tables (and the lookup relationship between them) if missing, and skips anything that already exists. Reads `DATAVERSE_ENVIRONMENT_URL`/`TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET`/`DATAVERSE_PUBLISHER_PREFIX` from `.env`, or pass them as parameters.

### 5.3 Seed Sample Classifications

```powershell
.\dataverse\scripts\seed-sample-classifications.ps1
```

Upserts the built-in sample rules (or pass `-ClassificationsJson` with your own).

---

## 6. Testing

### Test the Deployment Scripts

1. Run `deploy-dataverse-tables.ps1` - verify it prints both table logical names and collection (entity set) names with no errors.
2. Re-run it a second time - verify it reports every table/column/relationship as "already exists - skipping" (idempotency check).
3. Run `seed-sample-classifications.ps1` - verify the sample rows appear in the Classification Rule table (Power Apps maker portal -> Tables -> Classification Rule -> Data).

### Test the Prompt Tool (once built in Copilot Studio)

1. Open the topic/tool that fetches rules and calls the Prompt tool.
2. Send a test message body matching one of the seeded rules (e.g. "I have a question about my invoice").
3. Verify the returned classification matches the expected rule, and a row is written to the Classification Audit table.

---

## 7. Troubleshooting

| Issue | Resolution |
|---|---|
| **401/403 from `deploy-dataverse-tables.ps1`** | The app registration is not registered as an Application User in the Dataverse environment, or lacks a Customization-capable security role (Section 5.1) |
| **`EntityDefinitions` create fails with a name-conflict error** | The publisher prefix + logical name is already in use by another solution/table - choose a different `DATAVERSE_PUBLISHER_PREFIX` |
| **No classifications returned by the Prompt tool** | Verify the Classification Rule table has active (`isactive = true`) rows and the Prompt tool's grounding context includes them |
| **Wrong department routed** | Review rule priorities and example phrases in the Classification Rule table |
| **Audit table not updated** | Check the Dataverse connector's connection in Copilot Studio and confirm write permissions on the Classification Audit table |

---

## 8. Next Steps

- Build the Copilot Studio Prompt tool + Topic (Section 3)
- Evaluate swapping in a Foundry-hosted BART-MNLI (or similar) model once the Prompt tool baseline is working
- Proceed to Phase 3: Draft Creation with routing-block generation

---

## References

- [Dataverse table schema](https://learn.microsoft.com/power-apps/maker/data-platform/entity-overview)
- [Dataverse Web API: create table (EntityMetadata)](https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-definitions-using-web-api)
- [Copilot Studio Prompt tool (Generative AI)](https://learn.microsoft.com/microsoft-copilot-studio/advanced-generative-actions)
- [Azure AI Foundry model catalog](https://learn.microsoft.com/azure/ai-foundry/how-to/model-catalog-overview)

---

**Copyright & License**

(c) 2026 Holger Imbery (contact@holgerimbery.blog)

Licensed under the project LICENSE file.