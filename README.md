# Bridge365: Transforming Shared Mailboxes into AI-Powered Service Hubs

A comprehensive solution for automatically classifying and routing emails in shared mailboxes using Microsoft Copilot Studio, Azure backend services, and machine learning classifiers.

## Overview

This project provides:

- **Standard Harness:** Custom Connector for Power Platform integration, including an autonomous-agent polling trigger
- **GitHub Copilot Harness:** Executable Skills in Copilot Studio
- **Backend Service:** Azure-hosted Python application with Microsoft Graph API integration
- **Classification Engine:** Rule-based and AI-powered message routing
- **Audit Trail:** Dataverse-based logging and compliance tracking

## Status Summary

| Component | Status | Version |
|-----------|--------|---------|
| Foundation & Documentation | ✅ Complete | v0.1.0 |
| Phase 1: App Registration & Backend | ✅ Complete | v0.2.0 |
| Phase 1: Security Hardening | ✅ Complete | v0.3.0 |
| Phase 1: Repo Reorganization (backend-service / custom-connector / SharedMailboxSkills) | ✅ Complete | v0.4.0 |
| Phase 1: Custom Connector Autonomous Agent Trigger | ✅ Complete | v0.4.1 |
| Phase 1: Copilot Studio Workflow Trigger (GitHub Copilot Harness) | ✅ Complete | v0.4.2 |
| Phase 1: Script Parameter Management (.env Support) | ✅ Complete | v0.4.3 |
| Phase 1: Extract Remaining Inline Test Scripts (.env Support) | ✅ Complete | v0.4.4 |
| Phase 1: Move .env to Repo Root | ✅ Complete | v0.4.5 |
| Phase 1: GitHub Wiki Sync Automation | ✅ Complete | v0.4.6 |
| Phase 1: Fix Wiki Internal Page Links | ✅ Complete | v0.4.7 |
| Phase 1: Fix .env Quoted-Value Parsing | ✅ Complete | v0.4.8 |
| Phase 1: Fix .env Default-Fallback Bug (LOCATION/MAILBOX_ADDRESS) | ✅ Complete | v0.4.9 |
| Phase 1: Azure Deployment Safety Hardening (exit-code checks, tenant/subscription guard) | ✅ Complete | v0.4.10 |
| Phase 1: Email Allowlist OAuth Authorization + Wiki Doc Cleanup | ✅ Complete | v0.4.11 |
| Phase 1: Shared Mailbox Draft Create/Update (Graph createReply + PATCH) | ✅ Complete | v0.4.12 |
| Phase 1: Security Model Documentation (Worked Example) | ✅ Complete | v0.4.13 |
| Phase 1: Fail-safe Backend Deployment Script | ✅ Complete | v0.4.14 |
| Phase 1: Wiki Wording Cleanup (no version-history references) | ✅ Complete | v0.4.15 |
| Phase 1: Graph API Error Handling Fix | ✅ Complete | v0.4.16 |
| Phase 1: SendDraftMessage JSON Body Fix | ✅ Complete | v0.4.17 |
| Phase 1: Wiki Consent-Verification and Real Success-Path Testing | ✅ Complete | v0.4.18 |
| Phase 1: Custom Connector Delegated Auth Fix | ✅ Complete | v0.4.19 |
| Phase 1: Custom Connector CLI Deployment | ✅ Complete | v0.4.20 |
| Phase 1: Delegated Auth Token Fix (Scope/Audience/Version) | ✅ Complete | v0.4.21 |
| Phase 2: Classification Table | 🔄 In Progress | v0.5.0 (planned) |
| Phase 3-7: Advanced Features | 📋 Planned | v0.6.0+ |

## Quick Start (Phase 1: v0.4.21)

### Prerequisites

- Microsoft 365 tenant with Copilot Studio
- Azure subscription
- Shared mailbox with appropriate permissions
- PowerShell 7+ with Azure CLI

### Setup Steps

1. **Read Phase 1 Documentation**
   ```
   docs/wiki/phase-1-mailbox-setup.md
   ```

2. **Follow Step-by-Step Setup**
   - Create Application Registration (Step 3)
   - Deploy Backend Service (Step 4)
   - Configure Custom Connector, optionally as an autonomous agent trigger (Step 5)
   - Set Up Executable Skills (Step 6)
   - Run Integration Tests (Step 7)

3. **Test Each Component**
   All phases include testing procedures with expected outputs.

4. **Next Phase**
   After Phase 1 is complete, proceed to Phase 2: Classification (currently in progress).

## Architecture

```mermaid
graph TB
    subgraph CopilotStudio["Copilot Studio Cloud"]
        CONN["Custom Connector<br/>(Standard Harness)"]
        TRIG["Autonomous Agent Trigger<br/>NewMessageReceived (polling)"]
        EXSKILL["Executable Skills<br/>(GitHub Copilot Harness)"]
    end

    TRIG -.->|powers| CONN
    CONN -->|HTTP REST| BACKEND
    EXSKILL -->|HTTP REST| BACKEND

    subgraph Azure["Azure Backend"]
        BACKEND["Service Endpoint<br/>Python Flask App"]
        BACKEND -->|Graph API| GRAPH["Microsoft Graph<br/>Shared Mailbox"]
        BACKEND -->|SDK| DV["Dataverse<br/>Classifications & Audit"]
    end

    style CopilotStudio fill:#FF9800,color:#fff
    style Azure fill:#4CAF50,color:#fff
```

## Documentation

**Phase-by-Phase Guides:**
- [Phase 1: Shared Mailbox Skill & Custom Connector](docs/wiki/phase-1-mailbox-setup.md) ✅ Complete
- [Phase 2: Classification via Dataverse Table](docs/wiki/phase-2-classification-table.md) 🔄 In Progress

**Reference Documentation:**
- [Wiki Home](docs/wiki/index.md) - Overview and navigation
- [Implementation Plan](docs/implementation-plan.md) - Full roadmap with all phases
- [Changelog](CHANGELOG.md) - Version history and release notes
- [Commit Conventions](COMMIT_CONVENTION.md) - Standardized commit message format

**Helper Scripts:**
All scripts include copyright headers.
- `docs/wiki/scripts/test-app-registration.ps1` - Validate app registration credentials
- `docs/wiki/scripts/grant-mailbox-permissions.ps1` - Configure mailbox access
- `backend-service/scripts/create-app-service.ps1` - Create Azure App Service
- `backend-service/scripts/configure-app-service.ps1` - Set environment variables
- `backend-service/scripts/test-backend.ps1` - Test backend endpoints (health, messages, classify, drafts, poll)
- `backend-service/scripts/enable-backend-auth.ps1`, `configure-allowlist.ps1`, `secure-client-secret.ps1`, `restrict-network-access.ps1`, `review-backend-logs.ps1` - Security hardening
- `docs/wiki/scripts/setup-classification-table.ps1` - Create Dataverse table
- `docs/wiki/scripts/create-sample-classifications.ps1` - Load sample data

## Project Structure

```
bridge365/
├── README.md                           # This file
├── CHANGELOG.md                        # Version history
├── COMMIT_CONVENTION.md                # Commit message format
├── LICENSE                             # Project license
├── backend-service/                    # Flask backend service
│   ├── app.py                          # Backend application (incl. /poll trigger endpoint)
│   ├── requirements.txt                # Python dependencies
│   └── scripts/                        # Deployment & security-hardening scripts
├── custom-connector/                   # Standard harness (Power Platform connector)
│   ├── README.md                       # Setup guide, incl. autonomous agent trigger
│   └── openapi.yaml                    # Connector OpenAPI definition (actions + polling trigger)
├── SharedMailboxSkills/                # GitHub Copilot harness (executable skills)
│   ├── README.md                       # Setup guide
│   └── skills.json                     # Skill/action definitions
└── docs/
    ├── implementation-plan.md          # Full roadmap and phases
    ├── shared-mailbox-classification-master-guide.md  # Reference guide
    └── wiki/                           # Phase-by-phase guides
        ├── index.md                    # Wiki home
        ├── phase-1-mailbox-setup.md    # Phase 1 (complete with testing)
        ├── phase-2-classification-table.md  # Phase 2 (in progress)
        └── scripts/                    # Shared app-registration & Phase 2 scripts
```

## Support & Contribution

For questions or issues:
1. Check the relevant phase documentation in `docs/wiki/`
2. Review the troubleshooting section in the phase guide
3. Check [Implementation Plan](docs/implementation-plan.md) for detailed phase definitions
4. Verify all test procedures pass

## License

Licensed under the project LICENSE file.

## Copyright

(c) 2026 Holger Imbery (contact@holgerimbery.blog)

All code samples include copyright headers. See individual files for details.

---

# Detailed Status

## ✅ IMPLEMENTED

### v0.1.0: Foundation
- ✅ Implementation roadmap with decision tree
- ✅ Semantic versioning (v0.1.0 baseline)
- ✅ Standardized commit conventions (What's New, What's Fixed, What's Modified, Breaking Changes)
- ✅ Changelog tracking all versions
- ✅ Project structure and wiki module

### v0.2.0: Phase 1 - Shared Mailbox Skill & Custom Connector
- ✅ Complete Phase 1 wiki documentation with step-by-step setup
- ✅ Application registration in Microsoft Entra
  - ✅ API permissions (Mail.Read, Mail.Read.Shared, Mail.Send, Mail.Send.Shared)
  - ✅ Client credentials (Client ID, Tenant ID, Secret)
  - ✅ Testing procedures for credential validation
- ✅ Azure App Service deployment
  - ✅ Resource group and App Service plan creation
  - ✅ Environment variable configuration (Azure Client ID/Secret/Tenant)
  - ✅ Health check endpoints
- ✅ Custom Connector (Standard Harness)
  - ✅ OpenAPI specification
  - ✅ Azure AD authentication configuration
  - ✅ Testing procedures with expected outputs
- ✅ Executable Skills (GitHub Copilot Harness)
  - ✅ FetchMessage skill
  - ✅ ClassifyMessage skill
  - ✅ CreateDraft skill
- ✅ Backend Reference Implementation (Python Flask)
  - ✅ /health endpoint
  - ✅ /api/mailbox/messages (list)
  - ✅ /api/mailbox/messages/{id} (get single)
  - ✅ /api/mailbox/classify endpoint
  - ✅ /api/mailbox/drafts endpoint
- ✅ PowerShell Automation Scripts (all with copyright headers)
  - ✅ test-app-registration.ps1
  - ✅ create-app-service.ps1
  - ✅ configure-app-service.ps1
  - ✅ test-backend.ps1
  - ✅ grant-mailbox-permissions.ps1
- ✅ Comprehensive Testing & Verification
  - ✅ Test procedures for every step
  - ✅ Expected output examples
  - ✅ Troubleshooting tables
  - ✅ End-to-end integration testing

### v0.2.1: Documentation Improvements
- ✅ README restructured for clarity
- ✅ Fixed wiki navigation links
- ✅ Moved detailed status to end of README
- ✅ Quick start placed after short status summary
- ✅ Helper scripts documentation
- ✅ Support and contribution guidelines

### v0.2.2: Shared Mailbox Permission Guidance Fix
- ✅ Corrected Step 3.2 app permissions to application-only Graph scopes
- ✅ Replaced incorrect Exchange service-principal guidance with `New-ApplicationAccessPolicy`, scoped to a mail-enabled security group
- ✅ Guarded `Connect-ExchangeOnline` verification step against session/parameter errors

### v0.3.0: Security Hardening
- ✅ Phase 1 section "4.6 Security Hardening (Required Before Production Use)" with 6 controls: JWT authentication, tenant/client-id allowlist, mailbox scope re-verification, Key Vault secret storage, network access restriction, log sanitization
- ✅ Security Hardening Checklist Summary table
- ✅ Five new PowerShell scripts: `enable-backend-auth.ps1`, `configure-allowlist.ps1`, `secure-client-secret.ps1`, `restrict-network-access.ps1`, `review-backend-logs.ps1`

### v0.3.1 - v0.3.2: Script Consistency Fixes
- ✅ Synced 5 scripts referenced only as inline wiki code blocks into standalone files in `docs/wiki/scripts/`
- ✅ Standardized parameter naming (`-ClientId` instead of `-AppId`) across all scripts
- ✅ Removed 2 stale, unreferenced scripts with an inconsistent naming convention

### v0.4.0: Repo Reorganization
- ✅ New `backend-service/` folder: real `app.py`/`requirements.txt` plus deployment/security scripts
- ✅ New `custom-connector/` folder: `openapi.yaml` (Swagger 2.0) and setup guide
- ✅ New `SharedMailboxSkills/` folder: `skills.json` and setup guide
- ✅ Wiki and README updated to reference the new folder locations

### v0.4.1: Custom Connector Autonomous Agent Trigger
- ✅ `NewMessageReceived` polling trigger operation added to `custom-connector/openapi.yaml` (`x-ms-trigger: batch`)
- ✅ Matching `/api/mailbox/messages/poll` endpoint added to `backend-service/app.py` (newest-first, checkpoint-filtered)
- ✅ `backend-service/scripts/test-backend.ps1` extended with a poll-endpoint test
- ✅ Setup guide for wiring the trigger to an autonomous agent (Generative Orchestration, solution-aware cloud flow sharing, author-credential caveat)

### v0.4.2: Copilot Studio Workflow Trigger (GitHub Copilot Harness)
- ✅ New Step 5 "Trigger the Agent Autonomously with a Copilot Studio Workflow" in `SharedMailboxSkills/README.md`, using Copilot Studio's native Workflows feature (connector trigger + Agent node with the `FetchMessage`/`ClassifyMessage`/`CreateDraft` skills as tools)
- ✅ New Step 6.5 in `docs/wiki/phase-1-mailbox-setup.md` cross-referencing the Workflow setup guide
- ✅ New **SendMessage** and **SendDraftMessage** actions across all layers (`backend-service/app.py`, `custom-connector/openapi.yaml`, `SharedMailboxSkills/skills.json`), letting an agent send a brand-new message directly or send an existing draft after optional human review

### v0.4.3: Script Parameter Management (.env Support)
- ✅ New `.env.example` template in `backend-service/` covering all configurable parameters (resource group, app service name, Entra ID credentials, allowlist settings, testing backend URL/mailbox, security group name)
- ✅ All 8 `backend-service/scripts/*.ps1` scripts refactored to load parameters from `.env` when not supplied via CLI, with validation if a value is still missing
- ✅ `.gitignore` added to keep a real `backend-service/.env` (with secrets) out of version control

### v0.4.4: Extract Remaining Inline Test Scripts (.env Support)
- ✅ New `test-app-service.ps1` (`backend-service/scripts/`) extracted from the inline Step 4.2 snippet, with `.env` support
- ✅ New `confirm-mailbox-scope-restriction.ps1` (`docs/wiki/scripts/`) extracted from the inline Step 4.6.3 snippet, with `.env` support
- ✅ All 12 scripts referenced in `docs/wiki/phase-1-mailbox-setup.md` now have matching script files, `.env` support, and a `**Script:**` link

### v0.4.5: Move .env to Repo Root
- ✅ `.env.example` moved from `backend-service/.env.example` to the repo root, so it is visible immediately instead of buried inside `backend-service/`
- ✅ All 12 setup scripts now read the real `.env` from the repo root instead of `backend-service/.env`
- ⚠️ Breaking: if you already created a `backend-service/.env`, move it to the repo root (`.env`)

### v0.4.6: GitHub Wiki Sync Automation
- ✅ New `.github/workflows/sync-wiki.yml` mirrors `docs/wiki/*.md` into the repository's native Wiki tab on every push to `main` touching `docs/wiki/**` (or manually via `workflow_dispatch`)
- ✅ New `.github/scripts/sync-wiki.py` renames `index.md` to `Home.md` and rewrites relative links to scripts/backend-service/custom-connector/SharedMailboxSkills into absolute GitHub blob URLs
- ⚠️ Setup required: add a repository secret `WIKI_SYNC_TOKEN` (PAT with `repo` or `Contents: Read and write` scope) - the default `GITHUB_TOKEN` cannot push to the wiki repo

### v0.4.7: Fix Wiki Internal Page Links
- 🐛 Fixed `.github/scripts/sync-wiki.py`: internal links between wiki pages (e.g. `phase-1-mailbox-setup.md`) now have the `.md` extension stripped, since GitHub Wiki resolves pages by slug and a link keeping `.md` rendered raw/unrendered text or an empty page instead of navigating correctly

### v0.4.8: Fix .env Quoted-Value Parsing
- 🐛 Fixed the `Load-EnvFile` helper (all 12 setup/test scripts) to strip surrounding quotes from `.env` values (e.g. `TENANT_ID= "xxxx"`) - previously the literal quote characters were kept, causing token requests to fail with `400 Bad Request` when relying on `.env` instead of CLI parameters

### v0.4.9: Fix .env Default-Fallback Bug (LOCATION/MAILBOX_ADDRESS)
- 🐛 Fixed `create-app-service.ps1` and `test-backend.ps1`: the `.env` fallback for `-Location`/`-MailboxAddress` used PowerShell's boolean `-or` operator instead of a proper conditional, so it evaluated to the literal string `"True"` instead of the `.env` value - causing `az group create` to fail with `LocationNotAvailableForResourceGroup: The provided location 'True' is not available`

### v0.4.10: Azure Deployment Safety Hardening
- 🐛 Fixed 6 backend scripts (`create-app-service.ps1`, `configure-app-service.ps1`, `configure-allowlist.ps1`, `enable-backend-auth.ps1`, `restrict-network-access.ps1`, `secure-client-secret.ps1`) to check `$LASTEXITCODE` after every `az` call - they previously printed false-positive "✓ ... created" success messages even when the underlying Azure CLI command failed (e.g. quota errors)
- 🐛 Fixed a wrong-tenant deployment risk across all 7 backend scripts: none of them verified the active Azure CLI tenant/subscription before creating or modifying resources, so a stale `az login` session could silently deploy into the wrong tenant
- ✨ New shared `Confirm-AzureContext` function (all 7 scripts) - runs `az account set --subscription` when `.env`'s `AZURE_SUBSCRIPTION_ID` is set, and verifies `az account show --query tenantId` matches `.env`'s `TENANT_ID`, exiting with a clear remediation message on mismatch
- ✨ New `AZURE_SUBSCRIPTION_ID` entry in `.env.example`
- 🔧 `docs/wiki/phase-1-mailbox-setup.md`: all 7 embedded script blocks resynced; new troubleshooting entries for tenant/subscription mismatch errors

### v0.4.11: Email Allowlist OAuth Authorization + Wiki Doc Cleanup
- 🐛 Fixed `docs/wiki/phase-1-mailbox-setup.md`: 6 backend script sections each had their script embedded twice (a stale copy under "Script:" and the current copy mislabeled under "Run it:") - each section now has exactly one up-to-date embed plus a short invocation example
- 🐛 Fixed `backend-service/app.py`: previously had zero enforcement code for the caller allowlist the wiki docs claimed existed
- ✨ New OAuth-based authorization: `app.py` now enforces an `ALLOWED_EMAIL_ADDRESSES` allowlist against the `X-MS-CLIENT-PRINCIPAL-NAME` header injected by Azure App Service Authentication (Easy Auth) - authentication itself stays fully delegated to Microsoft Entra ID
- 🔧 `configure-allowlist.ps1`: replaced `-AllowedTenantId`/`-AllowedClientIds` with `-AllowedEmailAddresses`
- 🔧 `docs/wiki/phase-1-mailbox-setup.md` Section 4.6.2 rewritten for the new email-allowlist model
- ⚠️ Breaking: `ALLOWED_TENANT_ID`/`ALLOWED_CLIENT_IDS` env vars are replaced by `ALLOWED_EMAIL_ADDRESSES` (low impact - the old vars were never actually enforced by any backend code)

### v0.4.12: Shared Mailbox Draft Create/Update
- ✨ Implemented real `CreateDraft` (`POST /api/mailbox/drafts`): calls Graph's `createReply`/`createReplyAll` against `/users/{mailboxAddress}/messages/{messageId}` to create the reply draft directly in the **shared mailbox's own Drafts folder** - never in the calling user's personal mailbox - then PATCHes the new draft with the caller-supplied subject/body. Previously this endpoint returned a hardcoded `draft-placeholder` and never called Graph at all.
- ✨ New `UpdateDraft` endpoint (`PATCH /api/mailbox/drafts/{draftId}`) - edits an existing shared-mailbox draft's subject/body/recipients before it is sent (e.g. after a human reviews a `CreateDraft` result).
- 🔧 `custom-connector/openapi.yaml` and `SharedMailboxSkills/skills.json`: added the new `UpdateDraft` operation/action, and fixed `CreateDraft`'s body definition, which was missing `mailboxAddress` entirely (a pre-existing bug - the connector could never have told the backend which shared mailbox to draft in).
- 🔧 `backend-service/scripts/test-backend.ps1` and `docs/wiki/phase-1-mailbox-setup.md`: added CreateDraft/UpdateDraft smoke tests (now 8 tests total, renumbered).
- 🔧 `docs/wiki/phase-1-mailbox-setup.md`: Operations/Actions reference tables renumbered and updated for the new `CreateDraft` request shape and the new `UpdateDraft` operation/action.

### v0.4.13: Security Model Documentation (Worked Example)
- ✨ `docs/wiki/phase-1-mailbox-setup.md` Section 4.6: new "Understanding the Combined Security Model (Worked Example)" subsection - walks through a concrete example (generic tenant/mailbox/user addresses) showing that a caller can operate the backend and draft mail in the shared mailbox based on Easy Auth (tenant restriction) + the email allowlist, and clarifies that Exchange shared-mailbox membership/delegation is irrelevant to this API's authorization chain.

### v0.4.14: Fail-safe Backend Deployment Script
- ✨ New `backend-service/scripts/deploy-backend.ps1` - deploys the Python backend via the already-authenticated `az` CLI session (no Git credential prompts), removes any conflicting `WEBSITE_RUN_FROM_PACKAGE` setting, sets an explicit `gunicorn` startup command, waits for Kudu to be responsive, retries transient failures up to 3 times, and polls `/health` afterward.
- 🐛 Fixed `docs/wiki/phase-1-mailbox-setup.md` Step 4.4: replaced `git push azure main` (required typing App Service publishing credentials into a Git prompt, and offered no protection against the `WEBSITE_RUN_FROM_PACKAGE`/`SCM_DO_BUILD_DURING_DEPLOYMENT` conflict that causes an endless "Starting the site..."/HTTP 502 loop) with `deploy-backend.ps1`.

### v0.4.15: Wiki Wording Cleanup
- 🐛 Fixed `docs/wiki/phase-1-mailbox-setup.md`: two sections referenced an "earlier version of this guide" and "v0.4.10+" - reworded to describe only current, correct behavior. The wiki is a how-to guide, not a changelog, and should never reference prior versions of itself or the scripts.

### v0.4.16: Graph API Error Handling Fix
- 🐛 Fixed `backend-service/app.py`: Graph API calls in `get_messages`, `poll_new_messages`, `get_message`, `create_draft`, `update_draft`, `send_message`, and `send_draft_message` did not check the HTTP status code Microsoft Graph returned before treating the call as successful - a Graph error (e.g. a nonexistent message/draft ID) was silently parsed and returned as a `200 OK` with null/empty fields instead of an error.
- 🔧 Added a `GraphError` exception plus `graph_json()`/`check_graph_response()` helpers; every Graph-calling endpoint now returns Graph's own error status/message on failure instead of a misleading `200` or an unhandled `500`/`502`.
- ⚠️ Breaking: CreateDraft, UpdateDraft, SendMessage, and SendDraftMessage now return Graph's real error status (typically `404`) for a message/draft ID Graph can't find, instead of the previous (incorrect) always-`200` response.

### v0.4.17: SendDraftMessage JSON Body Fix
- 🐛 Fixed `backend-service/app.py`: `send_draft_message()` called `graph_client.post()` without an explicit JSON body, which raised an internal `TypeError` in `msgraph-core==0.2.2` and surfaced as an opaque `500` regardless of the draft ID's validity - masking the real outcome. Confirmed as a client-side bug, not a permissions issue, since it persisted even after Graph `Mail.Read`/`Mail.ReadWrite`/`Mail.Send` application permissions were correctly consented.
- 🔧 `send_draft_message()` now passes `json={}` explicitly, matching `create_draft()`'s existing pattern; Graph's real status code (`400`/`404`) now surfaces via the v0.4.16 `GraphError` handling instead of a generic `500`.

### v0.4.18: Wiki Consent-Verification and Real Success-Path Testing
- 🔧 Added "Verify Admin Consent Was Actually Granted" under Step 3.2 of `docs/wiki/phase-1-mailbox-setup.md` - shows how to check a service principal's `appRoleAssignments` directly, since the Entra portal's "Granted" status and `az ad app permission list-grants` (delegated grants only) can both misleadingly suggest consent when none was actually recorded.
- 🔧 Added Step 4.5.1, "Validate the Real Send/Draft Success Path" - walks through sending a real message to the shared mailbox, capturing its real `messageId`, and using it to exercise CreateDraft/UpdateDraft/SendDraftMessage against real Graph data, since Step 4.5's smoke test intentionally only uses fake IDs and reports `400`/`404`.
- 🔧 Added two troubleshooting table rows: `403` despite portal-reported consent, and opaque `500` from a Graph POST/PATCH call missing a JSON body.

### v0.4.19: Custom Connector Delegated Auth Fix
- 🐛 Fixed `custom-connector/openapi.yaml`: the `azure_ad` security definition used OAuth `flow: application` (client-credentials, app-only), incompatible with the delegated Easy Auth + per-user email allowlist from Step 4.6 hardening - with no signed-in user, the backend's allowlist check could never match, so every connector call would have been rejected with `403`.
- 🔧 Switched `custom-connector/openapi.yaml` to OAuth `flow: accessCode` (Authorization Code) so each of the three allowlisted users signs in individually.
- 🔧 Documented the required **Resource URL** field and an Application ID URI prerequisite in `docs/wiki/phase-1-mailbox-setup.md` (Step 5.4) and `custom-connector/README.md` (Step 3).

### v0.4.20: Custom Connector Command-Line Deployment
- ✨ Added `custom-connector/scripts/deploy-connector.ps1` and `custom-connector/apiProperties.template.json` - creates or updates the `SharedMailboxConnector` connector directly from the command line via the `paconn` CLI, no Power Platform portal wizard required.
- 🔧 Documented the CLI path as Step 5.0 in `docs/wiki/phase-1-mailbox-setup.md` and in `custom-connector/README.md`, alongside the existing portal-based Steps 5.1-5.6.
- 🔧 Added `POWER_PLATFORM_ENVIRONMENT_ID` and `CUSTOM_CONNECTOR_ID` to `.env.example` for the new script.

### v0.4.21: Delegated Auth Token Fix + PowerShell Testing Guide
- 🐛 Fixed the app registration never actually exposing the `user_impersonation` OAuth2 scope declared in `openapi.yaml` (v0.4.19) - any delegated token request (custom connector or manual testing) failed with `AADSTS650057`/`AADSTS65001` since there was nothing to consent to.
- 🐛 Fixed v2-format access tokens being silently rejected by Easy Auth Classic, which expects v1-issuer tokens - now forced via `requestedAccessTokenVersion: 1` on the app registration.
- 🐛 Fixed valid v1 tokens scoped to the Application ID URI (`api://<app-client-id>`) still getting `401 Unauthorized` - Easy Auth's default accepted audience is the bare Client ID, not the App ID URI; fixed with `--aad-allowed-token-audiences`.
- 🔧 `backend-service/scripts/enable-backend-auth.ps1` now performs all three fixes automatically (`Enable-DelegatedApiScope` + updated `az webapp auth update`); add `-SkipDelegatedScopeSetup` to skip the scope step on repeat runs.
- ✨ Added `docs/wiki/phase-1-mailbox-setup.md` Step 4.6.7 - a full PowerShell recipe for smoke-testing authenticated endpoints (acquire a delegated token, call the API with a bearer header) plus a troubleshooting guide.

---

## 🔄 IN PROGRESS

### v0.5.0 (planned): Phase 2 - Classification via Dataverse Table
- 🔄 Dataverse classification table schema
  - 🔄 Column definitions (className, classExamples, classTarget, etc.)
  - 🔄 Sample classification data (Invoice, Support, Contract, etc.)
- 🔄 Rule-based classifier implementation
  - 🔄 Keyword matching logic
  - 🔄 Confidence scoring
  - 🔄 Target routing configuration
- 🔄 Classification audit table
  - 🔄 Decision tracking
  - 🔄 Timestamp and provider logging
- 🔄 Copilot Studio skill actions
  - 🔄 ClassifyMessage action with Dataverse lookup
  - 🔄 Result aggregation and confidence calculation
- 🔄 Backend endpoint integration
  - 🔄 Dataverse SDK authentication
  - 🔄 Classification query and caching

---

## 📋 ROADMAP

### v0.6.0: Phase 3 - Draft Creation & Routing
- 📋 Draft composition engine with routing block generation
- 📋 Microsoft Graph draft creation API
- 📋 Draft preview in Copilot Studio
- 📋 Draft submission and tracking

### v0.7.0: Phase 4 - Override Workflow & Approvals
- 📋 Manual classification override capability
- 📋 State machine implementation
- 📋 Approval matrix configuration

### v0.8.0: Phase 5 - MCP Server Integration
- 📋 Model Context Protocol (MCP) server
- 📋 GitHub Copilot CLI integration
- 📋 Tool documentation and schema validation

### v0.9.0: Phase 6 - BART Classifier Integration
- 📋 BART model fine-tuning pipeline
- 📋 Azure Machine Learning deployment
- 📋 Confidence-based fallback routing

### v0.9.x: Phase 7 - Production Hardening
- 📋 Monitoring and observability
- 📋 Logging and compliance
- 📋 Security hardening and optimization
- 📋 Disaster recovery and backup

### v1.0.0: General Availability
- 📋 Production-ready release
- 📋 Full documentation and training
- 📋 Support and maintenance model

---

## 💡 BACKLOG (Unscheduled)

Ideas captured for future consideration, not yet assigned to a version or phase.

- 📋 **Promotional website** - a public-facing marketing/landing site to serve as a promotional entrypoint for the project (project overview, key capabilities, links to docs/wiki and the repo), separate from the technical documentation in this README and the wiki.
- 📋 **ServiceHub webpage** - a web application for human service reps to work alongside the autonomous mailbox agent, with role-based authorization levels: **Work with Emails** (view/respond to messages), **Reclassify Email** (correct/override AI classifications), and **Administrative Functions** (tenant/mailbox configuration). This gives SMEs the option to add a human-in-the-loop layer to their email automation instead of running fully autonomous. The admin interface also provides tools to fine-tune the BART classifier and to add/replace knowledge sources used by the solution's autonomous mode.

---

**Current Version:** v0.4.21 | [View Changelog](CHANGELOG.md) | [View Implementation Plan](docs/implementation-plan.md)
