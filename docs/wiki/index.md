# Wiki Index

Welcome to the shared mailbox email classification module wiki.

This wiki documents the setup, implementation, and operation of the email classification system for Microsoft Power Platform and Copilot Studio.

## Phases

- [Phase 0: Foundation](foundation.md)
- [Phase 1: Shared Mailbox Skill & Connector](phase-1-mailbox-setup.md) - includes [Security Hardening](phase-1-mailbox-setup.md#46-security-hardening-required-before-production-use) checklist
- [Phase 2: Classification via Table](phase-2-classification-table.md)
- [Phase 3: Draft Creation](phase-3-draft-creation.md)
- [Phase 4: Override/Change Classification](phase-4-override-workflow.md)
- [Phase 5: MCP Server Integration](phase-5-mcp-integration.md)
- [Phase 6: BART Classifier](phase-6-bart-classifier.md)

## Quick Start

1. Review the [Phase 1 setup guide](phase-1-mailbox-setup.md)
2. Deploy the [backend service](../../backend-service), then set up the
   [custom connector](../../custom-connector) and/or [SharedMailboxSkills](../../SharedMailboxSkills)
3. Test with the provided sample workflows

## Project Structure

- [`backend-service/`](../../backend-service) - Flask backend (`app.py`, `requirements.txt`) plus
  its deployment and security-hardening PowerShell scripts (`backend-service/scripts/`)
- [`custom-connector/`](../../custom-connector) - OpenAPI definition and setup guide for the
  standard Copilot Studio harness
- [`SharedMailboxSkills/`](../../SharedMailboxSkills) - Skill/action definition and setup guide for
  the GitHub Copilot harness (parallel executable skills)
- `docs/wiki/scripts/` - Shared app-registration scripts (`test-app-registration.ps1`,
  `grant-mailbox-permissions.ps1`) and Phase 2 Dataverse scripts

## Scripts

All PowerShell scripts include copyright headers.

- `docs/wiki/scripts/test-app-registration.ps1`, `docs/wiki/scripts/grant-mailbox-permissions.ps1` - Phase 1 app registration and mailbox access policy (shared by all harnesses)
- `backend-service/scripts/create-app-service.ps1`, `configure-app-service.ps1`, `test-backend.ps1` - Phase 1 backend service deployment
- `backend-service/scripts/enable-backend-auth.ps1`, `configure-allowlist.ps1`, `secure-client-secret.ps1`, `restrict-network-access.ps1`, `review-backend-logs.ps1` - Phase 1 security hardening
- `docs/wiki/scripts/setup-classification-table.ps1`, `create-sample-classifications.ps1` - Phase 2 classification table setup

## License & Copyright

(c) 2026 Holger Imbery (contact@holgerimbery.blog)

All code and documentation in this module are copyright protected. See LICENSE file for details.
