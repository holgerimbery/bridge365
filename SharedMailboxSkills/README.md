# SharedMailboxSkills (GitHub Copilot Harness - Executable Skills)

(c) 2026 Holger Imbery (contact@holgerimbery.blog). Licensed under the project LICENSE file.

This folder contains the artifacts needed to create the `SharedMailboxSkills` executable
skill set in Copilot Studio, used by the GitHub Copilot harness (parallel to the
[custom connector](../custom-connector) used by the standard harness) to call the
[backend service](../backend-service).

## Contents

- `skills.json` - Declarative definition of the skill's three actions (`FetchMessage`,
  `ClassifyMessage`, `CreateDraft`), their inputs/outputs, and the backend HTTP call
  each action maps to.

## Step 1: Create Executable Skills in Copilot Studio

1. Open **Copilot Studio**
2. Click your **agent**
3. Click **Skills** (left sidebar)
4. Click **Create new skill**
5. Name: `SharedMailboxSkills`
6. Description: `Shared mailbox classification and draft management`

## Step 2: Add Skill Actions

Add the three actions defined in `skills.json`:

- **FetchMessage** - input: `mailboxAddress`, `messageId` -> output: `message`
- **ClassifyMessage** - input: `mailboxAddress`, `messageId` -> output: `classifications`
- **CreateDraft** - input: `mailboxAddress`, `messageId`, `subject`, `body` -> output: `draftId`, `draftUrl`

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
  Body: { "messageId", "subject", "body", "classifications" }
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
