# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
- Source documentation: docs/shared-mailbox-classification-master-guide.md

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [0.2.0] - TBD

### What's New
- Removable internal routing block (text and HTML formats)
- Routing block detector and removal function
- Separate cleanup operation (CLI/MCP/connector)
- Configuration: INCLUDE_ROUTING_BLOCK, ROUTING_BLOCK_POSITION, REQUIRE_ROUTING_BLOCK_REMOVAL_BEFORE_SEND
- Prepare-send guard that rejects drafts with block present

### What's Fixed
- N/A

### What's Modified
- Prepare-send behavior: now validates routing block removal

### Breaking Changes
- Prepare-send will reject drafts containing the internal routing block

---

## [0.3.0] - TBD

### What's New
- Pluggable ClassificationProvider protocol/interface
- RuleBasedClassifier wrapper for deterministic logic
- Provider factory and configuration selection
- Provider version tracking in results
- Configuration: CLASSIFICATION_PROVIDER, CLASSIFICATION_MIN_SCORE, CLASSIFICATION_AMBIGUITY_DELTA

### What's Fixed
- N/A

### What's Modified
- Classification output now includes provider and model version

### Breaking Changes
- None (output is backward compatible)

---

## [0.4.0] - TBD

### What's New
- BART zero-shot proof of concept
- Evaluation framework and metrics collection
- Frozen multi-label test set (100+ reviewed messages)
- Decision document: fine-tuning feasibility

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None (research phase; no production code)

---

## [0.5.0] - TBD

### What's New
- Fine-tuned BART multi-label classifier
- Training data export (JSONL format, multi-label)
- Label map with stable modelLabel identifiers
- Threshold calibration logic (global and per-class)
- Model card documenting data, languages, and limitations
- Tests for long-message truncation and language variants

### What's Fixed
- N/A

### What's Modified
- N/A

### Breaking Changes
- None

---

## [0.6.0] - TBD

### What's New
- Foundry BART endpoint deployment
- Azure ML managed online endpoint configuration
- RBAC setup with least-privilege roles
- PowerShell test script for endpoint invocation
- Endpoint monitoring and scaling configuration

### What's Fixed
- N/A

### What's Modified
- Classification provider can now use Foundry-hosted BART

### Breaking Changes
- None (Foundry endpoint is transparent to harnesses)

---

## [0.7.0] - TBD

### What's New
- Copilot Studio MCP integration
- Copilot Studio custom connector operations
- GitHub Copilot executable skill commands
- GitHub Copilot MCP tools
- Harness-specific SKILL.md documentation

### What's Fixed
- N/A

### What's Modified
- All harnesses now support Foundry BART classification

### Breaking Changes
- None (harness APIs are stable)

---

## [0.8.0] - TBD

### What's New
- Fallback orchestration (BART → rules → manual review)
- Durable idempotency and approval replay protection
- Comprehensive audit logging
- Monitoring and alerting for drift
- Human correction tracking for retraining
- Operations runbook

### What's Fixed
- N/A

### What's Modified
- Endpoint failures automatically fall back to deterministic rules

### Breaking Changes
- None

---

## [1.0.0] - TBD

### What's New
- Production-ready release
- Complete end-to-end acceptance tests
- Full operational documentation
- Security review completed
- Performance benchmarks

### What's Fixed
- All known issues resolved

### What's Modified
- N/A

### Breaking Changes
- None (v1.0.0 is stable production release)

---

## Versioning Rules

- **Major version (0.x.0 → 1.0.0):** Product reaches release-candidate quality.
- **Minor version (0.1.0 → 0.2.0):** New feature or functional element (phases in implementation plan).
- **Patch version (0.2.0 → 0.2.1):** Bug fixes, security patches, documentation updates.

Each PR tied to a phase should be tagged and merged before the next phase begins.
