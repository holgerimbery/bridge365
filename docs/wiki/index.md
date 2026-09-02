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
2. Run the PowerShell scripts in `docs/wiki/scripts/`
3. Test with the provided sample workflows

## Scripts

All PowerShell scripts include copyright headers and are located in `scripts/`:

- `setup-shared-mailbox-skill.ps1` — Copilot Studio skill registration
- `setup-custom-connector.ps1` — Custom connector provisioning
- (More scripts added in subsequent phases)

## License & Copyright

(c) 2026 Holger Imbery (contact@holgerimbery.blog)

All code and documentation in this module are copyright protected. See LICENSE file for details.
