# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
- None

---

## [0.2.0] - TBD

### What's New
- Shared mailbox Copilot Studio skill
- Custom connector for mailbox operations
- PowerShell provisioning scripts
- Wiki documentation for setup

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [0.3.0] - TBD

### What's New
- Classification table (Dataverse) with schema
- Rule-based classifier
- Classification provider abstraction

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [0.4.0] - TBD

### What's New
- Draft creation with routing block
- Knowledge retrieval integration
- Prepare-send guard

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [0.5.0] - TBD

### What's New
- Classification override workflow
- Dataverse audit tables
- Routing block regeneration

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [0.6.0] - TBD

### What's New
- MCP server integration
- Standardized tool layer
- MCP tools for all operations

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [0.7.0] - TBD

### What's New
- BART classifier
- Foundry/Azure ML deployment
- Multi-label threshold calibration

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [1.0.0] - TBD

### What's New
- Production-ready release
- Complete end-to-end acceptance tests
- Full operational documentation

### What's Fixed
- All known issues resolved

### What's Modified
- N/A

### Breaking Changes
- None

---

## Versioning Rules

- **Major version (0.x.0 → 1.0.0):** Product reaches release-candidate quality.
- **Minor version (0.1.0 → 0.2.0):** New feature or functional element (phases in implementation plan).
- **Patch version (0.2.0 → 0.2.1):** Bug fixes, security patches, documentation updates.

Each PR tied to a phase should be tagged and merged before the next phase begins.
