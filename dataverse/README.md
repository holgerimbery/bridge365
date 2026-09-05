# Phase 2: Dataverse Classification Tables

(c) 2026 Holger Imbery (contact@holgerimbery.blog). Licensed under the project LICENSE file.

This folder contains the templates and scripts needed to deploy the two Dataverse
tables that back Phase 2 (message classification), used by a Copilot Studio
Prompt tool - see [`docs/wiki/phase-2-classification-table.md`](../docs/wiki/phase-2-classification-table.md)
for the full design and setup walkthrough.

## Contents

- `schemas/classification-rule.schema.json` - column template for the
  **Classification Rule** table (routing rules: class name, examples, target
  department/email, active flag, priority, model label).
- `schemas/classification-audit.schema.json` - column template for the
  **Classification Audit** table (one row per classified message: result JSON,
  provider, model version, confidence, human-review flag), with a lookup
  relationship back to the matched Classification Rule.
- `scripts/deploy-dataverse-tables.ps1` - creates or updates both tables (and
  the relationship between them) directly via the Dataverse Web API, driven by
  the JSON schema files above. Idempotent - safe to re-run.
- `scripts/seed-sample-classifications.ps1` - upserts sample classification
  rules into the deployed Classification Rule table.

## Prerequisites

The Azure AD app registration used elsewhere in this project (see
`docs/wiki/phase-1-mailbox-setup.md`, Section 3) must be added as an
**Application User** in the target Dataverse environment with a
Customization-capable security role (e.g. **System Customizer**):

1. [Power Platform Admin Center](https://admin.powerplatform.com) -> your
   environment -> **Settings** -> **Users + permissions** -> **Application
   users** -> **+ New app user** -> select the app registration -> assign
   **System Customizer** -> **Save**.

## Usage

```powershell
# 1. Add to .env in the repo root (or pass as parameters):
#    DATAVERSE_ENVIRONMENT_URL=https://org.crm.dynamics.com
#    DATAVERSE_PUBLISHER_PREFIX=b365
#    (TENANT_ID / CLIENT_ID / CLIENT_SECRET are already shared with backend-service)

# 2. Deploy both tables (creates the Classification Rule and Classification
#    Audit tables, plus the lookup relationship between them):
.\dataverse\scripts\deploy-dataverse-tables.ps1

# 3. Load sample classification rules:
.\dataverse\scripts\seed-sample-classifications.ps1
```

Both scripts are idempotent: re-running `deploy-dataverse-tables.ps1` skips any
table/column/relationship that already exists, and `seed-sample-classifications.ps1`
updates existing rows (matched by `className`) instead of creating duplicates.

## Adding a New Table or Column

Add a new `schemas/*.schema.json` file (or a new entry under `attributes`/
`lookups` in an existing one) following the existing format, then re-run
`deploy-dataverse-tables.ps1` - it discovers every `*.schema.json` file in this
folder automatically and only creates what is missing.

Supported column `type` values: `String`, `Memo`, `Integer`, `Decimal`,
`Boolean`. Add a new `case` to `Get-AttributeMetadata` in
`deploy-dataverse-tables.ps1` to support another Dataverse attribute type
(e.g. `Picklist`, `DateTime`).