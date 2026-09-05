# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.5.0] - 2026-09-05

### What's New
- `dataverse/schemas/classification-rule.schema.json` and `dataverse/schemas/classification-audit.schema.json`: JSON templates defining the two Phase 2 Dataverse tables (Classification Rule, Classification Audit), including a lookup relationship from Audit to Rule.
- `dataverse/scripts/deploy-dataverse-tables.ps1`: idempotent Dataverse Web API deployment script - creates both tables, their columns, and the lookup relationship from the JSON templates directly via the Web API, no manual maker-portal steps required. Safe to re-run.
- `dataverse/scripts/seed-sample-classifications.ps1`: upserts sample classification rules via the Web API, matched/updated by `className`.
- `dataverse/README.md`: setup guide, including the required Azure AD Application User + security role prerequisite in the target Dataverse environment.
- `DATAVERSE_ENVIRONMENT_URL` and `DATAVERSE_PUBLISHER_PREFIX` added to `.env.example`.

### What's Modified
- `docs/wiki/phase-2-classification-table.md`: rewritten to describe the finalized table schemas, reference the new templates/scripts, and document the classification approach - a Copilot Studio Prompt tool (Generative AI action), with a documented future option to swap in a Foundry-hosted model (e.g. BART-MNLI zero-shot classification).
- `README.md`, `docs/implementation-plan.md`, `docs/wiki/index.md`: cross-references updated from the old stub scripts to `dataverse/schemas/`/`dataverse/scripts/`; Status Summary table and Detailed Status updated for the new v0.5.0 entry.

### What's Removed
- `docs/wiki/scripts/setup-classification-table.ps1` and `create-sample-classifications.ps1` - non-functional stub scripts (printed instructions only, never called Dataverse) superseded by the real `dataverse/scripts/` implementations.
- The dead "GitHub Copilot Skill" section and the old Python rule-based classifier sketch from the Phase 2 wiki page, both superseded by the connector-only architecture (v0.4.27) and the Prompt tool classification approach.

### Breaking Changes
- None.

---

## [0.4.29] - 2026-09-05

### What's Fixed
- `docs/wiki/phase-1-mailbox-setup.md`: renumbered `## 7. Integration Test: End-to-End` -> `## 6.`, `## 8. Troubleshooting` -> `## 7.`, and `## 9. Next Steps` -> `## 8.`. The v0.4.27 removal of the "GitHub Copilot Harness" section (formerly Section 6) deleted the section content but never renumbered the sections that followed it, despite that commit's message claiming it had been done.
- `custom-connector/README.md`: restored the missing `# Custom Connector Setup` title. The file's opening lines had been overwritten by a stray duplicate of the Step 5 agent-instructions quote (introduced in v0.4.1) instead of the actual title, so the file started mid-sentence with no heading.
- `README.md` Quick Start "Setup Steps": removed the stale "Set Up Executable Skills (Step 6)" bullet (that section no longer exists since v0.4.27) and renumbered "Run Integration Tests" from Step 7 to Step 6 to match the corrected wiki numbering.
- `README.md` Documentation section: updated the Phase 1 link text from "Phase 1: Shared Mailbox Skill & Custom Connector" to "Phase 1: Shared Mailbox Custom Connector Setup" to match the wiki page's actual (already-renamed) title.

### What's Modified
- `custom-connector/README.md`: reworded "used by the standard Copilot Studio harness" to "used by Copilot Studio" for consistency with the connector-only architecture.

### Breaking Changes
- None.

---

## [0.4.28] - 2026-09-05

### What's New
- `docs/wiki/phase-1-mailbox-setup.md` Step 5.5 now documents how to test every connector operation via the Power Platform Test tab, not just `GetMessages`: `GetMessage`, `ClassifyMessage`, `CreateDraft`, `UpdateDraft`, `SendMessage`, and `SendDraftMessage`, each with exact webform field values and expected output, chaining ids returned by earlier tests (e.g. the Inbox `messageId` from `GetMessages` feeds `GetMessage`/`ClassifyMessage`/`CreateDraft`, and the `draftId` from `CreateDraft` feeds `UpdateDraft`/`SendDraftMessage`).
- Documented the one-time **New connection** step required before the Test tab can call any operation (sign in with an allowlisted user), since the connector uses delegated Azure AD auth.

### What's Modified
- Noted that `SendMessage`/`SendDraftMessage` send **real email** and suggested using a self-addressed test message to avoid spamming real recipients while testing.

### Breaking Changes
- None.

---

## [0.4.27] - 2026-09-05

### What's Removed
- `SharedMailboxSkills/` folder (the "GitHub Copilot harness" - executable skills using a static bearer token) - fully removed. The custom connector's action set is a strict superset of the skill's and is the only path that supports the `NewMessageReceived` polling trigger, so once the connector is registered in a Power Platform environment the skill added no capability, only a parallel, less-secure setup path.

### What's Modified
- Purged all `SharedMailboxSkills`/"GitHub Copilot harness" references from forward-looking documentation: `README.md` (Project Structure tree, Overview bullets), `docs/implementation-plan.md` (roadmap mermaid diagram and every phase's harness framing), `docs/wiki/phase-1-mailbox-setup.md` (architecture mermaid diagram, dedicated GitHub Copilot Harness setup section removed, Integration Test simplified to the connector only, subsequent sections renumbered), `docs/wiki/index.md`, `docs/wiki/phase-2-classification-table.md`, `docs/shared-mailbox-classification-master-guide.md` (harness-mapping and BART-orchestration sections simplified to the single connector path), and `.github/scripts/sync-wiki.py` (comment only).
- Historical `CHANGELOG.md` entries (e.g. v0.4.0-v0.4.12) and README `Detailed Status` entries that describe `SharedMailboxSkills` while it existed are left unchanged, per this project's convention of not rewriting history.

### Breaking Changes
- Any Copilot Studio agent using `SharedMailboxSkills` actions as Tools must switch to the `custom-connector` instead - the skill/action definitions no longer exist in this repo.

---

## [0.4.26] - 2026-09-05

### What's Modified
- `docs/wiki/phase-1-mailbox-setup.md`: `CreateDraft` operation docs now call out that `messageId` must be a real Inbox message id (from `GetMessages`/`GetMessage`), not a draft or sent item, and explains the exact Graph error you get if you use the wrong one - documenting the real pitfall hit and fixed in v0.4.25.

### Breaking Changes
- None.

---

## [0.4.25] - 2026-09-05

### What's Fixed
- **`CreateDraft` failed with `400: "The reference item does not support the requested operation"` even when using an `id` freshly copied from `GetMessages`** - `GetMessages` and the `NewMessageReceived` polling trigger called Microsoft Graph's `/users/{mailbox}/messages` root collection, which returns items from **every** folder (Inbox, Drafts, Sent Items), not just the Inbox. `createReply`/`createReplyAll` only work on real received messages, so whenever the returned list included a draft or sent item, using its `id` for `CreateDraft` failed with this Graph error.

### What's Modified
- `backend-service/app.py`: `get_messages()` and `poll_new_messages()` now call `/users/{mailbox}/mailFolders/inbox/messages` instead of `/users/{mailbox}/messages`, so both only ever return real Inbox mail. No permission changes needed - `Mail.Read` already covers this sub-resource.

### Breaking Changes
- None. `GetMessages`/`NewMessageReceived` responses are now scoped to Inbox only, which is the intended behavior - existing callers see the same shape, just without Drafts/Sent Items mixed in.

---

## [0.4.24] - 2026-09-05

### What's New
- `custom-connector/openapi.template.yaml` - committed, safe-to-share OpenAPI template with a placeholder `host: __BACKEND_HOST__` instead of a real hostname.
- `custom-connector/scripts/generate-openapi.ps1` - generates the real, gitignored `custom-connector/openapi.yaml` from the template, substituting `__BACKEND_HOST__` with your actual backend host (from `.env`'s `BACKEND_URL`/`APP_SERVICE_NAME`, or `-BackendHost`).

### What's Fixed
- **`custom-connector/openapi.yaml` was tracked in git with a real (or stale) backend App Service hostname baked into its `host:` field** - since this repo is going public, no deployment-specific hostname should live in a committed file. It's now generated locally from the template and gitignored.

### What's Modified
- `custom-connector/scripts/deploy-connector.ps1`: now calls `generate-openapi.ps1` automatically before deploying (new optional `-BackendHost` parameter), so the CLI path always uses your current real hostname without it ever being committed.
- `custom-connector/README.md`: Contents, Command-Line Alternative, and Step 2 sections updated to describe the template -> generate -> import workflow.
- `.gitignore`: added `custom-connector/openapi.yaml` (generated); `custom-connector/openapi.template.yaml` remains tracked.
- `CHANGELOG.md`: genericized a real App Service name mention in the v0.4.23 entry to "the backend App Service".
- Audited full `git log --all -p` history for tenant ID, client ID, real email domain, environment/subscription GUIDs, and confirmed none were ever committed; `.env` (with secrets) has also never been committed.

### Breaking Changes
- `custom-connector/openapi.yaml` is no longer tracked in git (`git rm --cached`) and must be generated locally before importing it in the portal wizard or running `deploy-connector.ps1` (the latter now does this automatically). If you previously relied on the committed file, run `.\custom-connector\scripts\generate-openapi.ps1` once to recreate it.

---

## [0.4.23] - 2026-09-05

### What's Fixed
- **Testing the custom connector in Power Platform failed with `AADSTS90009: Application ... is requesting a token for itself. This scenario is supported only if resource is specified using the GUID based App Identifier`** - the connector's `apiProperties.template.json` set `AzureActiveDirectoryResourceId`/`resourceUri` to the App ID URI (`api://<app-client-id>`), but since the connector's own registered app is *also* the token's resource (a self-referencing token request), Azure AD requires the bare Client ID GUID there instead of the App ID URI string.

### What's Modified
- `custom-connector/apiProperties.template.json`: `AzureActiveDirectoryResourceId` and `resourceUri` now use the bare `__CLIENT_ID__` GUID instead of `api://__CLIENT_ID__`.
- `custom-connector/README.md`: Step 3's manual portal-wizard **Resource URL** field updated to the bare Client ID GUID, with an explanation of the self-referencing-token restriction.
- `backend-service/scripts/enable-backend-auth.ps1`: `--aad-allowed-token-audiences` now allowlists **both** `api://<clientId>` (for az CLI/manual delegated-token testing, a different client requesting our API as the resource) and the bare `<clientId>` (for the custom connector's self-referencing token request).
- Applied live: Easy Auth on the backend App Service now accepts both audiences (`az webapp auth update --aad-allowed-token-audiences "api://<clientId>" "<clientId>"`, followed by a restart).

### Breaking Changes
- None. Existing deployments should re-run `enable-backend-auth.ps1` once (safe/idempotent) to pick up the additional allowed audience, and re-run `deploy-connector.ps1` (or manually update the connector's Security tab Resource URL) to pick up the corrected `apiProperties.template.json`.

---

## [0.4.22] - 2026-09-05

### What's Fixed
- **`custom-connector/scripts/deploy-connector.ps1` failed on every run with `json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)`** - the `paconn` CLI's `--api-def` flag always parses the file with `json.load()` regardless of extension, so passing `openapi.yaml` (our source of truth, used by the portal-import path too) directly always failed. Fixed by having the script auto-convert `openapi.yaml` to a generated, gitignored `openapi.generated.json` via a new `custom-connector/scripts/_yaml_to_json.py` helper (using `pyyaml`) before invoking `paconn`, so `openapi.yaml` stays the single source of truth for both the portal-import and command-line deployment paths.

### What's Modified
- `custom-connector/scripts/deploy-connector.ps1`: added the YAML-to-JSON conversion step (requires Python + `pip install pyyaml`, in addition to `paconn`); error messages now mention `pyyaml` where relevant.
- `custom-connector/README.md`: `pip install paconn` command updated to `pip install paconn pyyaml`.
- `.gitignore`: added `custom-connector/openapi.generated.json` (generated at deploy time, never committed).

### Breaking Changes
- None. Existing `.env`/parameter usage is unchanged; the conversion step runs automatically and only requires adding `pyyaml` to your Python environment (`pip install pyyaml`).

---

## [0.4.21] - 2026-09-05

### What's New
- `backend-service/scripts/enable-backend-auth.ps1`: now also exposes a delegated `user_impersonation` OAuth2 scope on the app registration (`Enable-DelegatedApiScope`), forces v1-format access tokens (`requestedAccessTokenVersion: 1`), and allowlists `api://<app-client-id>` as an accepted Easy Auth token audience (`--aad-allowed-token-audiences`) - all three are required before any delegated token request (custom connector or manual testing) succeeds. Add `-SkipDelegatedScopeSetup` to skip the scope step on repeat runs if already configured another way.
- `docs/wiki/phase-1-mailbox-setup.md`: new Step 4.6.7 "Testing Authenticated Endpoints via PowerShell" - a full recipe (get a delegated token via `az login --scope` + `az account get-access-token`, call the API with an `Authorization: Bearer` header) plus a troubleshooting guide for `AADSTS65001`/`AADSTS650057`/`401` errors, including a token-claims decoder snippet.

### What's Fixed
- **Delegated OAuth2 scope was never actually exposed on the app registration** - `custom-connector/openapi.yaml` declared a `user_impersonation` scope (v0.4.19) and the docs described setting an Application ID URI, but nothing configured the actual `oauth2PermissionScopes` on the Entra ID app registration, so any delegated token request failed with `AADSTS650057` ("resource not listed in requested permissions") or `AADSTS65001` (consent required with nothing to consent to).
- **Access tokens issued in v2 format were rejected by Easy Auth** - Easy Auth Classic (`--aad-token-issuer-url "https://sts.windows.net/<tenant>/"`) expects v1-format tokens, but tokens requested via `az account get-access-token`/MSAL default to v2 format unless `requestedAccessTokenVersion: 1` is set on the app registration, causing a silent issuer mismatch (`401 Unauthorized`, no reason logged by Easy Auth).
- **Valid v1 tokens scoped to the Application ID URI were still rejected** - Easy Auth's default accepted audience is the bare Client ID, not the App ID URI (`api://<app-client-id>`) used as the token's `aud` claim, causing `401 Unauthorized` even with a correctly-issued, correctly-signed token; fixed by explicitly allowlisting the App ID URI via `--aad-allowed-token-audiences`.

### What's Modified
- `custom-connector/README.md` and `docs/wiki/phase-1-mailbox-setup.md` (Step 5.0, Step 5.4): prerequisite sections updated to run `enable-backend-auth.ps1` (which now performs the full scope/token-version/audience setup) instead of the previous, incomplete `az ad app update --identifier-uris` command alone.

### Breaking Changes
- None. Existing deployments where `enable-backend-auth.ps1` already ran under v0.4.19 need to re-run it once (safe/idempotent) to pick up the new scope/audience configuration before delegated auth (custom connector or manual token testing) will work.

---

## [0.4.20] - 2026-09-05

### What's New
- `custom-connector/scripts/deploy-connector.ps1`: new script to create or update the `SharedMailboxConnector` custom connector directly from the command line via the `paconn` CLI, using `custom-connector/openapi.yaml` and the new `custom-connector/apiProperties.template.json` - no Power Platform portal wizard required.
- `custom-connector/apiProperties.template.json`: new connector metadata/auth template (Azure AD, `identityProvider: aad`, Application ID URI-based resource) consumed by `deploy-connector.ps1`.
- `docs/wiki/phase-1-mailbox-setup.md` (new Step 5.0) and `custom-connector/README.md`: documented the command-line deployment path as an alternative to the manual portal steps.
- `.env.example`: added `POWER_PLATFORM_ENVIRONMENT_ID` and `CUSTOM_CONNECTOR_ID` for the new script.

### What's Fixed
- None.

### What's Modified
- `.gitignore`: added `custom-connector/apiProperties.json`, the tenant/client-specific file `deploy-connector.ps1` generates from the template at deploy time - never committed.

### Breaking Changes
- None. The portal-based setup (Steps 5.1-5.6) is unchanged and remains fully supported; the CLI path is purely additive.

---

## [0.4.19] - 2026-09-05

### What's New
- `docs/wiki/phase-1-mailbox-setup.md` and `custom-connector/README.md`: added guidance for setting an Application ID URI (Resource URL) on the app registration, required by the custom connector's Azure AD authentication now that it uses a delegated OAuth flow.

### What's Fixed
- `custom-connector/openapi.yaml`: the `azure_ad` security definition used OAuth `flow: application` (client-credentials, app-only, no signed-in user). This is incompatible with the delegated Easy Auth + per-user email allowlist added in v0.4.x security hardening (Step 4.6): with no signed-in user, the backend's `X-MS-CLIENT-PRINCIPAL-NAME` allowlist check could never match one of the three allowed addresses, so every connector call would have been rejected with `403 Forbidden`. Confirmed via live testing of the production backend, where Easy Auth now correctly requires a signed-in user before the allowlist check even runs.

### What's Modified
- `custom-connector/openapi.yaml`: switched the `azure_ad` security definition to OAuth `flow: accessCode` (Authorization Code) with an explicit `authorizationUrl` and `user_impersonation` scope, so each of the three allowlisted users signs in individually and their email is available to the backend's allowlist check.
- `docs/wiki/phase-1-mailbox-setup.md` (Step 5.4) and `custom-connector/README.md` (Step 3): documented the required **Resource URL** field for the connector's Azure AD security configuration (missing from the original instructions), and explained why the connector must use delegated, not app-only, authentication.

### Breaking Changes
- None. Sending/drafting mail still always uses the shared mailbox address supplied in `mailboxAddress` via the backend's own app-only Graph client - this change only affects who is authorized to call the backend through the custom connector, not which mailbox mail is sent from.

---

## [0.4.18] - 2026-09-05

### What's New
- `docs/wiki/phase-1-mailbox-setup.md`: added a "Verify Admin Consent Was Actually Granted" sub-step under Step 3.2, showing how to check a service principal's `appRoleAssignments` directly - the only reliable way to confirm Microsoft Graph application-permission consent actually took effect, since the Entra portal's "Granted" status and `az ad app permission list-grants` (which only reports delegated grants) can both be misleading.
- `docs/wiki/phase-1-mailbox-setup.md`: added Step 4.5.1, "Validate the Real Send/Draft Success Path" - Step 4.5's smoke test intentionally uses fake IDs and only ever produces `400`/`404` warnings; the new section walks through sending a real message to the shared mailbox, capturing its real `messageId`, and using it to exercise CreateDraft/UpdateDraft/SendDraftMessage against real Graph data.
- `docs/wiki/phase-1-mailbox-setup.md`: added two troubleshooting table rows for `403 Forbidden` despite portal-reported consent, and opaque `500` responses from Graph POST/PATCH calls missing a JSON body.

### What's Fixed
- None.

### What's Modified
- None.

### Breaking Changes
- None. Documentation-only change; no code, API, or script behavior is affected.

---

## [0.4.17] - 2026-09-05

### What's Fixed
- `backend-service/app.py`: `send_draft_message()` (`POST /api/mailbox/drafts/<draft_id>/send`) called `graph_client.post()` without an explicit JSON body. `msgraph-core==0.2.2` raises an internal `TypeError` when no body is supplied to `post()`, which was being caught by the generic exception handler and returned as an opaque `500 Internal Server Error` regardless of whether the draft ID was valid - masking the actual outcome of the send attempt. Confirmed via live testing: this `500` persisted even after the app registration's Microsoft Graph `Mail.Read`/`Mail.ReadWrite`/`Mail.Send` application permissions were correctly consented, isolating it as a client-side bug rather than a permissions issue.

### What's Modified
- `backend-service/app.py`: `send_draft_message()` now passes `json={}` explicitly, matching the same pattern already used by `create_draft()`'s `createReply`/`createReplyAll` POST call. Graph's actual response status (e.g. `400` for a malformed draft ID, `404` for a real-but-missing one) now surfaces correctly through the existing `GraphError` handling from v0.4.16, instead of a generic `500`.

### Breaking Changes
- None. Callers already treating a non-2xx `SendDraftMessage` response as a failure are unaffected; only the specific status code returned for an invalid/missing draft ID changes (from an opaque `500` to Graph's actual `400`/`404`).

---

## [0.4.15] - 2026-09-05

### What's New
- None.

### What's Fixed
- `docs/wiki/phase-1-mailbox-setup.md` Step 4.4 and the troubleshooting table referenced an "earlier version of this guide" and "v0.4.10+" - the wiki is a how-to guide for readers, not a changelog, and should never reference prior versions of itself or the scripts. Reworded both sections to describe only the current, correct behavior.

### What's Modified
- `docs/wiki/phase-1-mailbox-setup.md`: two sections reworded to remove version/history references while keeping the same technical guidance.

### Breaking Changes
- None.

---

## [0.4.16] - 2026-09-05

### What's Fixed
- `backend-service/app.py`: Microsoft Graph API calls (`get_messages`, `poll_new_messages`, `get_message`, `create_draft`, `update_draft`, `send_message`, `send_draft_message`) previously called `.json()` (or ignored the response entirely) without checking the HTTP status code Graph actually returned. `msgraph-core`'s `GraphClient` does not raise for non-2xx Graph responses, so a Graph error (e.g. `ErrorItemNotFound` for a deleted or nonexistent message/draft) was silently parsed as if it were a successful payload - callers received a `200 OK` with `null`/empty fields instead of an error, even though the requested operation never happened.
- `POST /api/mailbox/drafts/<draft_id>/send` and `POST /api/mailbox/messages/send` previously discarded the Graph response entirely, so a failed send (e.g. a deleted draft) could report `{"status": "sent"}` even when nothing was sent.

### What's Modified
- `backend-service/app.py`: added a `GraphError` exception plus `graph_json()`/`check_graph_response()` helpers that inspect `response.status_code` and raise `GraphError` for any non-2xx Graph response. Every endpoint that calls Microsoft Graph now routes its response through one of these helpers and has a dedicated `except GraphError` handler that returns Graph's own status code (e.g. `404`, `403`) with the underlying Graph error message, instead of a misleading `200` or a generic unhandled `500`/`502`.

### Breaking Changes
- Callers of `/api/mailbox/drafts` (CreateDraft), `/api/mailbox/drafts/<draft_id>` (UpdateDraft), `/api/mailbox/messages/send` (SendMessage), and `/api/mailbox/drafts/<draft_id>/send` (SendDraftMessage) that operate on a message/draft ID Microsoft Graph can't find will now receive Graph's actual error status (typically `404`) instead of a `200` with empty/null fields. Any caller that was relying on the old (incorrect) always-`200` behavior for these endpoints must now check the response status code.

---

## [0.4.14] - 2026-09-05

### What's New
- `backend-service/scripts/deploy-backend.ps1`: new fail-safe ZIP deployment script for the Python backend on Azure App Service (Linux). Deploys via the already-authenticated `az` CLI session (no Git credential prompts at all), removes any conflicting `WEBSITE_RUN_FROM_PACKAGE` app setting, sets an explicit `gunicorn` startup command, waits for Kudu to become responsive before deploying, retries transient deployment failures up to 3 times, and polls `/health` afterward - printing the deployment log automatically on failure instead of leaving an ambiguous hang.

### What's Fixed
- `docs/wiki/phase-1-mailbox-setup.md` Step 4.4 previously documented deploying via `git push azure main`, which required typing App Service's own publishing credentials into a Git credential prompt (easily confused with a personal Microsoft account password) and offered no protection against the `WEBSITE_RUN_FROM_PACKAGE`/`SCM_DO_BUILD_DURING_DEPLOYMENT` conflict that silently skips the Oryx build step - both were observed in practice to cause an endless "Starting the site..." / HTTP 502 loop with no clear error message.

### What's Modified
- `docs/wiki/phase-1-mailbox-setup.md` Step 4.4 rewritten to use `deploy-backend.ps1` instead of `git push azure main`.

### Breaking Changes
- None. `git push azure main` still works as a manual fallback; `deploy-backend.ps1` is the new documented/recommended path.

---

## [0.4.13] - 2026-09-03

### What's New
- `docs/wiki/phase-1-mailbox-setup.md` Section 4.6: added a new "Understanding the Combined Security Model (Worked Example)" subsection with a concrete example (generic tenant/mailbox/user addresses) walking through why a user can operate the backend and draft mail in the shared mailbox, and clarifying that Exchange shared-mailbox membership/delegation is irrelevant to this API's authorization chain - only Easy Auth (tenant restriction), the email allowlist, and the app's own application access policy matter.

### What's Fixed
- None.

### What's Modified
- None (documentation addition only).

### Breaking Changes
- None.

---

## [0.4.11] - 2026-09-04

### What's Fixed
- `docs/wiki/phase-1-mailbox-setup.md`: fixed a pre-existing documentation bug where 6 of the 7 backend script sections (`configure-app-service.ps1`, `enable-backend-auth.ps1`, `configure-allowlist.ps1`, `secure-client-secret.ps1`, `restrict-network-access.ps1`, `review-backend-logs.ps1`) each embedded their script twice - a stale copy under "Script:" (missing the `Confirm-AzureContext`/exit-code checks from v0.4.10) and the current copy mislabeled under "Run it:". Each section now has exactly one, up-to-date, embedded script plus a short invocation example.
- `backend-service/app.py` previously had **no** enforcement code at all for the caller allowlist described in the wiki - `ALLOWED_TENANT_ID`/`ALLOWED_CLIENT_IDS` were documented as something "your backend code must read" but were never actually implemented.

### What's New
- Added OAuth-based authorization to the backend: a `before_request` hook in `app.py` reads the `X-MS-CLIENT-PRINCIPAL-NAME` header that Azure App Service Authentication (Easy Auth, enabled via `enable-backend-auth.ps1`) injects for every caller it has already authenticated via Microsoft Entra ID, and rejects (`403 Forbidden`) any request to a non-`/health` endpoint whose caller email is not in the new `ALLOWED_EMAIL_ADDRESSES` allowlist. Authentication itself is fully delegated to Microsoft/Entra ID - this app only decides authorization.
- Added `ALLOWED_EMAIL_ADDRESSES` (comma-separated) to `.env.example` and to `configure-allowlist.ps1`'s app-settings write.

### What's Modified
- `configure-allowlist.ps1`: replaced the `-AllowedTenantId`/`-AllowedClientIds` parameters (which set app settings that no backend code ever read) with a single `-AllowedEmailAddresses` parameter, writing `ALLOWED_EMAIL_ADDRESSES` instead of `ALLOWED_TENANT_ID`/`ALLOWED_CLIENT_IDS`. The unrelated `-TenantId`/`-SubscriptionId`/`Confirm-AzureContext` deployment-safety logic (added in v0.4.10) is unchanged.
- `docs/wiki/phase-1-mailbox-setup.md` Section 4.6.2 ("Restrict Callers with an Allowlist") rewritten to describe and demonstrate the new email-based allowlist model, including updated "Test it" verification steps.

### Breaking Changes
- **Env var rename**: `ALLOWED_TENANT_ID` and `ALLOWED_CLIENT_IDS` are replaced by `ALLOWED_EMAIL_ADDRESSES`. If your `.env` or App Service app settings set the old variables, update them to `ALLOWED_EMAIL_ADDRESSES=user1@company.com,user2@company.com` - the old variables are no longer read anywhere. In practice this is a low-impact change since the old variables were never actually enforced by any backend code.

---

## [0.4.12] - 2026-09-03

### What's Fixed
- `custom-connector/openapi.yaml` and `SharedMailboxSkills/skills.json`: the `CreateDraft` operation/action's request body was missing `mailboxAddress` entirely - the connector/skill could never have told the backend which shared mailbox to create the draft in.
- `backend-service/app.py`: `create_draft()` was a placeholder that always returned a hardcoded `draft-placeholder` id/URL and never called Microsoft Graph.

### What's New
- `backend-service/app.py`: `POST /api/mailbox/drafts` (`create_draft`) now calls Graph's `createReply`/`createReplyAll` action against `/users/{mailboxAddress}/messages/{messageId}` to create the reply draft directly in the **shared mailbox's own Drafts folder** (never the calling user's personal mailbox), then `PATCH`es the new draft with the caller-supplied `subject`/`body`. Accepts an optional `replyAll` flag.
- `backend-service/app.py`: new `PATCH /api/mailbox/drafts/<draft_id>` (`update_draft`) endpoint - edits an existing shared-mailbox draft's `subject`/`body`/`toRecipients` before it is sent, changing only the fields supplied.
- `custom-connector/openapi.yaml`: new `UpdateDraft` operation (`PATCH /api/mailbox/drafts/{draftId}`).
- `SharedMailboxSkills/skills.json`: new `UpdateDraft` skill action, matching the new backend endpoint.
- `backend-service/scripts/test-backend.ps1`: added CreateDraft/UpdateDraft smoke tests (now 8 tests total).

### What's Modified
- `custom-connector/openapi.yaml`, `SharedMailboxSkills/skills.json`: `CreateDraft` request schema gained `mailboxAddress` (bug fix) and an optional `replyAll` flag; response now also returns `subject`.
- `custom-connector/README.md`, `SharedMailboxSkills/README.md`: action/operation counts and sample HTTP call bodies updated for `CreateDraft`'s corrected shape and the new `UpdateDraft` action.
- `docs/wiki/phase-1-mailbox-setup.md`: Operations 4-7 and Actions 3-6 reference tables renumbered and updated; embedded `test-backend.ps1` copy and its "Expected output" resynced with the new 8-test script.

### Breaking Changes
- None. `CreateDraft`'s new `mailboxAddress` field is required going forward (it was silently broken before, since the backend has always required it), and the new `replyAll`/`to` fields are optional.

---

## [0.4.10] - 2026-09-03

### What's Fixed
- `create-app-service.ps1`, `configure-app-service.ps1`, `configure-allowlist.ps1`, `enable-backend-auth.ps1`, `restrict-network-access.ps1`, `secure-client-secret.ps1`: added `$LASTEXITCODE` checks after every `az` CLI call. Previously, scripts printed unconditional "✓ ... created/configured" success messages even when the underlying `az` command failed (e.g. `create-app-service.ps1` reported "✓ App Service plan created" and "✓ App Service created" after an Azure quota error, masking the real failure).
- All 7 backend deployment/test scripts (`create-app-service.ps1`, `configure-app-service.ps1`, `configure-allowlist.ps1`, `enable-backend-auth.ps1`, `restrict-network-access.ps1`, `secure-client-secret.ps1`, `review-backend-logs.ps1`): fixed a security/correctness gap where scripts never verified the active Azure CLI tenant/subscription before creating or modifying resources - a stale `az login` session could silently deploy resources into the wrong tenant (reported: a resource group was created in the wrong tenant because `.env`'s `TENANT_ID` was never checked against the logged-in Azure CLI context).

### What's New
- Added a shared `Confirm-AzureContext` function to all 7 backend scripts. When `.env` (or CLI parameters) supply `AZURE_SUBSCRIPTION_ID`, it runs `az account set --subscription` before any mutating/read call. When `TENANT_ID` is supplied, it compares `az account show --query tenantId` against it and exits with a clear remediation message (`az login --tenant <TENANT_ID>`) on mismatch. Both checks are opt-in - if neither value is present, scripts behave exactly as before.
- Added new `$TenantId` / `$SubscriptionId` parameters to all 7 scripts (backward-compatible; `configure-allowlist.ps1` keeps its existing `$AllowedTenantId` parameter, which serves a different purpose - the token-validation allowlist - and is unrelated to the new deployment-context check).
- Added `AZURE_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` to `.env.example`.
- Added troubleshooting entries in `docs/wiki/phase-1-mailbox-setup.md` for the new tenant/subscription mismatch errors and the exit-code-check fix.

### What's Modified
- `docs/wiki/phase-1-mailbox-setup.md`: all 7 embedded script code blocks resynced to match the updated source scripts.

### Breaking Changes
- None. New parameters are optional and only activate the safety checks when `.env` supplies `TENANT_ID` and/or `AZURE_SUBSCRIPTION_ID`.

---

## [0.4.9] - 2026-09-03

### What's Fixed
- `create-app-service.ps1` and `test-backend.ps1`: fixed a bug where the `.env`-sourced default fallback for `-Location` / `-MailboxAddress` used PowerShell's `-or` operator (e.g. `['LOCATION'] -or "eastus"`), which is a *boolean* operator, not a null-coalescing fallback. It evaluated both sides as booleans and returned the literal string `"True"` instead of the intended value - causing `create-app-service.ps1` to fail with `LocationNotAvailableForResourceGroup: The provided location 'True' is not available` even though `.env` correctly set `LOCATION=eastus`.
- `docs/wiki/phase-1-mailbox-setup.md`: both embedded code blocks resynced to match.

### What's Modified
- None.

### Breaking Changes
- None.

---

## [0.4.8] - 2026-09-02

### What's Fixed
- `Load-EnvFile` helper (present in all 12 setup/test scripts) now strips surrounding single or double quotes from `.env` values, in addition to trimming whitespace. Previously, a value written as `TENANT_ID= "xxxx"` was loaded as the literal string `"xxxx"` (quotes included), which silently broke Microsoft Entra ID token requests with a `400 Bad Request` - while the same value passed directly as a CLI parameter worked fine, since PowerShell strips the quotes for CLI arguments automatically.
- `docs/wiki/phase-1-mailbox-setup.md`: all 12 embedded `Load-EnvFile` code blocks resynced to match the fix.

### What's Modified
- None.

### Breaking Changes
- None. Quoted values in an existing `.env` (`KEY= "value"`) now parse correctly; unquoted values (`KEY=value`) continue to work exactly as before.

---

## [0.4.7] - 2026-09-02

### What's Fixed
- `.github/scripts/sync-wiki.py`: internal links between wiki pages (e.g. `[Phase 1 setup guide](phase-1-mailbox-setup.md)`) now have their `.md` extension stripped when synced to the Wiki repo. GitHub Wiki resolves pages by slug, not filename - a link that kept the `.md` extension rendered as raw/unrendered markdown text (or an empty page) instead of navigating to the target page, which was the root cause of the wiki appearing "not the same" as the `docs/wiki/` source.

### What's Modified
- None.

### Breaking Changes
- None. Existing wiki pages will be corrected automatically on the next sync (push to `main` touching `docs/wiki/**`, or a manual `workflow_dispatch` run).

---

## [0.4.6] - 2026-09-02

### What's New
- New `.github/workflows/sync-wiki.yml` GitHub Action that mirrors `docs/wiki/*.md` into the repository's native GitHub Wiki (the "Wiki" tab) on every push to `main` that touches `docs/wiki/**`, or on-demand via `workflow_dispatch`.
- New `.github/scripts/sync-wiki.py` helper: copies each top-level `docs/wiki/*.md` page into the wiki repo, renames `index.md` to `Home.md` (the wiki landing page), and rewrites relative links to `docs/wiki/scripts/`, `backend-service/`, `custom-connector/`, and `SharedMailboxSkills/` into absolute GitHub blob URLs, since the wiki repo has no access to sibling files in the main repo.

### What's Modified
- None. `docs/wiki/` remains the source of truth; the Wiki tab is now an auto-generated mirror.

### Breaking Changes
- None. Requires a one-time setup step: add a repository secret `WIKI_SYNC_TOKEN` (a PAT with `repo` or `Contents: Read and write` scope) so the workflow can push to the wiki repo, since the default `GITHUB_TOKEN` cannot.

---

## [0.4.5] - 2026-09-02

### What's New
- `.env.example` moved from `backend-service/.env.example` to the repo root (`.env.example`), so it is immediately visible when browsing the repository instead of being buried inside `backend-service/`.

### What's Modified
- All 12 setup scripts (`backend-service/scripts/*.ps1` and `docs/wiki/scripts/*.ps1`) updated to look for the real `.env` file at the repo root instead of `backend-service/.env`.
- `docs/wiki/phase-1-mailbox-setup.md`: all 12 embedded code blocks resynced to match the updated `.env` path resolution logic.
- `.gitignore` simplified to ignore `.env`/`*.env` anywhere in the repo (previously scoped to `backend-service/.env`), while still tracking `*.env.example` templates.

### Breaking Changes
- If you already created a `backend-service/.env` file locally, move it to the repo root (`.env`) - scripts will no longer read from the old location.

---

## [0.4.4] - 2026-09-02

### What's New
- New `test-app-service.ps1` script (`backend-service/scripts/`) extracted from the previously inline Step 4.2 verification snippet, with full `.env` support (`BACKEND_URL`).
- New `confirm-mailbox-scope-restriction.ps1` script (`docs/wiki/scripts/`) extracted from the previously inline Step 4.6.3 verification snippet, with full `.env` support (`CLIENT_ID`, `MAILBOX_ADDRESS`).

### What's Modified
- `docs/wiki/phase-1-mailbox-setup.md`: Steps 4.2 and 4.6.3 now link to their own script files (matching all other steps) instead of embedding a one-off inline snippet with no `.env` support.

### Breaking Changes
- None. Both scripts are new, and the behavior of the verification snippets is unchanged - only the parameter source (`.env` support) and file extraction are new.

---

## [0.4.3] - 2026-09-02

### What's New
- New `.env.example` template in `backend-service/` with all configurable parameters (resource group, app service name, Entra ID credentials, allowlist settings, testing backend URL and mailbox).

### What's Modified
- All deployment and testing scripts in `backend-service/scripts/` refactored to support loading parameters from a `.env` file in addition to (or instead of) command-line parameters. Scripts now load from `.env` if a parameter is not explicitly provided via CLI, with fallback validation to ensure all required values are present before executing Azure/HTTP operations.

### Breaking Changes
- None. All scripts remain backward-compatible with direct CLI parameters (e.g., `.\create-app-service.ps1 -ResourceGroup "..." -AppServiceName "..."`); the `.env` file is optional and only used if the file exists and CLI parameters are not supplied.

---

## [0.4.2] - 2026-09-02

### What's New
- New "Trigger the Agent Autonomously with a Copilot Studio Workflow" section (Step 5) in `SharedMailboxSkills/README.md`, documenting how to run the GitHub Copilot harness (executable skills) autonomously using Copilot Studio's native **Workflows** feature - a connector-based trigger ("When a new email arrives" or the custom connector's `NewMessageReceived` trigger) feeding an Agent node equipped with the `FetchMessage`/`ClassifyMessage`/`CreateDraft` skills as tools, with no external orchestration required.
- New Step 6.5 in `docs/wiki/phase-1-mailbox-setup.md` cross-referencing the Workflow setup guide.
- Added **SendMessage** and **SendDraftMessage** actions across all layers: `backend-service/app.py` gained `POST /api/mailbox/messages/send` (Graph `sendMail`) and `POST /api/mailbox/drafts/<draftId>/send` (Graph `.../messages/{id}/send`); `custom-connector/openapi.yaml` gained matching `SendMessage`/`SendDraftMessage` operations; `SharedMailboxSkills/skills.json` gained matching skill actions. This lets an agent send a brand-new message directly, or send an existing (optionally human-edited) draft created by `CreateDraft`.

### What's Modified
- `backend-service/scripts/test-backend.ps1` extended with Test 5 (send message) and Test 6 (send draft message), keeping the script in sync with `app.py`.
- `custom-connector/README.md` updated to list six actions and mention the new send actions in the autonomous-trigger sample instructions.
- `SharedMailboxSkills/README.md` updated to list five actions, with new HTTP mapping entries for `SendMessage`/`SendDraftMessage` and updated Workflow-trigger sample instructions.
- `docs/wiki/phase-1-mailbox-setup.md` updated with a byte-identical refresh of the embedded `test-backend.ps1` copy (previously missing Test 4), new Operation/Action blocks for `SendMessage`/`SendDraftMessage` in Steps 5.3 and 6.2/6.3, and updated Step 5.6/6.5 trigger instructions.

### Breaking Changes
- None.

---

## [0.4.1] - 2026-09-02

### What's New
- Added a `NewMessageReceived` polling trigger operation to `custom-connector/openapi.yaml` (`x-ms-trigger: batch`), so the `SharedMailboxConnector` can now power a Copilot Studio agent-level **Trigger**, enabling autonomous agents that react to new shared-mailbox mail without a user conversation.
- Added a matching `/api/mailbox/messages/poll` endpoint to `backend-service/app.py`, returning new messages in reverse-chronological order using a `since` checkpoint, per the connector polling-trigger contract.
- New "Use as an Autonomous Agent Trigger" section in `custom-connector/README.md` (Step 5) documenting the Generative Orchestration and solution-aware cloud flow sharing prerequisites, the author-credential authentication caveat, and how to wire the trigger to agent instructions.
- New Step 5.6 in `docs/wiki/phase-1-mailbox-setup.md` cross-referencing the connector READMEs trigger setup guide.

### What's Modified
- `backend-service/scripts/test-backend.ps1` extended with a Test 4 for the new `/poll` endpoint, keeping the script in sync with `app.py`.
- `README.md` rewritten to reflect the real release history (v0.3.0 security hardening, v0.3.1/v0.3.2 script fixes, v0.4.0 folder reorg, v0.4.1 trigger support) with an updated Status Summary, Architecture diagram, and Current Version.

### Breaking Changes
- None.

---

## [0.4.0] - 2026-09-02

### What's New
- New top-level `backend-service/` folder: extracted `app.py` and `requirements.txt` from the Phase 1 wiki into real, standalone source files, plus a `scripts/` subfolder with the 8 backend deployment and security-hardening PowerShell scripts.
- New top-level `custom-connector/` folder: added `openapi.yaml`, a proper OpenAPI (Swagger 2.0) definition of the four backend operations (`GetMessages`, `GetMessage`, `ClassifyMessage`, `CreateDraft`), plus a standalone `README.md` setup guide.
- New top-level `SharedMailboxSkills/` folder: added `skills.json`, a declarative definition of the three Copilot Studio executable skill actions (`FetchMessage`, `ClassifyMessage`, `CreateDraft`), plus a standalone `README.md` setup guide.

### What's Modified
- `docs/wiki/phase-1-mailbox-setup.md` updated to reference the new folder locations for all backend scripts, the backend source code, the connector OpenAPI spec, and the skill definition.
- `docs/wiki/index.md` and `README.md` updated with a Project Structure overview reflecting the new folders.
- `docs/implementation-plan.md` updated to remove references to the removed placeholder scripts.

### Breaking Changes
- The 8 backend scripts (`create-app-service.ps1`, `configure-app-service.ps1`, `test-backend.ps1`, `enable-backend-auth.ps1`, `configure-allowlist.ps1`, `secure-client-secret.ps1`, `restrict-network-access.ps1`, `review-backend-logs.ps1`) moved from `docs/wiki/scripts/` to `backend-service/scripts/`. Update any local references to the old paths.

---

## [0.3.2] - 2026-09-02

### What's Fixed
- Removed two stale scripts (`setup-shared-mailbox-skill.ps1`, `setup-custom-connector.ps1`) that were not referenced by any current wiki step and used a different, inconsistent parameter naming convention (`EnvironmentId`, `SkillName`, `ApiHost`, `ConnectorName`). Steps 5/6 now use manual Power Platform UI instructions, not scripts.
- Updated the `docs/wiki/index.md` script list to reflect the actual, current set of scripts in `docs/wiki/scripts/`.

### Breaking Changes
- None.

---

## [0.3.1] - 2026-09-02

### What's Fixed
- Five PowerShell scripts referenced inline in Phase 1 (`test-app-registration.ps1`, `grant-mailbox-permissions.ps1`, `create-app-service.ps1`, `configure-app-service.ps1`, `test-backend.ps1`) existed only as embedded code blocks in the wiki markdown and were missing from `docs/wiki/scripts/`. All five are now saved as standalone files, verified byte-identical to the wiki content.
- `grant-mailbox-permissions.ps1` used `-AppId` while every other script used `-ClientId` for the same Entra app registration ID. Renamed to `-ClientId` in both the script and the wiki (Step 3.5) for consistency.

### What's Modified
- Confirmed all 12 documented scripts across Phase 1 and Phase 2 use a consistent parameter naming convention: `ResourceGroup`, `AppServiceName`, `ClientId`, `ClientSecret`, `TenantId`, `MailboxAddress`, `BackendUrl`.

### Breaking Changes
- None.

---

## [0.3.0] - 2026-09-02

### What's New
- New Phase 1 section "4.6 Security Hardening (Required Before Production Use)" with 6 step-by-step controls:
  - Step 4.6.1: Enforce JWT authentication on backend endpoints (Easy Auth + Entra ID)
  - Step 4.6.2: Restrict callers with a tenant/client-id allowlist
  - Step 4.6.3: Confirm mailbox scope restriction (re-verification of Step 3.5)
  - Step 4.6.4: Move the client secret to Azure Key Vault
  - Step 4.6.5: Restrict network access (HTTPS-only + IP allowlist)
  - Step 4.6.6: Remove sensitive data from logs
- Security Hardening Checklist Summary table for quick verification
- Five new PowerShell scripts (all with copyright headers), each with a test/verification command and expected output:
  - `enable-backend-auth.ps1`
  - `configure-allowlist.ps1`
  - `secure-client-secret.ps1`
  - `restrict-network-access.ps1`
  - `review-backend-logs.ps1`
- Wiki index updated with a direct link to the Security Hardening checklist

### Breaking Changes
- None (additive documentation and scripts only)

---

## [0.2.2] - 2026-09-02

### What's Fixed
- Step 3.2 (App API Permissions): removed `Mail.Read.Shared` and `Mail.Send.Shared` - these are delegated-only Graph scopes and do not appear in the application permission picker for app-only (client credentials) authentication
- Step 3.5 (Shared Mailbox Access): replaced incorrect `Add-MailboxPermission`/`Add-RecipientPermission` via `Get-ServicePrincipal` guidance - this always fails with "couldn't be found" because app-only Graph apps are never registered as Exchange service principals
- Step 3.5 verification snippet: guarded `Connect-ExchangeOnline` with an existing-session check to avoid a parameter-binding error on the following `Test-ApplicationAccessPolicy` line

### What's Modified
- Step 3.5 rewritten to use `New-ApplicationAccessPolicy` scoped to a mail-enabled security group, restricting the app to the shared mailbox instead of the whole tenant (the Microsoft-documented approach for app-only Graph mailbox access)
- Added `Test-ApplicationAccessPolicy` verification step with expected output
- Simplified wording throughout Step 3.5 (removed redundant explanation and meta-commentary)

### Breaking Changes
- None (documentation only)

---

## [0.2.1] - 2026-09-02

### What's New
- README restructured for improved clarity and navigation
- Status summary table at top with quick overview
- Quick start section moved after short status
- Detailed implementation status moved to end of README
- Fixed wiki navigation links to use docs/wiki folder (works from GitHub web)
- Helper scripts documentation in README
- Support and contribution guidelines

### What's Fixed
- Wiki links now work correctly from GitHub repository web interface
- Navigation flow: Overview → Status → Quick Start → Architecture → Docs

### What's Modified
- README now serves as project status dashboard with clear sections
- Reorganized for better user experience (progressive disclosure)

### Breaking Changes
- None (documentation only)

---

## [0.2.0] - 2026-09-02

### What's New
- Phase 1 wiki documentation complete: `docs/wiki/phase-1-mailbox-setup.md`
- Phase 2 wiki documentation started: `docs/wiki/phase-2-classification-table.md`
- Application registration setup guide with testing procedures
- Azure App Service deployment with environment configuration
- Custom Connector setup (Standard Harness) with testing
- Executable Skills setup (GitHub Copilot Harness) with testing
- Python Flask backend reference implementation
- Comprehensive testing procedures for all components
- Expected output examples for validation
- PowerShell helper scripts for automation
- README updated with project overview and wiki links

### What's Fixed
- Clarified architecture: Standard Harness is custom connector only (no skills)
- Corrected Copilot Studio cloud execution model (not local PC)

### What's Modified
- Section numbering and organization throughout Phase 1 guide
- Testing procedures now included after every major step
- Added detailed navigation instructions (Power Platform Admin Center + Copilot Studio routes)

### Breaking Changes
- None

---

## [0.1.1] - 2026-09-02

### What's New
- Reordered implementation plan: Copilot Studio standard harness (primary) + GitHub Copilot (parallel)
- New phase sequence: Foundation → Shared Mailbox Skill → Classification Table → Draft → Override → MCP → BART → Release
- Created wiki module structure under `docs/wiki/`
- Phase 1 wiki guide: `docs/wiki/phase-1-mailbox-setup.md`
- PowerShell helper scripts with copyright headers (skill setup, connector setup)
- Explicit copyright and license headers on all code elements

### What's Fixed
- None

### What's Modified
- Implementation plan now emphasizes Copilot Studio-first approach
- All phases include both harnesses (Copilot Studio primary, GitHub Copilot parallel)

### Breaking Changes
- None (plan update only)

---

## [0.1.0] - 2026-09-02

### What's New
- Project foundation: directory structure (src/, tests/, docs/)
- Python environment and dependency management
- Configuration schema with Pydantic models
- Base service class with dependency injection
- Unit test framework and initial test suite
- Implementation plan with 8-phase roadmap (v0.1.0 → v1.0.0)
- Commit and PR message conventions documented
- Source documentation: `docs/shared-mailbox-classification-master-guide.md`

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- N/A
