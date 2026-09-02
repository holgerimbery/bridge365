# Custom Connector Setup (Standard Harness)

(c) 2026 Holger Imbery (contact@holgerimbery.blog). Licensed under the project LICENSE file.

This folder contains the artifacts needed to create the `SharedMailboxConnector` Power
Platform custom connector, used by the standard Copilot Studio harness to call the
[backend service](../backend-service).

## Contents

- `openapi.yaml` - OpenAPI (Swagger 2.0) definition of the four backend operations
  (`GetMessages`, `GetMessage`, `ClassifyMessage`, `CreateDraft`). Import this file
  directly when creating the connector.

## Step 1: Navigate to Power Platform Connectors

1. Open [Power Platform Admin Center](https://admin.powerplatform.com)
   - Or: Azure Portal -> search **Power Platform** -> click **Environments**
2. Select your **environment** (where Copilot Studio is deployed)
3. Click **Power Platform** -> **Connectors** (left sidebar)
   - Or: Click the **Environments** tab -> your environment -> **Connectors**
4. Click **New connector** (top-right)
5. Choose **From OpenAPI**

**Alternative Route (if using Copilot Studio directly):**
1. Open [Copilot Studio](https://copilotstudio.microsoft.com)
2. Click your **agent** (or create new)
3. Click **Connectors** (left sidebar under Skills)
4. Click **Create new connector**
5. Select **From OpenAPI**

## Step 2: Create the Connector

1. Name: `SharedMailboxConnector`
2. Import `openapi.yaml` from this folder (update the `host` field first if your
   backend URL differs from `shared-mailbox-classifier.azurewebsites.net`)
3. Leave all other fields default
4. Click **Create**

## Step 3: Configure Authentication

1. Click **Security** tab
2. **Authentication type:** Azure AD
3. **Tenant ID:** Your Azure tenant ID
4. **Client ID:** Your app registration Client ID
5. **Client secret:** Stored in Azure Key Vault (reference: `@Microsoft.KeyVault(SecretUri=...)`)

## Step 4: Test the Custom Connector

1. Click **Test** (top-right)
2. Choose **GetMessages** operation
3. Enter:
   - mailboxAddress: `shared@company.com`
   - top: `5`
4. Click **Test operation**

**Expected output:**
```json
{
  "value": [
    {
      "id": "AAMkADhhZGFmND...",
      "subject": "Invoice for August",
      "from": {
        "emailAddress": {
          "address": "sender@external.com",
          "name": "External Sender"
        }
      },
      "receivedDateTime": "2026-09-02T10:30:00Z"
    }
  ]
}
```

If you get **401 Unauthorized**, verify:
- App registration credentials are correct
- Client ID and secret match
- API permissions are granted and admin consent is given
