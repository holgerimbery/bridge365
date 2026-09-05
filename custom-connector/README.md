   > then call CreateDraft with a reply based on the returned classification. Call
   > SendDraftMessage only after a human has approved the draft (or call
   > SendMessage directly for a fully autonomous reply with no draft step)."

(c) 2026 Holger Imbery (contact@holgerimbery.blog). Licensed under the project LICENSE file.

This folder contains the artifacts needed to create the `SharedMailboxConnector` Power
Platform custom connector, used by the standard Copilot Studio harness to call the
[backend service](../backend-service).

## Contents

- `openapi.yaml` - OpenAPI (Swagger 2.0) definition of the backend operations:
  seven actions (`GetMessages`, `GetMessage`, `ClassifyMessage`, `CreateDraft`, `UpdateDraft`,
  `SendMessage`, `SendDraftMessage`) and one polling trigger (`NewMessageReceived`, see Step 5). Import
  this file directly when creating the connector.

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

The backend enforces delegated Easy Auth plus a per-user email allowlist (see
`docs/wiki/phase-1-mailbox-setup.md`, Step 4.6), so the connector must sign in
as the calling user (not app-only client-credentials) - this is why
`openapi.yaml` uses OAuth `flow: accessCode`, not `application`.

**Prerequisite - set an Application ID URI (Resource URL)** on the app
registration if it does not already have one (safe to re-run):

```powershell
az ad app update --id "<app-client-id>" --identifier-uris "api://<app-client-id>"
```

Then configure the connector:

1. Click **Security** tab
2. **Authentication type:** Azure AD
3. **Tenant ID:** Your Azure tenant ID
4. **Client ID:** Your app registration Client ID
5. **Client secret:** Stored in Azure Key Vault (reference: `@Microsoft.KeyVault(SecretUri=...)`)
6. **Resource URL:** `api://<app-client-id>` (must match the Application ID URI set above)

Each allowlisted user is prompted to sign in with their own Entra ID account
the first time they use the connector.

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

## Step 5: Use as an Autonomous Agent Trigger

The connector's `NewMessageReceived` operation is a polling trigger, so it can
power a Copilot Studio **autonomous agent** that reacts to new mail without any
user conversation - separate from the action-based Topics described above.

**Prerequisites:**
- The agent has **Generative Orchestration** enabled
- The environment has **solution-aware cloud flow sharing** turned on
- Note: event triggers authenticate with the **agent maker's credentials**, not
  per-end-user credentials. Published agents with an authenticated trigger show
  a data-protection warning; admins can block event triggers entirely via DLP
  policy.

**Steps:**

1. Open your agent in [Copilot Studio](https://copilotstudio.microsoft.com)
2. Go to **Overview** (not Topics) -> **Triggers** section
3. Click **Add trigger** -> **SharedMailboxConnector** -> **NewMessageReceived**
4. Set **mailboxAddress**: `shared@company.com`
   - Leave the internal `since` checkpoint parameter untouched; it's managed
     automatically between polls
5. Under **When this trigger fires**, write agent instructions describing what
   to do with the incoming message payload, for example:
   > "A new email arrived in the shared mailbox. Call ClassifyMessage on it,
   > then call CreateDraft with a reply based on the returned classification. Call
   > SendDraftMessage only after a human has approved the draft (or call
   > SendMessage directly for a fully autonomous reply with no draft step)."
6. Save and test by sending an email to the shared mailbox (see the
   `x-ms-trigger-hint` in `openapi.yaml`)

Because polling triggers must return results **newest first**, the connector
calls the backend's `/api/mailbox/messages/poll` endpoint, which applies
`$orderby=receivedDateTime desc` and a `since` checkpoint filter - see
`backend-service/app.py`.
