# Custom Connector Setup

(c) 2026 Holger Imbery (contact@holgerimbery.blog). Licensed under the project LICENSE file.

This folder contains the artifacts needed to create the `SharedMailboxConnector` Power
Platform custom connector, used by Copilot Studio to call the
[backend service](../backend-service).

## Contents

- `openapi.template.yaml` - **committed, safe-to-share** OpenAPI (Swagger 2.0)
  template of the backend operations: fifteen actions (`GetMessages`, `GetMessage`,
  `ClassifyMessage`, `CreateDraft`, `UpdateDraft`, `SendMessage`, `SendDraftMessage`,
  `GetMailFolders`, `UpdateMessageCategories`, `MoveMessage`, `GetMessagesDelta`,
  `GetAttachments`, `GetAttachment`, `GetExtendedProperty`, `SetExtendedProperty`)
  and one polling trigger (`NewMessageReceived`, see Step 5). Its `host:` field is
  a placeholder (`__BACKEND_HOST__`), not your real backend hostname.
- `openapi.yaml` - **gitignored, generated** from `openapi.template.yaml` by
  `scripts/generate-openapi.ps1` (or automatically by `deploy-connector.ps1`),
  with your real backend hostname substituted in. Import *this* file when
  creating the connector via the portal wizard (Step 2) - never commit it.
- `apiProperties.template.json` - connector metadata/auth template used by the
  command-line deployment path below (`scripts/deploy-connector.ps1`).
- `scripts/generate-openapi.ps1` - generates the real `openapi.yaml` from
  `openapi.template.yaml` using `BACKEND_URL`/`APP_SERVICE_NAME` from `.env`
  (or `-BackendHost`). Run this before the portal-wizard Step 2 below.
- `scripts/deploy-connector.ps1` - creates or updates the connector from the
  command line via the `paconn` CLI, instead of the portal wizard in Steps 1-4
  (calls `generate-openapi.ps1` automatically).

## Command-Line Alternative: Deploy via paconn CLI

Steps 1-4 below describe the Power Platform portal wizard. You can instead
create or update the connector entirely from the command line with the
[`paconn` CLI](https://learn.microsoft.com/connectors/custom-connectors/paconn-cli),
using this folder's `openapi.template.yaml` and `apiProperties.template.json` -
no manual portal steps needed. `deploy-connector.ps1` generates the real,
gitignored `openapi.yaml` for you from `BACKEND_URL`/`APP_SERVICE_NAME` in
`.env` (or pass `-BackendHost` explicitly).

```powershell
pip install paconn pyyaml
paconn login   # one-time interactive device-code sign-in

.\custom-connector\scripts\deploy-connector.ps1 `
    -EnvironmentId "<power-platform-environment-guid>" `
    -TenantId "<tenant-id>" `
    -ClientId "<app-client-id>" `
    -ClientSecret "<app-client-secret>"
```

The first run creates a new connector and prints its connector ID - save it
(e.g. into `.env` as `CUSTOM_CONNECTOR_ID`) so subsequent runs update the same
connector (pass `-ConnectorId`) instead of creating duplicates. All parameters
can also be supplied via `.env` (see `.env.example`). The script requires the
app registration's delegated OAuth2 scope to already be exposed - see the
prerequisite command in Step 3 below.

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

1. First, generate the real `openapi.yaml` (gitignored) from the committed
   template - it fills in `host:` with your actual backend hostname:
   ```powershell
   .\custom-connector\scripts\generate-openapi.ps1
   # or explicitly: .\custom-connector\scripts\generate-openapi.ps1 -BackendHost "<your-app>.azurewebsites.net"
   ```
2. Name: `SharedMailboxConnector`
3. Import the generated `custom-connector\openapi.yaml`
4. Leave all other fields default
5. Click **Create**

## Step 3: Configure Authentication

The backend enforces delegated Easy Auth plus a per-user email allowlist (see
`docs/wiki/phase-1-mailbox-setup.md`, Step 4.6), so the connector must sign in
as the calling user (not app-only client-credentials) - this is why
`openapi.yaml` uses OAuth `flow: accessCode`, not `application`.

**Prerequisite - expose the delegated OAuth2 scope** used by the connector's
Azure AD auth (Application ID URI, `user_impersonation` scope, v1 access
tokens, and an allowlisted token audience). If you already ran
`enable-backend-auth.ps1` (see `docs/wiki/phase-1-mailbox-setup.md`, Step
4.6.1), this is already done - it runs the same setup automatically.
Otherwise, run it now (safe to re-run):

```powershell
.\backend-service\scripts\enable-backend-auth.ps1 `
    -ResourceGroup "rg-shared-mailbox" `
    -AppServiceName "your-app-name" `
    -TenantId "<tenant-id>" `
    -ClientId "<app-client-id>" `
    -SubscriptionId "<subscription-id>"
```

Then configure the connector:

1. Click **Security** tab
2. **Authentication type:** Azure AD
3. **Tenant ID:** Your Azure tenant ID
4. **Client ID:** Your app registration Client ID
5. **Client secret:** Stored in Azure Key Vault (reference: `@Microsoft.KeyVault(SecretUri=...)`)
6. **Resource URL:** `<app-client-id>` (the bare Client ID GUID - **not**
   `api://<app-client-id>`. Using the App ID URI here fails with
   `AADSTS90009: Application ... is requesting a token for itself. This
   scenario is supported only if resource is specified using the GUID based
   App Identifier`, since the connector's own registered app is also the
   token's audience - a self-referencing token request, which Azure AD only
   allows via the bare GUID, not the App ID URI string.)

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
