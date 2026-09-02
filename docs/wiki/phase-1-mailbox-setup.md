# Phase 1: Shared Mailbox Skill & Custom Connector Setup

**Objective:** Build the core shared mailbox service with custom connector (standard harness) and executable skills (GitHub Copilot harness).

**Harnesses:** 
- **Standard Harness:** Custom Connector only (calls backend service)
- **GitHub Copilot Harness:** Executable Skills in Copilot Studio (also calls backend service)

---

## 1. Prerequisites

- Copilot Studio environment (Power Platform tenant)
- Power Platform admin access
- Shared mailbox address and permissions
- Application registration in Microsoft Entra (for mailbox access via Graph API)
- Azure subscription with App Service or Container Apps available
- PowerShell 7+ with Azure CLI modules
- Python 3.10+ or .NET 8+ for local development

---

## 2. Architecture (Copilot Studio Cloud Execution)

### Two Parallel Harnesses in Copilot Studio

Both harnesses execute within Copilot Studio cloud environment, calling the same backend:

- **Standard Harness:** Custom connector (no skills needed) → Backend service
- **GitHub Copilot Harness:** Executable skills in Copilot Studio → Same backend service
- **Backend Service:** Azure-hosted, handles mailbox access via Microsoft Graph API

No local execution. Everything is cloud-based in Copilot Studio.

### Architecture Diagram

```mermaid
graph TB
    subgraph CopilotStudio["Copilot Studio Cloud Environment"]
        direction TB
        
        subgraph StandardHarness["Standard Harness"]
            CONN["Custom Connector<br/>SharedMailboxConnector"]
        end
        
        subgraph GitHubHarness["GitHub Copilot Harness"]
            EXSKILL["Executable Skills<br/>FetchMessage<br/>ClassifyMessage<br/>CreateDraft"]
        end
        
        CONN -->|HTTP REST| BACKEND
        EXSKILL -->|HTTP REST| BACKEND
    end
    
    subgraph Backend["Backend Service<br/>(Azure-hosted)"]
        BACKEND["Service Endpoint<br/>https://your-api.azurewebsites.net"]
        BACKEND -->|Microsoft Graph| GRAPH["Microsoft Graph API<br/>(Shared Mailbox)"]
    end
    
    style CopilotStudio fill:#FF9800,color:#fff
    style StandardHarness fill:#FFC107,color:#333
    style GitHubHarness fill:#2196F3,color:#fff
    style Backend fill:#4CAF50,color:#fff
```

---

## 3. Application Registration (Required - for Graph API Access)

You **MUST** create an app registration because your backend service needs authenticated access to the shared mailbox.

### Step 3.1: Register the Application in Entra ID

1. Navigate to **[Azure Portal](https://portal.azure.com)**
2. Search for **Microsoft Entra ID** (or click left sidebar → **Microsoft Entra ID**)
3. Click **App registrations** (left sidebar)
4. Click **New registration** (top-left button)
5. Fill in:
   - **Name:** `SharedMailboxClassifier`
   - **Supported account types:** `Accounts in this organizational directory only`
   - **Redirect URI:** Leave blank
6. Click **Register**

### Step 3.2: Add API Permissions

1. In the app registration, click **API permissions** (left sidebar)
2. Click **Add a permission** (top-left)
3. Search for and select **Microsoft Graph**
4. Choose **Application permissions** (not Delegated)
5. Search and add these permissions:
   - `Mail.Read` - Read messages (application permission)
   - `Mail.Send` - Send emails (application permission)
6. Click **Add permissions**
7. Click **Grant admin consent for [Your Tenant]** (and confirm)

> **Important:** `Mail.Read.Shared` and `Mail.Send.Shared` will **not** appear in this picker.
> Those scopes only apply to delegated permissions (a signed-in user acting on a shared mailbox they have delegate access to). Since this backend uses application (client credentials) permissions, shared mailbox access is granted differently by giving the app’s service principal `FullAccess` and `SendAs` rights directly on the mailbox in Exchange Online (see Step 3.5 below).

### Step 3.3: Create Client Credentials

1. Click **Certificates & secrets** (left sidebar)
2. Click **New client secret** (top-left button)
3. Set expiration to **12 months** (or your policy)
4. Click **Add**
5. **Copy the Value immediately** (you can't see it again!)
6. Note your:
   - **Client ID** (from Overview tab: Application (client) ID)
   - **Tenant ID** (from Overview tab: Directory (tenant) ID)
   - **Client Secret** (from Certificates & secrets: Value)

Store these securely in Azure Key Vault or a password manager.

### Step 3.4: Test App Registration

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Test app registration credentials

param(
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$ClientSecret,
    [Parameter(Mandatory)] [string]$TenantId
)

$TokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

$Body = @{
    grant_type = "client_credentials"
    client_id = $ClientId
    client_secret = $ClientSecret
    scope = "https://graph.microsoft.com/.default"
}

try {
    $Response = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $Body
    Write-Host "✓ Token acquired successfully" -ForegroundColor Green
    Write-Host "  Token expires in: $($Response.expires_in) seconds" -ForegroundColor Gray
    Write-Host "  Access Token: $($Response.access_token.Substring(0, 50))..." -ForegroundColor Gray
} catch {
    Write-Host "✗ Token acquisition failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
```

Run it:

```powershell
.\docs\wiki\scripts\test-app-registration.ps1 `
    -ClientId "your-client-id" `
    -ClientSecret "your-client-secret" `
    -TenantId "your-tenant-id"
```

**Expected output:**
```
✓ Token acquired successfully
  Token expires in: 3599 seconds
  Access Token: eyJ0eXAiOiJKV1QiLCJhbGciOi...
```

If you get **401 Unauthorized**, check that:
- Client ID, secret, and tenant ID are correct
- Secret hasn't expired
- App registration is in the correct tenant

### Step 3.5: Restrict Shared Mailbox Access with an Application Access Policy

With **application permissions** (`Mail.Read`, `Mail.Send` + admin consent), Microsoft Graph grants the app access to every mailbox in the tenant. To limit the app to only the shared mailbox, use `New-ApplicationAccessPolicy` scoped to a mail-enabled security group.

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Restricts an app-only Graph application (Mail.Read/Mail.Send) to only
# access the specified shared mailbox, instead of every mailbox in the tenant.

param(
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$MailboxAddress,
    [Parameter(Mandatory)] [string]$SecurityGroupName
)

Connect-ExchangeOnline

# 1. Create a mail-enabled security group scoped to this app (if it doesn't exist yet)
$Group = Get-DistributionGroup -Identity $SecurityGroupName -ErrorAction SilentlyContinue
if (-not $Group) {
    New-DistributionGroup -Name $SecurityGroupName -Type Security | Out-Null
    Write-Host "Created mail-enabled security group: $SecurityGroupName" -ForegroundColor Cyan
}

# 2. Add the shared mailbox as a member of the group
Add-DistributionGroupMember -Identity $SecurityGroupName -Member $MailboxAddress -ErrorAction SilentlyContinue

# 3. Restrict the app so it can only access mailboxes in this group
New-ApplicationAccessPolicy -AccessRight RestrictAccess `
    -AppId $ClientId `
    -PolicyScopeGroupId $SecurityGroupName `
    -Description "Restrict $ClientId to shared mailbox $MailboxAddress"

Write-Host "Application access policy created: $ClientId restricted to $SecurityGroupName" -ForegroundColor Green
```

Save it as `docs/wiki/scripts/grant-mailbox-permissions.ps1`.

Run it:

```powershell
.\docs\wiki\scripts\grant-mailbox-permissions.ps1 `
    -ClientId "your-app-client-id" `
    -MailboxAddress "shared-mailbox@company.com" `
    -SecurityGroupName "AppAccess-SharedMailbox"
```

**Expected output:**
```
Created mail-enabled security group: AppAccess-SharedMailbox
Application access policy created: your-app-client-id restricted to AppAccess-SharedMailbox
```

**Verify the policy took effect:**

```powershell
if (-not (Get-ConnectionInformation)) { Connect-ExchangeOnline }

Test-ApplicationAccessPolicy -Identity "shared-mailbox@company.com" -AppId "your-app-client-id"
```

**Expected output (example):**
```
AppId               : your-app-client-id
Mailbox             : shared-mailbox@company.com
AccessCheckedResult : Granted
```

If `AccessCheckedResult` shows `Denied`, wait 30-60 minutes for policy propagation (Application Access Policies can take up to an hour to apply tenant-wide), then re-run the test.

`FullAccess`/`SendAs` mailbox permissions apply to delegated (user sign-in) access via EWS/Outlook, not app-only Graph API calls, and are not needed here.


---

## 4. Backend Service Deployment (How to Get the URL)

This is the central component that both harnesses call. You must deploy it to Azure.

### Step 4.1: Create Azure App Service

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [string]$Location = "eastus"
)

Write-Host "Creating Azure App Service..." -ForegroundColor Yellow

# Create resource group
az group create --name $ResourceGroup --location $Location
Write-Host "✓ Resource group created: $ResourceGroup" -ForegroundColor Green

# Create App Service plan
az appservice plan create `
    --resource-group $ResourceGroup `
    --name "$AppServiceName-plan" `
    --sku B1 `
    --is-linux

Write-Host "✓ App Service plan created" -ForegroundColor Green

# Create web app
az webapp create `
    --resource-group $ResourceGroup `
    --plan "$AppServiceName-plan" `
    --name $AppServiceName `
    --runtime "PYTHON:3.11"

$Url = "https://$AppServiceName.azurewebsites.net"
Write-Host "✓ App Service created: $Url" -ForegroundColor Green
```

Run it:

```powershell
.\docs\wiki\scripts\create-app-service.ps1 `
    -ResourceGroup "shared-mailbox-rg" `
    -AppServiceName "shared-mailbox-classifier"
```

**Expected output:**
```
Creating Azure App Service...
✓ Resource group created: shared-mailbox-rg
✓ App Service plan created
✓ App Service created: https://shared-mailbox-classifier.azurewebsites.net
```

### Step 4.2: Test App Service is Running

```powershell
$BackendUrl = "https://shared-mailbox-classifier.azurewebsites.net"

# Test connectivity
$Response = Invoke-WebRequest -Uri "$BackendUrl/health" -SkipHttpErrorCheck

Write-Host "Status Code: $($Response.StatusCode)" -ForegroundColor Green
Write-Host "Response: $($Response.Content)" -ForegroundColor Gray
```

**Expected output (initially):**
```
Status Code: 404
Response: <!DOCTYPE html><html><body><h1>404 - Web app not found</h1>
```

This is normal — the app is running but no code is deployed yet. We'll deploy code in the next step.

### Step 4.3: Configure Environment Variables

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$ClientSecret,
    [Parameter(Mandatory)] [string]$TenantId
)

az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings `
        AZURE_CLIENT_ID=$ClientId `
        AZURE_CLIENT_SECRET=$ClientSecret `
        AZURE_TENANT_ID=$TenantId

Write-Host "✓ Environment variables configured" -ForegroundColor Green
```

Run it:

```powershell
.\docs\wiki\scripts\configure-app-service.ps1 `
    -ResourceGroup "shared-mailbox-rg" `
    -AppServiceName "shared-mailbox-classifier" `
    -ClientId "your-client-id" `
    -ClientSecret "your-client-secret" `
    -TenantId "your-tenant-id"
```

**Expected output:**
```
✓ Environment variables configured
```

### Step 4.4: Deploy Backend Code

Create the Python backend application:

```python
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# backend/app.py - Shared Mailbox Service

from flask import Flask, request, jsonify
from azure.identity import ClientSecretCredential
from msgraph.core import GraphClient
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Graph client
try:
    credential = ClientSecretCredential(
        client_id=os.getenv("AZURE_CLIENT_ID"),
        client_secret=os.getenv("AZURE_CLIENT_SECRET"),
        tenant_id=os.getenv("AZURE_TENANT_ID")
    )
    graph_client = GraphClient(credential=credential)
    logging.info("Graph client initialized successfully")
except Exception as e:
    logging.error(f"Failed to initialize Graph client: {e}")

@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "shared-mailbox-classifier"}), 200

@app.route("/api/mailbox/messages", methods=["GET"])
def get_messages():
    """Fetch messages from shared mailbox"""
    try:
        mailbox = request.args.get("mailboxAddress")
        top = request.args.get("top", 10, type=int)
        
        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400
        
        # Call Microsoft Graph API
        response = graph_client.get(
            f"/users/{mailbox}/messages?$top={top}&$select=id,subject,from,receivedDateTime,bodyPreview"
        )
        return jsonify(response.json()), 200
    except Exception as e:
        logging.error(f"Error fetching messages: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/<message_id>", methods=["GET"])
def get_message(message_id):
    """Fetch single message"""
    try:
        mailbox = request.args.get("mailboxAddress")
        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400
        
        response = graph_client.get(
            f"/users/{mailbox}/messages/{message_id}"
        )
        return jsonify(response.json()), 200
    except Exception as e:
        logging.error(f"Error fetching message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/classify", methods=["POST"])
def classify_message():
    """Classify message based on rules"""
    try:
        data = request.json
        message_id = data.get("messageId")
        
        if not message_id:
            return jsonify({"error": "messageId required"}), 400
        
        # Placeholder: Query Dataverse for classification rules (Phase 2)
        # Apply rule-based classifier
        
        return jsonify({
            "classifications": [
                {"className": "Invoice Question", "confidence": 0.92, "targetEmail": "finance@company.com"}
            ]
        }), 200
    except Exception as e:
        logging.error(f"Error classifying message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/drafts", methods=["POST"])
def create_draft():
    """Create reply draft"""
    try:
        data = request.json
        message_id = data.get("messageId")
        subject = data.get("subject")
        body = data.get("body")
        
        if not all([message_id, subject, body]):
            return jsonify({"error": "messageId, subject, body required"}), 400
        
        # Placeholder: Create draft via Graph API (Phase 3)
        
        return jsonify({
            "draftId": "draft-placeholder",
            "draftUrl": "https://outlook.office.com/mail/..."
        }), 200
    except Exception as e:
        logging.error(f"Error creating draft: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

Create `backend/requirements.txt`:

```
Flask==2.3.0
azure-identity==1.13.0
msgraph-core==0.2.2
```

Deploy to App Service:

```powershell
cd backend
git remote add azure https://shared-mailbox-classifier.scm.azurewebsites.net/shared-mailbox-classifier.git
git push azure main
cd ..

Write-Host "✓ Backend deployed" -ForegroundColor Green
```

### Step 4.5: Test Backend Endpoints

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.

param(
    [Parameter(Mandatory)] [string]$BackendUrl,
    [string]$MailboxAddress = "test@company.com"
)

Write-Host "Testing Backend Endpoints" -ForegroundColor Cyan
Write-Host "Backend: $BackendUrl" -ForegroundColor Gray
Write-Host ""

# Test 1: Health endpoint
Write-Host "1. Testing /health endpoint..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$BackendUrl/health" -Method Get
    Write-Host "   ✓ Health check passed" -ForegroundColor Green
    Write-Host "   Response: $($Response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Health check failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Get messages endpoint
Write-Host "2. Testing /api/mailbox/messages endpoint..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages?mailboxAddress=$MailboxAddress&top=5" `
        -Method Get -ErrorAction Stop
    Write-Host "   ✓ Messages endpoint works" -ForegroundColor Green
    Write-Host "   Found $($Response.value.Count) messages" -ForegroundColor Gray
} catch {
    Write-Host "   ⚠ Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "     (This is normal if app registration doesn't have mailbox access yet)" -ForegroundColor Gray
}

Write-Host ""

# Test 3: Classify endpoint
Write-Host "3. Testing /api/mailbox/classify endpoint..." -ForegroundColor Yellow
try {
    $Body = @{ messageId = "test-message-id" } | ConvertTo-Json
    $Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/classify" `
        -Method Post -Body $Body -ContentType "application/json"
    Write-Host "   ✓ Classify endpoint works" -ForegroundColor Green
    Write-Host "   Response: $($Response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Classify endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Testing complete!" -ForegroundColor Cyan
```

Run it:

```powershell
.\docs\wiki\scripts\test-backend.ps1 `
    -BackendUrl "https://shared-mailbox-classifier.azurewebsites.net" `
    -MailboxAddress "shared@company.com"
```

**Expected output:**
```
Testing Backend Endpoints
Backend: https://shared-mailbox-classifier.azurewebsites.net

1. Testing /health endpoint...
   ✓ Health check passed
   Response: {
     "status": "healthy",
     "service": "shared-mailbox-classifier"
   }

2. Testing /api/mailbox/messages endpoint...
   ⚠ Warning: 401 Unauthorized
     (This is normal if app registration doesn't have mailbox access yet)

3. Testing /api/mailbox/classify endpoint...
   ✓ Classify endpoint works
   Response: {
     "classifications": [{"className": "Invoice Question", ...}]
   }

Testing complete!
```

---

## 4.6 Security Hardening (Required Before Production Use)

The backend service is the security boundary for this solution: anything that can call it successfully can act on the shared mailbox using app-only Graph permissions (`Mail.Read`, `Mail.Send`). Complete every step below before connecting real users or production data.

**What this closes:**
- Unauthorized callers hitting your API
- The app reading/sending mail outside the intended shared mailbox
- Client secret exposure
- Public, unauthenticated network exposure
- Sensitive data leaking into logs

### Step 4.6.1: Enforce JWT Authentication on Backend Endpoints

Require every request (except `/health`) to present a valid Microsoft Entra-issued bearer token.

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Enables Azure App Service built-in authentication (Easy Auth) with
# Microsoft Entra ID as the identity provider, so unauthenticated
# requests are rejected before they reach your application code.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId
)

az webapp auth update `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --enabled true `
    --action LoginWithAzureActiveDirectory `
    --aad-client-id $ClientId `
    --aad-token-issuer-url "https://sts.windows.net/$TenantId/"

Write-Host "Entra authentication enabled for $AppServiceName" -ForegroundColor Green
```

Save it as `docs/wiki/scripts/enable-backend-auth.ps1`.

Run it:

```powershell
.\docs\wiki\scripts\enable-backend-auth.ps1 `
    -ResourceGroup "rg-shared-mailbox" `
    -AppServiceName "shared-mailbox-classifier" `
    -TenantId "your-tenant-id" `
    -ClientId "your-app-client-id"
```

**Expected output:**
```
Entra authentication enabled for shared-mailbox-classifier
```

**Test it:**

```powershell
# Request without a token should now be rejected
Invoke-RestMethod -Uri "https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/messages" -Method Get
```

**Expected result:** the call fails with `401 Unauthorized` (or a redirect to sign-in). If it still succeeds without a token, authentication is not correctly enabled — repeat this step before continuing.

### Step 4.6.2: Restrict Callers with an Allowlist

Even with a valid token, only your known connector/client application(s) should be allowed to call the backend. Add an allowlist check in your application configuration (environment variables read by your backend code):

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Sets the tenant and client-id allowlist your backend code checks against
# on every incoming token, in addition to Easy Auth's signature validation.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [Parameter(Mandatory)] [string]$AllowedTenantId,
    [Parameter(Mandatory)] [string]$AllowedClientIds
)

az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings `
        ALLOWED_TENANT_ID="$AllowedTenantId" `
        ALLOWED_CLIENT_IDS="$AllowedClientIds"

Write-Host "Allowlist configured on $AppServiceName" -ForegroundColor Green
```

Save it as `docs/wiki/scripts/configure-allowlist.ps1`.

Run it:

```powershell
.\docs\wiki\scripts\configure-allowlist.ps1 `
    -ResourceGroup "rg-shared-mailbox" `
    -AppServiceName "shared-mailbox-classifier" `
    -AllowedTenantId "your-tenant-id" `
    -AllowedClientIds "your-connector-client-id,your-copilot-skill-client-id"
```

**Expected output:**
```
Allowlist configured on shared-mailbox-classifier
```

Your backend code must read `ALLOWED_TENANT_ID` and `ALLOWED_CLIENT_IDS` and reject any token whose `tid` (tenant) or `appid`/`azp` (client) claim is not in the list, returning `403 Forbidden`.

**Test it:**

```powershell
# Restart so the app picks up new settings, then confirm they are applied
az webapp restart --resource-group "rg-shared-mailbox" --name "shared-mailbox-classifier"
az webapp config appsettings list --resource-group "rg-shared-mailbox" --name "shared-mailbox-classifier" `
    --query "[?name=='ALLOWED_CLIENT_IDS']"
```

**Expected output:** the allowlist value you set is returned, confirming it's active.

### Step 4.6.3: Confirm Mailbox Scope Restriction

This was already configured in [Step 3.5](#step-35-restrict-shared-mailbox-access-with-an-application-access-policy). Re-run the verification here as part of your security checklist:

```powershell
if (-not (Get-ConnectionInformation)) { Connect-ExchangeOnline }

Test-ApplicationAccessPolicy -Identity "shared-mailbox@company.com" -AppId "your-app-client-id"
```

**Expected output:**
```
AppId               : your-app-client-id
Mailbox             : shared-mailbox@company.com
AccessCheckedResult : Granted
```

If this policy is missing, the app can read/send mail for **every mailbox in the tenant**, not just the shared mailbox. Do not proceed to production without this control in place.

### Step 4.6.4: Move the Client Secret to Key Vault

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Stores the app registration client secret in Key Vault and wires the
# App Service to read it via a Key Vault reference, instead of storing
# the plaintext secret directly in application settings.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$KeyVaultName,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [Parameter(Mandatory)] [string]$ClientSecret
)

# Create Key Vault if it doesn't already exist
az keyvault create --resource-group $ResourceGroup --name $KeyVaultName --location "westeurope" 2>$null

# Store the secret
az keyvault secret set --vault-name $KeyVaultName --name "AzureClientSecret" --value $ClientSecret | Out-Null

# Grant the App Service managed identity access to read secrets
az webapp identity assign --resource-group $ResourceGroup --name $AppServiceName | Out-Null
$PrincipalId = az webapp identity show --resource-group $ResourceGroup --name $AppServiceName --query principalId -o tsv

az keyvault set-policy --name $KeyVaultName --object-id $PrincipalId --secret-permissions get list | Out-Null

# Point the app setting to the Key Vault reference instead of the raw value
az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings AZURE_CLIENT_SECRET="@Microsoft.KeyVault(VaultName=$KeyVaultName;SecretName=AzureClientSecret)"

Write-Host "Client secret moved to Key Vault: $KeyVaultName" -ForegroundColor Green
```

Save it as `docs/wiki/scripts/secure-client-secret.ps1`.

Run it:

```powershell
.\docs\wiki\scripts\secure-client-secret.ps1 `
    -ResourceGroup "rg-shared-mailbox" `
    -KeyVaultName "kv-shared-mailbox" `
    -AppServiceName "shared-mailbox-classifier" `
    -ClientSecret "your-current-client-secret"
```

**Expected output:**
```
Client secret moved to Key Vault: kv-shared-mailbox
```

**Test it:**

```powershell
az webapp config appsettings list --resource-group "rg-shared-mailbox" --name "shared-mailbox-classifier" `
    --query "[?name=='AZURE_CLIENT_SECRET'].value" -o tsv
```

**Expected output:** a value starting with `@Microsoft.KeyVault(...)`, not the plaintext secret. Then confirm the backend can still authenticate by re-running [Step 3.4: Test App Registration](#step-34-test-app-registration) — it should still succeed.

### Step 4.6.5: Restrict Network Access (HTTPS-Only + Ingress Control)

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Enforces HTTPS-only traffic and restricts inbound access to an
# allowlisted set of IP ranges (e.g. Power Platform / your office egress).

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [Parameter(Mandatory)] [string[]]$AllowedIpRanges
)

az webapp update --resource-group $ResourceGroup --name $AppServiceName --https-only true

$Priority = 100
foreach ($Range in $AllowedIpRanges) {
    az webapp config access-restriction add `
        --resource-group $ResourceGroup `
        --name $AppServiceName `
        --rule-name "Allow-$Range" `
        --action Allow `
        --ip-address $Range `
        --priority $Priority
    $Priority += 10
}

Write-Host "HTTPS-only enforced and ingress restricted on $AppServiceName" -ForegroundColor Green
```

Save it as `docs/wiki/scripts/restrict-network-access.ps1`.

Run it:

```powershell
.\docs\wiki\scripts\restrict-network-access.ps1 `
    -ResourceGroup "rg-shared-mailbox" `
    -AppServiceName "shared-mailbox-classifier" `
    -AllowedIpRanges @("203.0.113.0/24", "198.51.100.10/32")
```

**Expected output:**
```
HTTPS-only enforced and ingress restricted on shared-mailbox-classifier
```

**Test it:**

```powershell
# HTTP (not HTTPS) should now be rejected
Invoke-WebRequest -Uri "http://shared-mailbox-classifier.azurewebsites.net/health" -Method Get
```

**Expected result:** the request fails or redirects to HTTPS (`301`/`403`), confirming plain HTTP is blocked.

### Step 4.6.6: Remove Sensitive Data from Logs

Review your backend logging code and confirm:
- Tokens, client secrets, and connection strings are never written to logs.
- Full email body/subject content is not logged by default — log only metadata (message ID, classification label, timestamp, correlation ID).

```powershell
# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Pulls recent App Service log lines so you can manually verify no
# secrets or raw email content are present before going live.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName
)

az webapp log tail --resource-group $ResourceGroup --name $AppServiceName
```

Save it as `docs/wiki/scripts/review-backend-logs.ps1`.

Run it (then trigger a few test requests in another window):

```powershell
.\docs\wiki\scripts\review-backend-logs.ps1 `
    -ResourceGroup "rg-shared-mailbox" `
    -AppServiceName "shared-mailbox-classifier"
```

**Expected output:** log lines showing request metadata (method, path, status code, correlation ID) with **no** visible tokens, secrets, or full email bodies. Press `Ctrl+C` to stop tailing.

### Security Hardening Checklist Summary

| # | Control | Verified By |
|---|---------|-------------|
| 4.6.1 | JWT authentication enforced | Unauthenticated call returns `401` |
| 4.6.2 | Caller allowlist configured | Allowlist values present in app settings |
| 4.6.3 | Mailbox scope restricted | `Test-ApplicationAccessPolicy` returns `Granted` for shared mailbox only |
| 4.6.4 | Client secret in Key Vault | App setting shows `@Microsoft.KeyVault(...)` reference |
| 4.6.5 | HTTPS-only + ingress restricted | Plain HTTP call blocked |
| 4.6.6 | Logs free of sensitive data | Manual log review shows no secrets/PII |

Do not proceed to Phase 2+ production rollout until every row in this table is verified.

---

## 5. Custom Connector Setup (Standard Harness)

### Step 5.1: Navigate to Power Platform Connectors

1. Open **[Power Platform Admin Center](https://admin.powerplatform.com)**
   - Or: Azure Portal → search **Power Platform** → click **Environments**
2. Select your **environment** (where Copilot Studio is deployed)
3. Click **Power Platform** → **Connectors** (left sidebar)
   - Or: Click the **Environments** tab → your environment → **Connectors**
4. Click **New connector** (top-right)
5. Choose **From OpenAPI**

**Alternative Route (if using Copilot Studio directly):**
1. Open **[Copilot Studio](https://copilotstudio.microsoft.com)**
2. Click your **agent** (or create new)
3. Click **Connectors** (left sidebar under Skills)
4. Click **Create new connector**
5. Select **From OpenAPI**

### Step 5.2: Create the Connector

1. Name: `SharedMailboxConnector`
2. Host: `shared-mailbox-classifier.azurewebsites.net` (your actual backend URL)
3. Leave all other fields default
4. Click **Create**

### Step 5.3: Add API Operations

1. Click **Definition** tab
2. Add these operations:

**Operation 1: GetMessages**
```
Method: GET
Path: /api/mailbox/messages
Query Parameters:
  - mailboxAddress (string, required)
  - top (integer, optional, default: 10)
Response: Array of Message objects
```

**Operation 2: GetMessage**
```
Method: GET
Path: /api/mailbox/messages/{messageId}
URL Parameters:
  - messageId (string, required)
Query Parameters:
  - mailboxAddress (string, required)
Response: Single Message object
```

**Operation 3: ClassifyMessage**
```
Method: POST
Path: /api/mailbox/classify
Body (JSON):
  {
    "messageId": "string"
  }
Response: Array of Classifications
```

**Operation 4: CreateDraft**
```
Method: POST
Path: /api/mailbox/drafts
Body (JSON):
  {
    "messageId": "string",
    "subject": "string",
    "body": "string",
    "classifications": []
  }
Response: { draftId, draftUrl }
```

### Step 5.4: Configure Authentication

1. Click **Security** tab
2. **Authentication type:** Azure AD
3. **Tenant ID:** Your Azure tenant ID
4. **Client ID:** Your app registration Client ID
5. **Client secret:** Stored in Azure Key Vault (reference: `@Microsoft.KeyVault(SecretUri=...)`)

### Step 5.5: Test Custom Connector

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

---

## 6. GitHub Copilot Harness (Parallel - Executable Skills)

### Step 6.1: Create Executable Skills in Copilot Studio

1. Open **Copilot Studio**
2. Click your **agent**
3. Click **Skills** (left sidebar)
4. Click **Create new skill**
5. Name: `SharedMailboxSkills`
6. Description: `Shared mailbox classification and draft management`

### Step 6.2: Add Skill Actions

Add three actions:

**Action 1: FetchMessage**
```
Input: 
  - mailboxAddress (text)
  - messageId (text)

Output:
  - message (object)
```

**Action 2: ClassifyMessage**
```
Input:
  - mailboxAddress (text)
  - messageId (text)

Output:
  - classifications (array)
```

**Action 3: CreateDraft**
```
Input:
  - mailboxAddress (text)
  - messageId (text)
  - subject (text)
  - body (text)

Output:
  - draftId (text)
  - draftUrl (text)
```

### Step 6.3: Implement Actions (Call Backend)

For each action, add an HTTP call to your backend:

```
FetchMessage:
  HTTP GET → https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/messages/{messageId}?mailboxAddress={mailboxAddress}
  Headers: Authorization: Bearer <token>

ClassifyMessage:
  HTTP POST → https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/classify
  Body: { "messageId": "{messageId}" }

CreateDraft:
  HTTP POST → https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/drafts
  Body: { "messageId", "subject", "body", "classifications" }
```

### Step 6.4: Test Executable Skills

In your Copilot Studio agent:

1. Add a **Topic** that uses the **SharedMailboxSkills**
2. Add a step: Call **FetchMessage** skill
3. Set inputs: mailboxAddress = `shared@company.com`, messageId = `<known-id>`
4. **Test** the agent

**Expected output:**
```
Message retrieved:
  Subject: Invoice for August
  From: sender@external.com
  Received: 2026-09-02 10:30 AM
```

---

## 7. Integration Test: End-to-End

Create a Copilot Studio topic that demonstrates both harnesses:

1. **Standard Harness (Custom Connector):**
   - Call custom connector GetMessages
   - Display results

2. **GitHub Copilot Harness (Executable Skills):**
   - Call FetchMessage skill
   - Verify output matches connector

3. **Verify consistency:** Both should return identical message data

---

## 8. Troubleshooting

| Issue | Resolution |
|---|---|
| **Cannot find Power Platform connectors** | Ensure you're in Power Platform Admin Center (admin.powerplatform.com), not Azure Portal |
| **Backend URL returns 404** | App Service is running but code isn't deployed. Push code via git or use zip deploy |
| **401 Unauthorized from backend** | Verify app registration credentials in environment variables |
| **Custom connector test fails** | Check backend /health endpoint is responding. Verify Azure AD authentication is configured |
| **Executable skill times out** | Increase timeout in skill definition. Verify backend is responding to HTTP calls |

---

## 9. Next Steps

- Proceed to Phase 2: Classification via Dataverse table
- Implement remaining backend endpoints
- Create sample classification data

---

## References

- [Power Platform Admin Center](https://admin.powerplatform.com)
- [Copilot Studio](https://copilotstudio.microsoft.com)
- [Microsoft Graph Mail API](https://learn.microsoft.com/graph/api/resources/message)
- [Power Platform Custom Connectors](https://learn.microsoft.com/connectors/custom-connectors/)
- [Azure App Service](https://learn.microsoft.com/azure/app-service/)

---

**Copyright & License**

(c) 2026 Holger Imbery (contact@holgerimbery.blog)

Licensed under the project LICENSE file.
