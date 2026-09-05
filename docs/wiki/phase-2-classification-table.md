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
3. The result is written to the Classification Audit table via the built-in Dataverse connector.

This can optionally be wrapped in a Power Automate flow instead of a Topic if a scheduled/triggered (rather than conversational) classification path is needed - the Dataverse tables and Prompt tool step are the same either way.

**Planned/future swap-in:** replace the built-in Studio model with a model hosted on **Azure AI Foundry** (e.g. `facebook/bart-large-mnli` for zero-shot classification, deployed as a managed real-time endpoint) called from the Prompt tool via a custom connector or Flow action. The Dataverse schema and audit trail above do not change - only the `provider`/`modellabel` values and the backing model call. This swap is **not implemented yet** and is tracked as a Phase 2 follow-up.

---

## 4. Prompt Tool Examples

Two Copilot Studio **Prompt tools** (Generative AI actions) implement the flow end to end. Both are configured the same way: create a Prompt tool, paste the **Instructions** text below, define the **Input** variables, and set the **Output** to structured JSON (or plain text for the HTML tool) matching the schema shown.

### 4.1 Example: `ClassifyMessage` Prompt Tool

**Inputs:**

| Name | Type | Source |
|---|---|---|
| `EmailSubject` | String | The message being classified |
| `EmailBody` | String | The message being classified |
| `ClassificationRules` | String (JSON array) | Active rows from the Classification Rule table (`classname`, `classexamples`, `classtarget`, `classtargetemail`), fetched via the Dataverse connector "List rows" action, filtered to `isactive eq true` |

**Instructions (paste into the Prompt tool):**

```text
You are a message-routing classifier for a shared mailbox. You are given an
email (Subject, Body) and a list of candidate classification rules, each
with a class name, example phrases, a target department, and a target email.

Compare the email against every rule's example phrases and decide which
rule(s) plausibly apply - there can be zero, one, or several matches.

Respond with ONLY a JSON object in this exact shape, no other text:

{
  "classifications": [
    { "className": "<rule className>", "classTarget": "<rule classTarget>",
      "classTargetEmail": "<rule classTargetEmail>", "score": <0.0-1.0>,
      "reason": "<short reason this rule matched>" }
  ],
  "needsHumanRoutingDecision": <true if zero or more than one match, else false>,
  "confidence": <the highest score above, or 0 if no matches>
}

Email Subject: {{EmailSubject}}
Email Body: {{EmailBody}}
Classification Rules: {{ClassificationRules}}
```

**Example input/output:**

```json
// Input
{
  "EmailSubject": "Question about invoice 4711",
  "EmailBody": "Hi, the amount on invoice 4711 looks wrong. Can you check?",
  "ClassificationRules": "[{\"className\":\"Invoice Question\",\"classExamples\":\"invoice\\nbilling\\namount\\nreceipt\",\"classTarget\":\"Finance Department\",\"classTargetEmail\":\"finance@company.com\"},{\"className\":\"Technical Support\",\"classExamples\":\"cannot sign in\\nerror\\nAADSTS\\naccess denied\",\"classTarget\":\"IT Support\",\"classTargetEmail\":\"itsupport@company.com\"}]"
}

// Output
{
  "classifications": [
    { "className": "Invoice Question", "classTarget": "Finance Department",
      "classTargetEmail": "finance@company.com", "score": 0.92,
      "reason": "Mentions an invoice number and a disputed amount" }
  ],
  "needsHumanRoutingDecision": false,
  "confidence": 0.92
}
```

The calling Topic writes this result (plus `provider: "copilot-prompt"` and a `modelVersion`) to the Classification Audit table via the Dataverse connector.

### 4.2 Example: `DraftEmailBody` Prompt Tool

Generates the full HTML body for the reply draft, combining the classification result, a proposed response, and the original message - so a human reviewer sees everything in one place before sending.

**Inputs:**

| Name | Type | Source |
|---|---|---|
| `OriginalFrom` | String | Original message sender |
| `OriginalTo` | String | Original message recipient (the shared mailbox) |
| `OriginalSubject` | String | Original message subject |
| `OriginalBody` | String | Original message body |
| `Classifications` | String (JSON array) | Output of the `ClassifyMessage` Prompt tool (Section 4.1) - may contain zero, one, or several entries |

**Instructions (paste into the Prompt tool):**

```text
You draft the HTML body for a shared-mailbox reply email. You are given the
original message (From, To, Subject, Body) and its classification result(s).

Produce ONE complete HTML document (inline styles only, no external CSS/JS,
no markdown, no commentary outside the HTML) containing exactly these three
sections, in this order:

1. INTERNAL ROUTING BLOCK - wrap it in these exact HTML comment markers:
   <!-- ROUTING-BLOCK:START - please remove before sending -->
   ... and ...
   <!-- ROUTING-BLOCK:END -->
   Inside, render a table listing EVERY entry from Classifications: its
   class name, target department, and target department email. If
   Classifications is empty, state "No classification matched - manual
   routing required" instead of a table.

2. DRAFTED RESPONSE - wrap it in these exact HTML comment markers:
   <!-- DRAFT-RESPONSE:START - please modify/redact before sending -->
   ... and ...
   <!-- DRAFT-RESPONSE:END -->
   Write a professional, concise reply that addresses the sender's request,
   IN THE SAME LANGUAGE as OriginalBody (detect the language yourself; do
   not translate it). Do not invent facts that are not present in the
   original message. Sign off generically (no personal name).

3. ORIGINAL MESSAGE - quote it for reference in a plain HTML blockquote,
   showing From, To, Subject, and Body exactly as given. No removal marker
   needed here - this section is reference context, not a draft artifact.

Original From: {{OriginalFrom}}
Original To: {{OriginalTo}}
Original Subject: {{OriginalSubject}}
Original Body: {{OriginalBody}}
Classifications: {{Classifications}}
```

**Example output** (English original; a German original would produce a German drafted response in section 2, unchanged sections 1 and 3 structure):

```html
<!-- ROUTING-BLOCK:START - please remove before sending -->
<table style="border-collapse:collapse;font-family:sans-serif;font-size:13px;">
  <tr style="background:#f2f2f2;">
    <th style="border:1px solid #ccc;padding:4px 8px;">Class Name</th>
    <th style="border:1px solid #ccc;padding:4px 8px;">Target Department</th>
    <th style="border:1px solid #ccc;padding:4px 8px;">Target Email</th>
  </tr>
  <tr>
    <td style="border:1px solid #ccc;padding:4px 8px;">Invoice Question</td>
    <td style="border:1px solid #ccc;padding:4px 8px;">Finance Department</td>
    <td style="border:1px solid #ccc;padding:4px 8px;">finance@company.com</td>
  </tr>
</table>
<!-- ROUTING-BLOCK:END -->

<!-- DRAFT-RESPONSE:START - please modify/redact before sending -->
<p>Hello,</p>
<p>Thank you for reaching out about invoice 4711. We are reviewing the amount
you flagged and will confirm the correct total shortly. If you have the
original purchase order to hand, please share it so we can cross-check
faster.</p>
<p>Kind regards,<br/>Finance Department</p>
<!-- DRAFT-RESPONSE:END -->

<hr/>
<p style="color:#666;font-size:12px;"><strong>Original Message</strong></p>
<p style="color:#666;font-size:12px;">
  From: sender@external.com<br/>
  To: shared@company.com<br/>
  Subject: Question about invoice 4711
</p>
<blockquote style="color:#666;font-size:12px;border-left:2px solid #ccc;padding-left:8px;">
  Hi, the amount on invoice 4711 looks wrong. Can you check?
</blockquote>
```

Pass the resulting HTML string as the `body` (with `contentType: "html"`) to the existing `CreateDraft` connector operation (`docs/wiki/phase-1-mailbox-setup.md`, Section 5) to create the reviewable draft reply.

---

## 5. Connector Requirements by Classification Path

The two classification paths described above have different connector needs:

- **Current/default path (Prompt tool, Section 4.1):** requires no custom connector operation. The Topic (or Flow) reads the Classification Rule table and writes the Classification Audit table using the built-in Dataverse connector only, and the Prompt tool itself runs natively inside Copilot Studio - everything happens in-platform, with no server-side call to build or maintain.
- **Future Foundry-hosted path (Section 3, "Planned/future swap-in"):** if/when the built-in Studio model is swapped for a model hosted on Azure AI Foundry, a `ClassifyMessage` custom connector operation becomes necessary so the Prompt tool/Topic can invoke that server-side model call. The response shape returned by that connector operation matches the Prompt tool's JSON output today, so the Dataverse schema and audit trail do not change - only the `provider`/`modelVersion` values and the backing model call:

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

## 6. Setup Instructions

### 6.1 Prerequisites

The Azure AD app registration used by `backend-service`/`custom-connector` (see `docs/wiki/phase-1-mailbox-setup.md`, Section 3) must be added as an **Application User** in the target Dataverse environment, with a security role granting Customization permissions (e.g. **System Customizer**):

1. [Power Platform Admin Center](https://admin.powerplatform.com) -> your environment -> **Settings** -> **Users + permissions** -> **Application users** -> **+ New app user**
2. Select the app registration, assign the **System Customizer** role, and save.

Add to `.env` in the repo root:

```
DATAVERSE_ENVIRONMENT_URL=https://org.crm.dynamics.com
DATAVERSE_PUBLISHER_PREFIX=b365
```

### 6.2 Deploy the Tables

```powershell
.\dataverse\scripts\deploy-dataverse-tables.ps1
```

Idempotent - creates the Classification Rule and Classification Audit tables (and the lookup relationship between them) if missing, and skips anything that already exists. Reads `DATAVERSE_ENVIRONMENT_URL`/`TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET`/`DATAVERSE_PUBLISHER_PREFIX` from `.env`, or pass them as parameters.

### 6.3 Seed Sample Classifications

```powershell
.\dataverse\scripts\seed-sample-classifications.ps1
```

Upserts the built-in sample rules (or pass `-ClassificationsJson` with your own).

---

## 7. Testing

### 7.1 Smoke Test (run before merging/relying on this phase)

A minimal end-to-end pass confirming the tables, seed data, and both Prompt tools work together:

1. **Deploy tables.** Run `.\dataverse\scripts\deploy-dataverse-tables.ps1`. Expect it to print both table logical names (`<prefix>_classificationrule`, `<prefix>_classificationaudit`) and their collection names, with no errors.
2. **Idempotency check.** Re-run the same command. Expect every table/column/relationship to be reported as "already exists - skipping" - confirms the script is safe to re-run (e.g. after adding a new column to a schema file later).
3. **Seed data.** Run `.\dataverse\scripts\seed-sample-classifications.ps1`. In the Power Apps maker portal (make.powerapps.com -> your environment -> Tables -> Classification Rule -> Data), confirm 3 rows exist (Invoice Question, Technical Support, Contract Inquiry) with `isactive = Yes`.
4. **Re-run seed.** Run the seed script a second time. Confirm the row count stays at 3 (rows are updated, not duplicated).
5. **Build the Prompt tools.** In Copilot Studio, create the two Prompt tools from Section 4.1/4.2, pasting the Instructions text and defining the Input/Output as documented.
6. **Test `ClassifyMessage` manually** (Prompt tool's own Test pane): use the Section 4.1 example input. Confirm the output JSON matches the expected shape and correctly matches "Invoice Question".
7. **Test a no-match case**: send an unrelated subject/body (e.g. "Happy birthday!") with the same `ClassificationRules`. Confirm `classifications` is empty and `needsHumanRoutingDecision` is `true`.
8. **Test `DraftEmailBody` manually**: feed it the Section 4.1 example output plus a sample original message. Confirm the returned HTML contains all three sections, both `<!-- ROUTING-BLOCK:START -->`/`<!-- DRAFT-RESPONSE:START -->` marker pairs, and that the drafted response is in the same language as the supplied `OriginalBody` (test once in English, once in German, to confirm no unwanted translation).
9. **Wire into `CreateDraft`** (optional but recommended before considering Phase 2 done): pass the generated HTML as `body`/`contentType: "html"` to the existing `CreateDraft` connector operation against a real test mailbox, and open the created draft in Outlook to visually confirm the three sections render correctly and the routing block is clearly marked for removal.
10. **Audit write-back**: after a classification, use the Dataverse connector (or a direct Web API call) to create a Classification Audit row; confirm it appears in the maker portal with the correct `provider`, `confidence`, and (if applicable) `classificationruleid` lookup populated.

If steps 1-4 fail, see Troubleshooting (Section 8) before attempting steps 5-10.

### 7.2 Test the Deployment Scripts

1. Run `deploy-dataverse-tables.ps1` - verify it prints both table logical names and collection (entity set) names with no errors.
2. Re-run it a second time - verify it reports every table/column/relationship as "already exists - skipping" (idempotency check).
3. Run `seed-sample-classifications.ps1` - verify the sample rows appear in the Classification Rule table (Power Apps maker portal -> Tables -> Classification Rule -> Data).

### 7.3 Test the Prompt Tools (once built in Copilot Studio)

1. Open the topic/tool that fetches rules and calls the `ClassifyMessage` Prompt tool.
2. Send a test message body matching one of the seeded rules (e.g. "I have a question about my invoice").
3. Verify the returned classification matches the expected rule, and a row is written to the Classification Audit table.
4. Feed that result into the `DraftEmailBody` Prompt tool and verify the resulting HTML has all three required sections (Section 4.2).

---

## 8. Troubleshooting

| Issue | Resolution |
|---|---|
| **401/403 from `deploy-dataverse-tables.ps1`** | The app registration is not registered as an Application User in the Dataverse environment, or lacks a Customization-capable security role (Section 6.1) |
| **`EntityDefinitions` create fails with a name-conflict error** | The publisher prefix + logical name is already in use by another solution/table - choose a different `DATAVERSE_PUBLISHER_PREFIX` |
| **No classifications returned by the Prompt tool** | Verify the Classification Rule table has active (`isactive = true`) rows and the Prompt tool's grounding context includes them |
| **Wrong department routed** | Review rule priorities and example phrases in the Classification Rule table |
| **Audit table not updated** | Check the Dataverse connector's connection in Copilot Studio and confirm write permissions on the Classification Audit table |
| **`DraftEmailBody` output isn't valid HTML / missing a marker** | Re-check the Instructions text was pasted verbatim (the exact comment marker strings matter if you post-process the HTML to strip the routing block programmatically) |
| **Drafted response is in the wrong language** | Confirm `OriginalBody` (not a translated/summarized version) is passed verbatim as input - the model detects language from that field only |

---

## 9. Next Steps

- Build the Copilot Studio Prompt tools + Topic (Section 4)
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