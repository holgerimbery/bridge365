# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
