# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
