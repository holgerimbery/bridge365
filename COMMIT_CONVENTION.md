# Commit and PR Message Convention

## Structure

All commits and pull requests should follow this format:

\\\
<Type>: <Short summary (imperative mood, 50 chars max)>

<Blank line>

<Body: detailed description, wrapped at 72 chars>

<Blank line>

What's New:
- Feature or capability added (bullet points)

What's Fixed:
- Bug or issue resolved (bullet points)

What's Modified:
- Changes to existing behavior (bullet points)

Breaking Changes:
- Incompatibilities or API changes (or "None")

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
\\\

---

## Types

- **Feature**: A new feature, capability, or functional element.
- **Fix**: A bug fix or issue resolution.
- **Docs**: Documentation updates (no code change).
- **Refactor**: Code restructuring without behavior change.
- **Test**: Test additions or updates.
- **Chore**: Dependency updates, configuration changes.
- **Research**: Investigation or proof-of-concept (no production code).

---

## What's New

Describe features and capabilities added in this change.

**Format:**
- One bullet per item
- Be specific and reference the implementation plan phase if applicable
- Example: "Add routing block generator (text and HTML formats)"

---

## What's Fixed

Describe bugs resolved or issues addressed.

**Format:**
- One bullet per issue
- Reference issue number if available (#123)
- Example: "Fix routing block HTML escaping to prevent XSS"

---

## What's Modified

Describe changes to existing behavior (that are not bug fixes).

**Format:**
- One bullet per modification
- Explain impact on users/operators
- Example: "Prepare-send now validates routing block removal before approval"

---

## Breaking Changes

Describe any incompatibilities, API changes, or behavioral shifts that affect consumers.

**Format:**
- List each breaking change with migration guidance
- If none, write "None"
- Example: "Prepare-send rejects drafts with routing block present (see docs/upgrade-v0.2.md for migration)"

---

## Example: Feature Commit

\\\
Feature: removable internal routing block and cleanup operation

Add a removable HTML block to every classification-generated draft.
The block contains the sender address, all proposed classifications,
departments, and email addresses. A separate cleanup operation allows
reviewers to safely remove the block before sending.

What's New:
- Routing block generator (text and HTML formats)
- Routing block detector (check if present in draft)
- Routing block removal function (safe extraction)
- Cleanup operation as separate CLI/MCP/connector tool
- Configuration: INCLUDE_ROUTING_BLOCK, ROUTING_BLOCK_POSITION, REQUIRE_ROUTING_BLOCK_REMOVAL_BEFORE_SEND
- Prepare-send guard that rejects drafts with the block still present
- Unit tests: zero/single/multiple classification scenarios

What's Fixed:
- None

What's Modified:
- Prepare-send now rejects drafts containing the internal routing block

Breaking Changes:
- Prepare-send will reject drafts with the routing block present

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
\\\

---

## Example: Fix Commit

\\\
Fix: HTML escaping in routing block prevents XSS

The routing block HTML generator was not escaping sender addresses,
classifications, or department names. This could allow untrusted input
from email headers to inject scripts.

What's New:
- None

What's Fixed:
- HTML escape all user-provided values in routing block

What's Modified:
- None

Breaking Changes:
- None

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
\\\

---

## Pull Request Template

Use the same structure for PR descriptions:

\\\markdown
## Summary
<Short description of the PR>

## What's New
- Bullet points

## What's Fixed
- Bullet points (or "None")

## What's Modified
- Bullet points (or "None")

## Breaking Changes
- Incompatibilities (or "None")

## Testing
- How to test this change
- Unit tests included: yes/no
- Integration tests included: yes/no

## Checklist
- [ ] All tests pass
- [ ] Changelog updated
- [ ] Documentation updated (if applicable)
- [ ] Commit messages follow convention
\\\

---

## Phase-Scoped Commits

Each major phase (v0.1.0 → v0.8.0) typically includes one main feature commit plus supporting commits for tests, docs, and fixes.

**Phase 1 Example:**
1. Feature: removable internal routing block... (main)
2. Test: routing block edge cases (supporting)
3. Docs: routing block usage guide (supporting)
4. Fix: prepare-send guard logic (bugfix during development)

All commits within a phase are merged into a single PR, which is tagged with the phase version and merged to main.
