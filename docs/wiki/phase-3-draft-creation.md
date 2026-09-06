# Phase 3: Draft Creation & Routing

**Objective:** Give a Copilot Studio agent the mailbox-routing capabilities it
needs after classification - tag a message with categories, move it to a
department folder, track changes via delta query, read attachments, and
stash routing metadata directly on the Graph message via extended
properties. Reply drafting and sending (createReply/createReplyAll/send)
were already delivered in Phase 1 - see the "Already Available" section
below.

> **Not to be confused with Phase 2's `DraftEmailBody` routing block:**
> Phase 2's Prompt tool ([`phase-2-classification-table.md`, Section
> 4.2](phase-2-classification-table.md#42-example-draftemailbody-prompt-tool))
> generates an HTML "routing block" *inside the reply draft's body* -
> a human-reviewable table of classifications, meant to be read and removed
> by a reviewer before sending. This phase's routing capabilities
> (categories, move, extended properties) are a different, machine-actionable
> mechanism - they act directly on the Graph message/mailbox itself (visible
> in Outlook, queryable via Graph), independent of whatever draft body is
> attached to it. The two are complementary, not overlapping: use Phase 2's
> routing block so a human reviewer sees the routing decision before
> sending, and this phase's operations so the mailbox itself reflects that
> decision (tagged, filed, and annotated) regardless of what happens to any
> draft.

**Harness:** Same Flask backend service (`backend-service/app.py`) and
`SharedMailboxConnector` custom connector as Phase 1 - this phase only adds
new routes/operations to both, no new infrastructure.

---

## 0. Already Available (Phase 1, no change here)

These operations already exist and are not duplicated by this phase:

| Capability | Connector Operation | Backend Route |
|---|---|---|
| Create a reply draft (or reply-all) | `CreateDraft` (`replyAll: true/false`) | `POST /api/mailbox/drafts` |
| Update a draft before sending | `UpdateDraft` | `PATCH /api/mailbox/drafts/{draftId}` |
| Send an existing draft | `SendDraftMessage` | `POST /api/mailbox/drafts/{draftId}/send` |

`CreateDraft` intentionally stays a single operation with a `replyAll`
boolean flag rather than two separate `CreateReply`/`CreateReplyAll`
operations - both call the same Graph `createReply`/`createReplyAll` action
and PATCH pattern, so splitting them would just duplicate the same backend
logic under two operationIds with no behavioral difference.

---

## 1. Categories: `UpdateMessageCategories`

Sets (replaces, not merges) a message's Outlook categories - e.g. tag it with
a department name right after classification, so the routing decision is
visible directly in Outlook, not just in Dataverse's Classification Audit
table (Phase 2).

**Backend:** `PATCH /api/mailbox/messages/{messageId}/categories`
**Graph mapping:** `PATCH /users/{mailbox}/messages/{id}` with body
`{"categories": ["Finance", "Urgent"]}`

```powershell
$Body = @{ mailboxAddress = $MailboxAddress; categories = @("Finance", "Urgent") } | ConvertTo-Json
Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/$MessageId/categories" `
    -Method Patch -Body $Body -ContentType "application/json"
```

**Expected output:** `{ "messageId": "...", "categories": ["Finance", "Urgent"] }`

---

## 2. Move: `MoveMessage`

Moves a message to a different mail folder - e.g. route it to a department
subfolder after classification.

**Backend:** `POST /api/mailbox/messages/{messageId}/move`
**Graph mapping:** `POST /users/{mailbox}/messages/{id}/move` with body
`{"destinationId": "<folderId or wellKnownName>"}`

### Finding a `destinationId`: `GetMailFolders`

`destinationId` accepts two kinds of value:

- A **Graph well-known folder name** - `inbox`, `archive`, `deleteditems`,
  `drafts`, `sentitems`, `junkemail`, `outbox` - use these directly, no
  lookup needed.
- A **real folder id** - required for anything else (e.g. a custom
  department subfolder), looked up with `GetMailFolders`.

**Backend:** `GET /api/mailbox/folders`
**Graph mapping:** `GET /users/{mailbox}/mailFolders` (top-level folders) or
`GET /users/{mailbox}/mailFolders/{parentFolderId}/childFolders` (one level
of children) - Graph does not return nested folders in a single call, so
reaching a subfolder several levels deep means walking down one
`parentFolderId` at a time.

```powershell
# Top-level folders (Inbox, Archive, Sent Items, any custom top-level folders...)
$Folders = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/folders?mailboxAddress=$MailboxAddress" -Method Get
$Folders.value | Select-Object id, displayName, childFolderCount

# A department subfolder nested under Inbox - find Inbox's id above, then:
$InboxId = ($Folders.value | Where-Object { $_.displayName -eq "Inbox" }).id
$Children = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/folders?mailboxAddress=$MailboxAddress&parentFolderId=$InboxId" -Method Get
$Children.value | Select-Object id, displayName
```

**Expected output:** `{ "value": [ { "id": "...", "displayName": "Finance", "parentFolderId": "...", "childFolderCount": 0 }, ... ] }` -
use the matching folder's `id` as `MoveMessage`'s `destinationId`.

> **Gotcha:** Graph assigns the moved message a **new id** in the destination
> folder. The original `messageId` stops resolving once the move completes -
> use `movedMessageId` from the response for any further operation
> (categories, extended properties, attachments) on this message.

```powershell
$Body = @{ mailboxAddress = $MailboxAddress; destinationId = "archive" } | ConvertTo-Json
Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/$MessageId/move" `
    -Method Post -Body $Body -ContentType "application/json"
```

**Expected output:** `{ "movedMessageId": "...", "destinationId": "archive" }`

---

## 3. Delta Query: `GetMessagesDelta`

Graph delta query for change tracking on the Inbox (new/changed/deleted
messages since a checkpoint) - for incremental sync use cases.

**Backend:** `GET /api/mailbox/messages/delta`
**Graph mapping:** `GET /users/{mailbox}/mailFolders/inbox/messages/delta`

This is a **new, separate capability** from the existing `NewMessageReceived`
polling trigger (`/api/mailbox/messages/poll`), which filters on
`receivedDateTime gt {since}` - a simple timestamp comparison that can miss
edits/deletes and is vulnerable to clock skew. `GetMessagesDelta` instead
uses Graph's real delta-token protocol. Neither replaces the other; use
`NewMessageReceived` for the autonomous-agent trigger and `GetMessagesDelta`
for an explicit incremental-sync call from a topic.

```powershell
# First call - starts a fresh delta over the Inbox
$Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/delta?mailboxAddress=$MailboxAddress" -Method Get
$Response.value | Select-Object id, subject

# Persist whichever link came back...
$DeltaLink = $Response.'@odata.deltaLink'
if (-not $DeltaLink) { $DeltaLink = $Response.'@odata.nextLink' }

# ...and pass it back on the next call to resume from that checkpoint
$Next = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/delta?mailboxAddress=$MailboxAddress&deltaLink=$([uri]::EscapeDataString($DeltaLink))" -Method Get
```

**Expected output:** Graph's raw delta payload - `value` (array of changed
messages) plus `@odata.nextLink` (more pages to fetch) or `@odata.deltaLink`
(caught up - save this as the next checkpoint).

---

## 4. Attachments: `GetAttachments` / `GetAttachment`

Reads a message's attachments - e.g. to inspect an invoice PDF as part of
routing/classification.

**Backend:** `GET /api/mailbox/messages/{messageId}/attachments` (list,
metadata only) and `GET /api/mailbox/messages/{messageId}/attachments/{attachmentId}`
(single attachment, includes base64 `contentBytes` for file attachments).
**Graph mapping:** `GET /users/{mailbox}/messages/{id}/attachments` and
`GET /users/{mailbox}/messages/{id}/attachments/{attachmentId}`.

```powershell
$Attachments = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/$MessageId/attachments?mailboxAddress=$MailboxAddress" -Method Get
$Attachments.value | Select-Object id, name, contentType, size

$AttachmentId = $Attachments.value[0].id
Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/$MessageId/attachments/$AttachmentId`?mailboxAddress=$MailboxAddress" -Method Get
```

**Expected output (list):** array of `{ id, name, contentType, size }`.
**Expected output (single):** the same object plus `contentBytes` (base64)
for file attachments; absent for other attachment types (e.g.
`itemAttachment`, `referenceAttachment`).

---

## 5. Extended Properties: `GetExtendedProperty` / `SetExtendedProperty`

Stashes or reads internal routing/classification metadata directly on the
Graph message object (in addition to, not instead of, the Dataverse
Classification Audit table from Phase 2) - useful when the metadata needs to
travel with the message itself (e.g. survive a mailbox export, or be visible
to another tool reading Graph directly).

**Backend:** `GET`/`PATCH /api/mailbox/messages/{messageId}/extended-properties`
**Graph mapping (read):** `GET /users/{mailbox}/messages/{id}?$expand=singleValueExtendedProperties($filter=id eq 'String {GUID} Name propertyName')`
**Graph mapping (write):** `PATCH /users/{mailbox}/messages/{id}` with body
`{"singleValueExtendedProperties": [{"id": "String {GUID} Name propertyName", "value": "..."}]}`

`propertyGuid` is any stable GUID you choose to namespace the property (Graph
has no bare-name extended properties) - pick one GUID per logical property
and reuse it for both reads and writes. For example:

```powershell
$PropertyGuid = "12345678-1234-1234-1234-123456789012"
$PropertyName = "RoutingDepartment"

# Write
$Body = @{ mailboxAddress = $MailboxAddress; propertyGuid = $PropertyGuid; propertyName = $PropertyName; value = "Finance" } | ConvertTo-Json
Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/$MessageId/extended-properties" `
    -Method Patch -Body $Body -ContentType "application/json"

# Read it back
Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/$MessageId/extended-properties?mailboxAddress=$MailboxAddress&propertyGuid=$PropertyGuid&propertyName=$PropertyName" -Method Get
```

**Expected output:** `{ "messageId": "...", "propertyId": "String {12345678-1234-1234-1234-123456789012} Name RoutingDepartment", "value": "Finance" }`
(`value: null` on read if the property was never set).

---

## 6. Copilot Studio Custom Connector Setup

Add the eight new operations to the connector the same way as Phase 1 (see
[`docs/wiki/phase-1-mailbox-setup.md`, Step 5.3](phase-1-mailbox-setup.md#step-53-add-api-operations)):
regenerate `custom-connector/openapi.yaml` from the updated
`openapi.template.yaml` (`.\custom-connector\scripts\generate-openapi.ps1`),
then re-import/update the connector definition (portal wizard **Edit** ->
**Swagger Editor**, or re-run `deploy-connector.ps1` for the CLI path).

Test each operation in the connector's **Test** tab (same authenticated
connection as Phase 1 - see
[Step 5.4](phase-1-mailbox-setup.md#step-54-configure-authentication)):

#### 1. GetMailFolders
- mailboxAddress: `shared@company.com`
- parentFolderId: (leave empty to list top-level folders)
- **Expected:** array of `{ id, displayName, parentFolderId, childFolderCount }` - copy the target department folder's `id` for `MoveMessage` below

#### 2. UpdateMessageCategories
- messageId: `<inboxMessageId>` (from a real Inbox message - see Phase 1 Step 5.5.1)
- body: mailboxAddress `shared@company.com`, categories `["Finance", "Urgent"]`
- **Expected:** `{ "messageId": "...", "categories": ["Finance", "Urgent"] }`

#### 3. MoveMessage
- messageId: `<inboxMessageId>`
- body: mailboxAddress `shared@company.com`, destinationId `archive` (or a folder `id` from `GetMailFolders` above)
- **Expected:** `{ "movedMessageId": "...", "destinationId": "archive" }` - copy `movedMessageId` for later steps

#### 4. GetMessagesDelta
- mailboxAddress: `shared@company.com`
- deltaLink: (leave empty on first call)
- **Expected:** `{ "value": [...], "@odata.deltaLink" or "@odata.nextLink": "..." }`

#### 5. GetAttachments
- messageId: `<movedMessageId>` (or any message with attachments)
- mailboxAddress: `shared@company.com`
- **Expected:** array of attachment metadata objects

#### 6. GetAttachment
- messageId: `<movedMessageId>`, attachmentId: `<id from GetAttachments>`
- mailboxAddress: `shared@company.com`
- **Expected:** the attachment object including `contentBytes`

#### 7. SetExtendedProperty
- messageId: `<movedMessageId>`
- body: mailboxAddress `shared@company.com`, propertyGuid `12345678-1234-1234-1234-123456789012`, propertyName `RoutingDepartment`, value `Finance`
- **Expected:** `{ "messageId": "...", "propertyId": "...", "value": "Finance" }`

#### 8. GetExtendedProperty
- messageId: `<movedMessageId>`
- mailboxAddress: `shared@company.com`, propertyGuid `12345678-1234-1234-1234-123456789012`, propertyName `RoutingDepartment`
- **Expected:** `{ "messageId": "...", "propertyId": "...", "value": "Finance" }`

---

## 7. Integration Test: End-to-End

Demonstrates the full routing chain in a Copilot Studio topic (or the
PowerShell snippets above, run in order): **find folder -> categorize ->
move -> verify via delta -> read attachments -> set extended property**.

1. **Find the destination folder:** Call `GetMailFolders` (no
   `parentFolderId`) and find the department subfolder's `id` - skip this
   step if routing to a well-known folder like `archive`.
2. **Categorize:** Call `UpdateMessageCategories` on a real Inbox message
   with the department name(s) returned by Phase 2's `ClassifyMessage`
   Prompt tool.
3. **Move:** Call `MoveMessage` to route the message into the matching
   department subfolder (using the `id` from step 1, or a well-known name);
   capture `movedMessageId`.
4. **Verify via delta:** Call `GetMessagesDelta` (fresh, no `deltaLink`) and
   confirm the moved message shows up as a change; save the returned
   `@odata.deltaLink` for the next incremental check.
5. **Read attachments:** Call `GetAttachments` with `movedMessageId`, then
   `GetAttachment` for the first attachment id returned (if any).
6. **Set extended property:** Call `SetExtendedProperty` with `movedMessageId`
   to stash the classification result directly on the message, then
   `GetExtendedProperty` to confirm it round-trips.

---

## 8. Troubleshooting

| Issue | Resolution |
|---|---|
| **`MoveMessage` response's `movedMessageId` doesn't work on a later call** | Confirm you're using `movedMessageId` from the move response, not the original `messageId` - Graph assigns a new id on move |
| **`GetMessagesDelta` with a `deltaLink` returns a Graph error about an invalid URL** | Make sure the full link (including its query string) is URL-encoded when passed as the `deltaLink` query parameter - see the PowerShell snippet's `[uri]::EscapeDataString(...)` |
| **`GetExtendedProperty` returns `value: null` after a successful `SetExtendedProperty`** | Confirm `propertyGuid` and `propertyName` are byte-for-byte identical between the write and the read - Graph treats the combined `id` string as an exact match, not a lookup by name alone |
| **`GetAttachment` response has no `contentBytes`** | The attachment isn't a file attachment (e.g. it's an `itemAttachment` or `referenceAttachment`) - only file attachments carry `contentBytes` |
| **500 Internal Server Error from `UpdateMessageCategories`/`SetExtendedProperty`** | Confirm the PATCH body includes the required fields exactly as documented above - `app.py` returns a 400 with a clear message if a required field is missing, so a 500 usually means the Graph call itself failed (check `bodyPreview`-safe backend logs) |

---

## 9. Next Steps

- Proceed to Phase 4: Override/Change Classification
- Wire `UpdateMessageCategories` and `MoveMessage` into the Copilot Studio
  topic that runs after Phase 2's `ClassifyMessage` Prompt tool
- Consider persisting each mailbox's latest `GetMessagesDelta` checkpoint
  (e.g. in Dataverse) so incremental sync survives across sessions

---

## References

- [Microsoft Graph Mail API](https://learn.microsoft.com/graph/api/resources/message)
- [Update message (categories)](https://learn.microsoft.com/graph/api/message-update)
- [List mailFolders](https://learn.microsoft.com/graph/api/user-list-mailfolders)
- [Move message](https://learn.microsoft.com/graph/api/message-move)
- [Get delta (mail)](https://learn.microsoft.com/graph/api/message-delta)
- [List attachments](https://learn.microsoft.com/graph/api/message-list-attachments)
- [Get attachment](https://learn.microsoft.com/graph/api/attachment-get)
- [Get open extension or singleValueExtendedProperties](https://learn.microsoft.com/graph/api/singlevaluelegacyextendedproperty-get)
- [Update singleValueExtendedProperties](https://learn.microsoft.com/graph/outlook-extended-properties-overview)

---

**Copyright & License**

(c) 2026 Holger Imbery (contact@holgerimbery.blog)

Licensed under the Bridge365 Sustainable Use License 1.0 (BSUL-1.0). See the [LICENSE file](https://github.com/holgerimbery/bridge365/blob/main/LICENSE).