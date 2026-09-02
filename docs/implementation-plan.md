# Email Classification Module — Implementation Plan

**Version:** 0.1.0  
**Last Updated:** 2026-09-02  
**Status:** In Development

---

## Overview

This document outlines the phased implementation of the Incoming Email Classification, Knowledge-Grounded Draft Responses, and Foundry BART module. Each major step introduces a complete functional element that can be independently shipped and versioned.

Source guidance: See docs/shared-mailbox-classification-master-guide.md.

---

## Major Implementation Steps (Feature-Level)

`mermaid
graph TD
    A["Phase 0: Foundation<br/>(v0.1.0)"] --> B["Phase 1: Routing Block<br/>(v0.2.0)"]
    B --> C["Phase 2: Provider Abstraction<br/>(v0.3.0)"]
    C --> D["Phase 3: BART Proof of Concept<br/>(v0.4.0)"]
    D --> E["Phase 4: Fine-Tuning<br/>(v0.5.0)"]
    E --> F["Phase 5: Foundry Deployment<br/>(v0.6.0)"]
    F --> G["Phase 6: Harness Integration<br/>(v0.7.0)"]
    G --> H["Phase 7: Production Controls<br/>(v0.8.0)"]
    H --> I["v1.0.0: Release Candidate"]
`

---

## Detailed Phases

### Phase 0: Foundation (v0.1.0)

**Objective:** Project structure, dependencies, configuration, and base service scaffolding.

**Deliverables:**
- Project layout (src/, tests/, docs/)
- Python environment (dependencies in equirements.txt)
- Configuration schema (.env template and Pydantic models)
- Base service class with dependency injection
- Unit test framework and first test suite
- This implementation plan and changelog

**Success Criteria:**
- Project runs and all tests pass
- Configuration is externalized and validated
- No classification/routing logic yet

**Major PR:** "Foundation: project structure and configuration scaffolding"

---

### Phase 1: Routing Block (v0.2.0)

**Objective:** Add the removable internal routing block to every draft, with detection and cleanup operations.

**Deliverables:**
- Routing block generator (text and HTML)
- Routing block detector (check if present in draft)
- Routing block removal function (safe extraction)
- Configuration: INCLUDE_ROUTING_BLOCK, ROUTING_BLOCK_POSITION, REQUIRE_ROUTING_BLOCK_REMOVAL_BEFORE_SEND
- Prepare-send guard that rejects drafts with the block still present
- Separate cleanup CLI/MCP/connector operation
- Unit tests: zero/single/multiple classification scenarios

**Success Criteria:**
- Every generated draft includes the exact removable block format
- Block contains sender, all classNames, targets, and emails
- Prepare-send rejects drafts with the block still embedded
- Cleanup removes only the marked block and is audited
- All existing functionality remains unchanged

**Major PR:** "Feature: removable internal routing block and cleanup operation"

---

### Phase 2: Provider Abstraction (v0.3.0)

**Objective:** Create a pluggable classification provider interface so the deterministic classifier can be swapped for BART or structured models.

**Deliverables:**
- ClassificationProvider protocol/interface
- RuleBasedClassifier wrapper around existing deterministic logic
- Provider factory and configuration selection
- Unified output schema across all providers
- Provider version tracking in results and audit
- Configuration: CLASSIFICATION_PROVIDER, CLASSIFICATION_MIN_SCORE, CLASSIFICATION_AMBIGUITY_DELTA
- Unit tests for factory and provider selection

**Success Criteria:**
- Rules classifier behaves identically to before
- Provider can be switched via environment configuration
- Output schema is identical regardless of provider
- Model version is captured in every result
- No breaking changes to harness APIs

**Major PR:** "Feature: pluggable classification provider abstraction"

---

### Phase 3: BART Proof of Concept (v0.4.0)

**Objective:** Evaluate a pretrained zero-shot BART model on organization email without fine-tuning.

**Deliverables:**
- Export active classification table labels and reviewed examples
- Setup Hugging Face acebook/bart-large-mnli zero-shot classifier
- Create frozen multi-label test set (100+ reviewed messages)
- Implement zero-shot evaluation script
- Metrics: per-class precision, recall, micro/macro F1, routing-risk rate
- Decision document: is there enough data for fine-tuning?
- Evaluation report stored in docs/evaluations/

**Success Criteria:**
- Zero-shot model runs and produces scores
- Test set is reviewed and frozen
- Metrics are recorded per-class and aggregated
- Clear decision on whether to proceed to fine-tuning

**Major PR:** "Research: BART zero-shot evaluation and proof of concept"

---

### Phase 4: Fine-Tuning (v0.5.0)

**Objective:** Train a custom multi-label BART classifier on organization data.

**Deliverables:**
- Reviewed train/validation/test JSONL files (multi-label format)
- Stable label map using modelLabel field
- Fine-tuning script with multi-label cross-entropy loss
- Threshold calibration logic (global and per-class)
- Training metrics and validation plots
- Model artifact registered and versioned
- Model card with data summary, language coverage, known limitations
- Tests for long-message truncation, language variants, imbalance handling

**Success Criteria:**
- Model trains without errors
- Validation metrics exceed proof-of-concept baseline
- Thresholds are calibrated on validation set
- Model artifact is versioned and reproducible
- Model card documents assumptions and limitations

**Major PR:** "Feature: fine-tuned BART multi-label classifier"

---

### Phase 5: Foundry Deployment (v0.6.0)

**Objective:** Deploy the fine-tuned model to a managed inference endpoint.

**Deliverables:**
- Check Foundry catalog for model availability
- If available: register and deploy via Foundry managed compute
- If not: register artifact and deploy as Azure ML managed online endpoint
- Endpoint configuration: scaling, networking, monitoring
- RBAC roles and identity setup (least privilege)
- Environment variables for endpoint URL and audience
- PowerShell test script for endpoint invocation
- Documentation of consume URL and schema

**Success Criteria:**
- Endpoint is accessible and responds to requests
- Azure RBAC is configured with least-privilege roles
- Endpoint URL and audience are in protected configuration
- Test script successfully invokes the endpoint
- Latency and cost per inference are acceptable

**Major PR:** "Feature: Foundry BART endpoint deployment and configuration"

---

### Phase 6: Harness Integration (v0.7.0)

**Objective:** Wire the deployed BART classifier into the target harness(es).

**Deliverables:**

**For Copilot Studio MCP:**
- Configure MCP service to use CLASSIFICATION_PROVIDER=foundry-bart
- MCP tools: classify_incoming_email, create_grounded_response_draft, emove_internal_routing_block
- Grant MCP workload identity permission to invoke endpoint

**For Copilot Studio custom connector:**
- OpenAPI spec additions for classification, draft, cleanup operations
- Connector implementation without model endpoint credentials

**For GitHub Copilot executable skill:**
- CLI commands: classify-email, create-response-draft, emove-routing-block
- SKILL.md documentation with usage examples

**For GitHub Copilot MCP:**
- Reuse same MCP tools as Copilot Studio path

**Common:**
- Integration tests for each harness
- No harness receives model endpoint credentials directly

**Success Criteria:**
- Each harness can classify a test email without errors
- BART endpoint is only invoked from the service/MCP layer
- Harnesses never receive endpoint credentials
- Multi-label results are correctly handled in all paths
- Existing prepare-send and approval flows remain unchanged

**Major PR:** "Feature: Harness integration for BART classification"

---

### Phase 7: Production Controls (v0.8.0)

**Objective:** Add monitoring, fallback, audit, and safety controls for production use.

**Deliverables:**
- Fallback orchestration (BART → deterministic rules → manual review)
- Routing block removal guard enforced before send
- Durable idempotency and approval replay protection
- Audit logging: provider, model version, classifications, corrections
- Monitoring: endpoint latency, availability, drift, class distribution
- Human correction tracking for controlled retraining
- Evaluation re-run trigger logic
- Dataverse integration (optional) for classification audit trail
- Documentation of operations runbook

**Success Criteria:**
- Endpoint unavailability automatically falls back to deterministic rules
- Auto-send remains disabled; human approval is mandatory
- All decisions are auditable with timestamps and versions
- Monitoring alerts trigger on drift or degradation
- Human corrections feed into retraining pipeline

**Major PR:** "Feature: production controls, monitoring, and audit trail"

---

### Phase 8: Release Candidate (v1.0.0)

**Objective:** Stabilize, document, and prepare for production release.

**Deliverables:**
- All phases complete and tested
- End-to-end acceptance tests pass
- Documentation complete: architecture, operations, troubleshooting
- Security review completed
- Performance benchmarks documented
- Changelog fully up-to-date
- CONTRIBUTING guide for future maintenance

**Success Criteria:**
- All acceptance criteria from all phases are met
- No known critical or high-severity issues
- Ready for production deployment

**Major PR:** "Release: v1.0.0 production candidate"

---

## Version Increment Strategy

| Version Range | Trigger | Change Type |
|---|---|---|
|  .1.0 →  .2.0 | New feature or element adds functionality | Minor |
|  .2.1 | Bug fix, security patch, documentation | Patch |
|  .1.0 → 1.0.0 | Feature complete, production-ready | Major |

**Rules:**
- **Major:** Product at release-candidate quality; significant architecture changes.
- **Minor:** New feature, element, or capability (phases in this plan).
- **Patch:** Bug fixes, documentation, non-breaking refactors.

---

## Commit and PR Message Convention

Every commit tied to a major phase should follow this structure:

\\\
<Type>: <Short summary>

What's New:
- Describe new features or capabilities added.

What's Fixed:
- Describe bugs or issues resolved.

What's Modified:
- Describe changes to existing behavior.

Breaking Changes:
- None. (or describe incompatibilities)

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
\\\

**Examples:**

\\\
Feature: removable internal routing block and cleanup operation

What's New:
- Add routing block generator (text and HTML formats)
- Add routing block detector
- Add cleanup operation as separate CLI/MCP/connector tool
- Add REQUIRE_ROUTING_BLOCK_REMOVAL_BEFORE_SEND guard to prepare-send

What's Fixed:
- N/A

What's Modified:
- Prepare-send now rejects drafts containing the internal routing block

Breaking Changes:
- None.
\\\

---

## References

- Source: docs/shared-mailbox-classification-master-guide.md
- Changelog: CHANGELOG.md
- Commit conventions: See commit messages in this repo
