# Email Classification Module — Implementation Plan

**Version:** 0.1.1  
**Last Updated:** 2026-09-02  
**Status:** In Development

---

## Overview

This document outlines the phased implementation of the shared mailbox email classification and drafting module for Microsoft Power Platform environments. Implementation is built around a **Copilot Studio custom connector** for all phases.

Source guidance: See `docs/shared-mailbox-classification-master-guide.md`.

---

## Major Implementation Steps (Feature-Level)

```mermaid
graph TD
    A["Phase 0: Foundation<br/>(v0.1.0)"] --> B["Phase 1: Shared Mailbox<br/>Custom Connector (v0.2.0)"]
    B --> C["Phase 2: Classification via Dataverse Table<br/>(v0.5.0)"]
    C --> D["Phase 3: Draft Creation<br/>& Routing (v0.6.0)"]
    D --> E["Phase 4: Override/Change<br/>Classification (v0.5.0)"]
    E --> F["Phase 5: MCP Server<br/>Integration (v0.6.0)"]
    F --> G["Phase 6: BART Classifier<br/>(v0.7.0)"]
    G --> H["v1.0.0: Release Candidate"]
```

---

## Detailed Phases

### Phase 0: Foundation (v0.1.0)

**Objective:** Project structure, dependencies, configuration, and base service scaffolding.

**Deliverables:**
- Project layout (src/, tests/, docs/, docs/wiki/)
- Python environment (dependencies in `requirements.txt`)
- Configuration schema (`.env` template and Pydantic models)
- Base service class with dependency injection
- Unit test framework
- This implementation plan, changelog, and wiki module structure

**Success Criteria:**
- Project runs and all tests pass
- Configuration is externalized and validated
- Wiki structure is ready for phase documentation

**Major PR:** "Foundation: project structure, configuration, and wiki scaffolding"

---

### Phase 1: Shared Mailbox Custom Connector (v0.2.0)

**Objective:** Build the core shared mailbox service and Copilot Studio custom connector.

**Deliverables:**

**Shared Mailbox Service (core):**
- Microsoft Graph mailbox client
- Message fetching and iteration
- Webhook/subscription handling
- Configuration for shared mailbox address and permissions

**Copilot Studio Custom Connector:**
- Custom connector OpenAPI spec (endpoints for mailbox operations)
- Connector actions for message retrieval and draft management
- Authentication (workload identity / Entra)
- Connector operations stubs (to be filled in later phases)

**Wiki & Documentation:**
- `docs/wiki/phase-1-mailbox-setup.md` — human-readable Copilot Studio setup guide
- `custom-connector/openapi.yaml` - Connector definition
- `backend-service/`, `custom-connector/` - Deployable artifacts and setup guides
- Mermaid diagrams for message fetching flow

**Success Criteria:**
- Connector can authenticate and fetch messages from shared mailbox
- Connector operations are registered in OpenAPI spec
- Wiki includes step-by-step Copilot Studio setup
- PowerShell scripts automate connector registration

**Major PR:** "Feature: Shared mailbox custom connector (Phase 1)"

---

### Phase 2: Classification via Dataverse Table (v0.5.0)

**Objective:** Store classification rules and audit results in Dataverse, and classify messages via a Copilot Studio Prompt tool.

**Deliverables:**

**Classification Rule & Audit Tables:**
- Dataverse Classification Rule table (classificationruleid, classname, classexamples, classtarget, classtargetemail, isactive, priority, modellabel)
- Dataverse Classification Audit table (classificationauditid, messageid, classificationresult, provider, modelversion, confidence, needshumanreview, classificationruleid lookup)
- Classification output schema (classifications[], needsHumanRoutingDecision, confidence, provider, modelVersion)

**Copilot Studio Prompt Tool:**
- Prompt tool (Generative AI action) classifies message text against the active Classification Rule rows, with or without a wrapping Flow
- Result written to the Classification Audit table via the Dataverse connector
- Planned follow-up: swap in a Foundry-hosted model (e.g. BART-MNLI) behind the same Prompt tool/schema

**Wiki & Documentation:**
- `docs/wiki/phase-2-classification-table.md` — table setup and Prompt tool design
- `dataverse/schemas/classification-rule.schema.json`, `classification-audit.schema.json` — table column templates
- `dataverse/scripts/deploy-dataverse-tables.ps1` — Dataverse table provisioning (idempotent Web API deployment)
- `dataverse/scripts/seed-sample-classifications.ps1` — Sample classification data
- Mermaid diagram: classification flow

**Success Criteria:**
- Classification Rule and Audit tables created in Dataverse with sample data
- Prompt tool returns all matching classes for a test message
- Multi-class results are handled correctly
- PowerShell scripts automate table setup

**Major PR:** "Feature: Classification via Dataverse table and Copilot Studio Prompt tool (Phase 2)"

---

### Phase 3: Draft Creation & Routing (v0.6.0)

**Objective:** Give a Copilot Studio agent Microsoft Graph mailbox-routing
capabilities to act on a message after classification - categorize, move,
track changes, read attachments, and stash routing metadata - building on
the reply-draft creation/update/send capabilities already delivered in
Phase 1 (`CreateDraft` with `replyAll`, `UpdateDraft`, `SendDraftMessage`).

**Deliverables:**

**Backend Service (`backend-service/app.py`):**
- `PATCH /api/mailbox/messages/{id}/categories` — set/replace Outlook categories
- `POST /api/mailbox/messages/{id}/move` — move a message to another mail folder
- `GET /api/mailbox/messages/delta` — Graph delta query for incremental sync (additive to the existing `poll` timestamp-filter trigger, not a replacement)
- `GET /api/mailbox/messages/{id}/attachments`, `GET /api/mailbox/messages/{id}/attachments/{attachmentId}` — list/read attachments
- `GET`/`PATCH /api/mailbox/messages/{id}/extended-properties` — read/write Graph `singleValueExtendedProperties` for internal routing metadata

**Copilot Studio Custom Connector:**
- Connector operations: `UpdateMessageCategories`, `MoveMessage`, `GetMessagesDelta`, `GetAttachments`, `GetAttachment`, `GetExtendedProperty`, `SetExtendedProperty`
- `CreateDraft`/`UpdateDraft`/`SendDraftMessage` (Phase 1) cover createReply/createReplyAll/send — no new operations needed for those

**Wiki & Documentation:**
- `docs/wiki/phase-3-draft-creation.md` — setup, PowerShell test snippets, and connector test steps for each new operation
- Integration Test: End-to-End section (categorize → move → verify via delta → read attachments → set extended property)

**Success Criteria:**
- Categories can be set on a real Inbox message and confirmed via Graph
- A message can be moved to a target folder and re-located via its new id
- Delta query returns a usable `@odata.deltaLink`/`@odata.nextLink` for incremental sync
- Attachments (list and single, with content) can be retrieved
- Extended properties round-trip (write then read back the same value)

**Major PR:** "Feature: Draft creation & mailbox routing - categories, move, delta, attachments, extended properties (Phase 3)"

---

### Phase 4: Override/Change Classification (v0.5.0)

**Objective:** Allow reviewers to accept, reject, or override automated classifications before sending.

**Deliverables:**

**Override Workflow:**
- Dataverse classification audit records (proposed and final classifications)
- Override table that captures reviewer decisions and comments
- Rebuild routing block after override
- Invalidate prior prepare-send approval on override

**Copilot Studio Custom Connector:**
- Connector operations: `GetClassificationRecord`, `SetClassificationOverride`, `RebuildRoutingBlock`
- Model-driven app form (optional) for classification review UI

**Wiki & Documentation:**
- `docs/wiki/phase-4-override-workflow.md` — override and approval workflow
- `docs/wiki/scripts/test-override-workflow.ps1` — Test override and rebuild
- Mermaid state diagram: classification workflow (proposed → review → override? → final → send)

**Success Criteria:**
- Reviewers can view all proposed classifications and change them
- Override comment is mandatory
- Routing block is regenerated with final classifications
- Prepare-send approval is invalidated after override
- Audit trail captures all changes

**Major PR:** "Feature: Classification override and workflow control (Phase 4)"

---

### Phase 5: MCP Server Integration (v0.6.0)

**Objective:** Add MCP server layer for standardized tool invocation.

**Deliverables:**

**MCP Server:**
- Implement MCP tools for all mailbox operations:
  - `fetch_incoming_message`
  - `classify_incoming_email`
  - `retrieve_answer_knowledge`
  - `create_grounded_response_draft`
  - `get_classification_processing_record`
  - `set_classification_override`
  - `rebuild_draft_routing_block`
  - `remove_internal_routing_block`
- Tool schemas with input validation
- Error handling and retry logic

**Copilot Studio Custom Connector:**
- MCP integration (connect connector actions to MCP server)
- Agents can invoke MCP tools directly

**Wiki & Documentation:**
- `docs/wiki/phase-5-mcp-integration.md` — MCP server architecture and tool schemas
- `docs/wiki/scripts/start-mcp-server.ps1` — Start MCP server for local testing
- Mermaid diagram: tool call flow (connector → MCP server → backend service)

**Success Criteria:**
- MCP server starts and exposes all tools
- Tool schemas are complete and validated
- Error responses are informative

**Major PR:** "Feature: MCP server and standardized tool layer (Phase 5)"

---

### Phase 6: BART Classifier (v0.7.0)

**Objective:** Add machine learning classifier option (Foundry BART or Azure ML).

**Deliverables:**

**BART Classifier:**
- Foundry BART endpoint deployment (or Azure ML managed online endpoint)
- Classification provider factory (switch between rules and BART)
- Configuration: `CLASSIFICATION_PROVIDER=foundry-bart`, `BART_ENDPOINT`, `BART_AUDIENCE`
- Multi-label score processing and threshold calibration
- Fallback to rules if BART endpoint fails

**Copilot Studio Custom Connector:**
- MCP tool `classify_incoming_email` auto-selects provider based on config
- No connector-level changes needed; provider is transparent

**Wiki & Documentation:**
- `docs/wiki/phase-6-bart-classifier.md` — BART model training, deployment, and evaluation
- `docs/wiki/scripts/deploy-bart-endpoint.ps1` — Foundry/Azure ML deployment script
- `docs/wiki/scripts/evaluate-bart.ps1` — Evaluation and metrics collection
- Python training script reference (transformers + multi-label setup)

**Success Criteria:**
- BART endpoint is deployed and responsive
- Classification provider factory selects BART correctly
- Multi-label thresholds are calibrated
- Fallback to rules works on endpoint failure
- Evaluation metrics are documented

**Major PR:** "Feature: BART machine learning classifier and Foundry deployment (Phase 6)"

---

### Phase 7: Release Candidate (v1.0.0)

**Objective:** Stabilize, test, and prepare for production release.

**Deliverables:**
- All phases complete and tested
- End-to-end acceptance tests
- Complete wiki documentation
- Security review and hardening
- Operations runbook and monitoring setup
- Performance benchmarks

**Success Criteria:**
- All acceptance criteria from all phases are met
- No known critical or high-severity issues
- Ready for production deployment

**Major PR:** "Release: v1.0.0 production candidate"

---

## Version Increment Strategy

| Version Range | Trigger | Change Type |
|---|---|---|
| `0.1.0` → `0.2.0` | New feature or element adds functionality | Minor |
| `0.2.1` | Bug fix, security patch, documentation | Patch |
| `0.1.0` → `1.0.0` | Feature complete, production-ready | Major |

**Rules:**
- **Major:** Product at release-candidate quality.
- **Minor:** New feature, element, or capability (phases in this plan).
- **Patch:** Bug fixes, documentation, non-breaking refactors.

---

## Commit and PR Message Convention

Every commit tied to a major phase should follow this structure:

```
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
```

---

## Wiki Module Structure

All human-readable documentation is stored under `docs/wiki/` as a self-contained module:

- `docs/wiki/index.md` — overview and navigation
- `docs/wiki/phase-<N>-<topic>.md` — per-phase setup guides
- `docs/wiki/scripts/` — PowerShell helper scripts
- `docs/wiki/diagrams/` — Mermaid diagram sources

Each phase wiki includes:
- Step-by-step Copilot Studio/Azure setup instructions
- PowerShell scripts with full copyright and license headers
- Mermaid diagrams illustrating workflows

---

## Copyright & License

All code and documentation in this repository includes copyright headers:

```
(c) 2026 Holger Imbery (contact@holgerimbery.blog)
Licensed under [LICENSE FILE]
```

---

## Next Steps

1. Implement Phase 0 (already v0.1.0).
2. Implement Phase 1 (Shared Mailbox Skill + Connector) → tag `v0.2.0`.
3. Implement Phase 2 (Classification via Dataverse Table) → tag `v0.5.0`.
4. Continue sequentially through Phase 6 → tag `v1.0.0`.

---

## References

- Source: `docs/shared-mailbox-classification-master-guide.md`
- Changelog: `CHANGELOG.md`
- Commit conventions: `COMMIT_CONVENTION.md`
- Wiki: `docs/wiki/`
