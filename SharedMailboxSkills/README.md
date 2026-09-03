# SharedMailboxSkills (GitHub Copilot Harness - Executable Skills)

(c) 2026 Holger Imbery (contact@holgerimbery.blog). Licensed under the project LICENSE file.

This folder contains the artifacts needed to create the `SharedMailboxSkills` executable
skill set in Copilot Studio, used by the GitHub Copilot harness (parallel to the
[custom connector](../custom-connector) used by the standard harness) to call the
[backend service](../backend-service).

## Contents

- `skills.json` - Declarative definition of the skill's six actions (`FetchMessage`,
  `ClassifyMessage`, `CreateDraft`, `UpdateDraft`, `SendMessage`, `SendDraftMessage`), their
  inputs/outputs, and the backend HTTP call each action maps to.

## Step 1: Create Executable Skills in Copilot Studio

1. Open **Copilot Studio**
2. Click your **agent**
3. Click **Skills** (left sidebar)
4. Click **Create new skill**
5. Name: `SharedMailboxSkills`
6. Description: `Shared mailbox classification and draft management`

## Step 2: Add Skill Actions

Add the six actions defined in `skills.json`:

- **FetchMessage** - input: `mailboxAddress`, `messageId` -> output: `message`
- **ClassifyMessage** - input: `mailboxAddress`, `messageId` -> output: `classifications`
- **CreateDraft** - input: `mailboxAddress`, `messageId`, `subject`, `body`, `replyAll` (optional) -> output: `draftId`, `subject`, `draftUrl`. Creates the draft directly in the **shared mailbox's** own Drafts folder (via Graph `createReply`/`createReplyAll`) - never in a user's personal mailbox.
- **UpdateDraft** - input: `mailboxAddress`, `draftId`, `subject` (optional), `body` (optional), `to` (optional) -> output: `draftId`, `subject`, `draftUrl`. Edits an existing shared-mailbox draft (e.g. one created by `CreateDraft`) before it is sent.
- **SendMessage** - input: `mailboxAddress`, `to`, `subject`, `body` -> output: `status`
- **SendDraftMessage** - input: `mailboxAddress`, `draftId` -> output: `status`, `draftId`

## Step 3: Implement Actions (Call Backend)

For each action, add an HTTP call to your backend using the `http` block in
`skills.json`:

```
FetchMessage:
  HTTP GET -> https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/messages/{messageId}?mailboxAddress={mailboxAddress}
  Headers: Authorization: Bearer <token>

ClassifyMessage:
  HTTP POST -> https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/classify
  Body: { "messageId": "{messageId}" }

CreateDraft:
  HTTP POST -> https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/drafts
  Body: { "mailboxAddress", "messageId", "subject", "body", "replyAll" }

UpdateDraft:
  HTTP PATCH -> https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/drafts/{draftId}
  Body: { "mailboxAddress", "subject", "body", "to" }

SendMessage:
  HTTP POST -> https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/messages/send
  Body: { "mailboxAddress", "to", "subject", "body" }

SendDraftMessage:
  HTTP POST -> https://shared-mailbox-classifier.azurewebsites.net/api/mailbox/drafts/{draftId}/send
  Body: { "mailboxAddress" }
```

## Step 4: Test Executable Skills

In your Copilot Studio agent:

1. Add a **Topic** that uses the **SharedMailboxSkills**
2. Add a step: Call **FetchMessage** skill
3. Set inputs: mailboxAddress = `shared@company.com`, messageId = `<known-id>`
4. **Test** the agent

**Expected output:**
```
Message retrieved:
  Subject: Invoice for August
  From: sender@external.com
  Received: 2026-09-02 10:30 AM
```

## Step 5: Trigger the Agent Autonomously with a Copilot Studio Workflow

Steps 1-4 above build a **conversational** skill set - something a Topic (or a chat
user) calls on demand. To have the shared mailbox processed **automatically the
moment a new email arrives**, use Copilot Studio's native **Workflows** feature
instead of building any external automation. Workflows are event-driven: they start
from a **trigger** (schedule, or a connector event) and run to completion with no one
watching, and can hand a step to an **Agent node** that reasons over the trigger data
and calls tools/skills to get the work done. This is the recommended way to run the
GitHub Copilot harness autonomously - no GitHub Actions, Direct Line, or other
external orchestration is needed.

> Reference: [Microsoft Copilot Studio Labs - Workflows](https://microsoft.github.io/mcs-labs/labs/mcs-workflows/)

### 5.1 Create the workflow and configure its trigger

1. In **Copilot Studio**, go to the environment that hosts your agent and select
   **Workflows** in the left navigation (next to **Agents**), then **+ New workflow**.
2. Rename it from **Untitled Workflow** to something like `Shared Mailbox Trigger`.
3. Select the **Start** trigger node, change **Trigger type** from **Manual** to
   **Connector**, then choose **Select trigger...** and pick one of:
   - **Office 365 Outlook - "When a new email arrives (V3)"**, scoped to the shared
     mailbox and, if needed, a specific folder - the built-in, no-code option; or
   - The **custom connector's** `NewMessageReceived` trigger added in v0.4.1 (see
     `../custom-connector/README.md`) - preferred when the app-only Graph
     permissions/allowlisted app policy already restrict access to only the shared
     mailbox, since it reuses that same access path instead of a delegated Outlook
     connection.
4. When prompted, **Create new connection** and sign in with the account that has
   access to the shared mailbox (or, for the custom-connector trigger, the account
   used to authorize the connector).

### 5.2 Add an Agent node that runs the shared mailbox skills

1. Select the **+** after the trigger and choose **Agent** to add an agent node.
2. Leave **New agent for this workflow** selected (or point it at an existing
   published agent that already has the `SharedMailboxSkills` skill/actions added).
3. Under **Tools**, add the actions from `skills.json` the agent needs -
   **FetchMessage**, **ClassifyMessage**, and **CreateDraft** at minimum, plus
   **SendMessage** and/or **SendDraftMessage** if the agent should also be able to
   send a reply/new message rather than only draft one.
4. In the **Instructions** box, describe the goal and reference the trigger's data
   with the **`/`** dynamic-content token so the agent acts on the actual message,
   for example:

   ```
   A new email arrived in the shared mailbox with message ID /Id (from
   "When a new email arrives"). Fetch the message, classify it, and create a
   reply draft addressed to the sender using the classification result.
   Only create one draft per message. Do not send it automatically - use
   SendDraftMessage only if a human reviewer has approved the draft.
   ```

5. **Save**, then **Publish** the workflow - a workflow only listens for its trigger
   once published.

### 5.3 Test the workflow

1. Send a test email to the shared mailbox.
2. In the workflow's **Activity** tab, select **Refresh** until the run appears
   (connector-based triggers poll on a schedule, so this can take a few minutes).
3. Open the run to watch it execute **Trigger -> Agent** node-by-node, and expand the
   **Agent** node to see its narration of calling **FetchMessage**, **ClassifyMessage**,
   and **CreateDraft**.
4. Confirm a draft reply was created in the shared mailbox, addressed appropriately
   for the classified category.
