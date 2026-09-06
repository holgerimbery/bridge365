# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# backend-service/app.py - Shared Mailbox Service

from flask import Flask, request, jsonify
from azure.identity import ClientSecretCredential
from msgraph.core import GraphClient
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Graph client
try:
    credential = ClientSecretCredential(
        client_id=os.getenv("AZURE_CLIENT_ID"),
        client_secret=os.getenv("AZURE_CLIENT_SECRET"),
        tenant_id=os.getenv("AZURE_TENANT_ID")
    )
    graph_client = GraphClient(credential=credential)
    logging.info("Graph client initialized successfully")
except Exception as e:
    logging.error(f"Failed to initialize Graph client: {e}")


class GraphError(Exception):
    """Raised when Microsoft Graph returns a non-2xx response.

    msgraph-core's GraphClient does not raise for HTTP error statuses (it
    behaves like a plain requests.Session) - it returns the response object
    regardless of status code, so a Graph error body (e.g. ErrorItemNotFound)
    would otherwise be silently parsed and returned to the caller as if the
    call had succeeded. This exception, and the helpers below, make sure a
    Graph-side failure always surfaces as an error to API callers.
    """

    def __init__(self, response):
        self.status_code = response.status_code
        try:
            body = response.json()
        except ValueError:
            body = {}
        error = body.get("error", {}) if isinstance(body, dict) else {}
        self.message = (
            error.get("message")
            or response.text
            or f"Graph request failed with status {response.status_code}"
        )
        super().__init__(self.message)


def graph_json(response):
    """Parses a Graph response as JSON, raising GraphError if Graph reported
    a non-2xx status instead of treating its error body as a success payload."""
    if response.status_code >= 400:
        raise GraphError(response)
    return response.json()


def check_graph_response(response):
    """Raises GraphError if a Graph response (whose body is unused, e.g. a
    send action that returns no content) reported a non-2xx status."""
    if response.status_code >= 400:
        raise GraphError(response)


# Authorization allowlist of caller email addresses. Authentication itself
# (who is this caller, is their Microsoft sign-in valid) is handled entirely
# by Azure App Service Authentication (Easy Auth) with Microsoft Entra ID as
# the identity provider - see enable-backend-auth.ps1. Easy Auth injects the
# signed-in caller's email/UPN into the X-MS-CLIENT-PRINCIPAL-NAME header
# after validating their sign-in; this app only decides whether that email is
# authorized to call the API.
ALLOWED_EMAIL_ADDRESSES = {
    email.strip().lower()
    for email in os.getenv("ALLOWED_EMAIL_ADDRESSES", "").split(",")
    if email.strip()
}

@app.before_request
def enforce_email_allowlist():
    """Rejects requests from callers not on ALLOWED_EMAIL_ADDRESSES.

    Skips /health so uptime probes (which are unauthenticated) keep working.
    If ALLOWED_EMAIL_ADDRESSES is unset, allowlist enforcement is skipped
    entirely (e.g. local development without Easy Auth configured) - set it
    before exposing the service to production traffic.
    """
    if request.path == "/health" or not ALLOWED_EMAIL_ADDRESSES:
        return None

    caller_email = request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME", "")
    if not caller_email or caller_email.strip().lower() not in ALLOWED_EMAIL_ADDRESSES:
        logging.warning(f"Rejected request from unauthorized caller: {caller_email or '(no identity header)'}")
        return jsonify({"error": "Forbidden: caller is not on the allowed email list"}), 403

    return None

@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "shared-mailbox-classifier"}), 200

@app.route("/api/mailbox/messages", methods=["GET"])
def get_messages():
    """Fetch messages from shared mailbox"""
    try:
        mailbox = request.args.get("mailboxAddress")
        top = request.args.get("top", 10, type=int)
        
        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400
        
        # Restrict to the Inbox folder (not the /messages root collection,
        # which also returns Drafts/Sent Items) - createReply/createReplyAll
        # only work on real received messages, so mixing in drafts/sent
        # items here would make CreateDraft fail with a confusing Graph 400.
        response = graph_client.get(
            f"/users/{mailbox}/mailFolders/inbox/messages?$top={top}&$select=id,subject,from,receivedDateTime,bodyPreview"
        )
        return jsonify(graph_json(response)), 200
    except GraphError as e:
        logging.error(f"Error fetching messages (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error fetching messages: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/poll", methods=["GET"])
def poll_new_messages():
    """Polling trigger endpoint: returns messages newer than 'since', newest first.

    Used by the SharedMailboxConnector NewMessageReceived polling trigger so a
    Copilot Studio autonomous agent can react to new mail without a conversation.
    """
    try:
        mailbox = request.args.get("mailboxAddress")
        since = request.args.get("since")

        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400

        filter_clause = f"receivedDateTime gt {since}" if since else "receivedDateTime gt 1970-01-01T00:00:00Z"

        # Restrict to the Inbox folder - see get_messages() above for why.
        response = graph_client.get(
            f"/users/{mailbox}/mailFolders/inbox/messages?$filter={filter_clause}&$orderby=receivedDateTime desc"
            f"&$select=id,subject,from,receivedDateTime,bodyPreview"
        )
        return jsonify(graph_json(response)), 200
    except GraphError as e:
        logging.error(f"Error polling for new messages (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error polling for new messages: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/api/mailbox/messages/<message_id>", methods=["GET"])
def get_message(message_id):
    """Fetch single message"""
    try:
        mailbox = request.args.get("mailboxAddress")
        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400
        
        response = graph_client.get(
            f"/users/{mailbox}/messages/{message_id}"
        )
        return jsonify(graph_json(response)), 200
    except GraphError as e:
        logging.error(f"Error fetching message (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error fetching message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/classify", methods=["POST"])
def classify_message():
    """Classify message based on rules"""
    try:
        data = request.json
        message_id = data.get("messageId")
        
        if not message_id:
            return jsonify({"error": "messageId required"}), 400
        
        # Placeholder: Query Dataverse for classification rules (Phase 2)
        # Apply rule-based classifier
        
        return jsonify({
            "classifications": [
                {"className": "Invoice Question", "confidence": 0.92, "targetEmail": "finance@company.com"}
            ]
        }), 200
    except Exception as e:
        logging.error(f"Error classifying message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/drafts", methods=["POST"])
def create_draft():
    """Create a reply draft in the SHARED mailbox's own Drafts folder.

    Uses Graph's createReply/createReplyAll action against
    /users/{mailboxAddress}/messages/{messageId} - the app-only Graph client
    always operates against the shared mailbox named by mailboxAddress, never
    against a user's personal mailbox. createReply returns a draft populated
    with Graph's auto-generated quoted-reply body; we then PATCH that draft
    to set the exact subject/body the caller supplied.
    """
    try:
        data = request.json or {}
        mailbox = data.get("mailboxAddress")
        message_id = data.get("messageId")
        subject = data.get("subject")
        body = data.get("body")
        reply_all = bool(data.get("replyAll", False))

        if not all([mailbox, message_id, body]):
            return jsonify({"error": "mailboxAddress, messageId, body required"}), 400

        reply_action = "createReplyAll" if reply_all else "createReply"
        draft = graph_json(graph_client.post(
            f"/users/{mailbox}/messages/{message_id}/{reply_action}",
            json={}
        ))

        draft_id = draft.get("id")
        if not draft_id:
            return jsonify({"error": "Graph did not return a draft id"}), 502

        update_payload = {"body": {"contentType": "Text", "content": body}}
        if subject:
            update_payload["subject"] = subject

        updated = graph_json(graph_client.patch(
            f"/users/{mailbox}/messages/{draft_id}",
            json=update_payload
        ))

        return jsonify({
            "draftId": draft_id,
            "subject": updated.get("subject"),
            "draftUrl": updated.get("webLink", "")
        }), 200
    except GraphError as e:
        logging.error(f"Error creating draft (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error creating draft: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/drafts/<draft_id>", methods=["PATCH"])
def update_draft(draft_id):
    """Update an existing draft's subject/body/recipients in a shared mailbox
    before sending it. Only the fields provided are changed; the draft must
    already exist in mailboxAddress's Drafts folder (e.g. created via
    createReply above, or already present because a user drafted it in
    Outlook)."""
    try:
        data = request.json or {}
        mailbox = data.get("mailboxAddress")
        subject = data.get("subject")
        body = data.get("body")
        to = data.get("to")

        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400
        if subject is None and body is None and to is None:
            return jsonify({"error": "at least one of subject, body, to required"}), 400

        update_payload = {}
        if subject is not None:
            update_payload["subject"] = subject
        if body is not None:
            update_payload["body"] = {"contentType": "Text", "content": body}
        if to is not None:
            recipients = to if isinstance(to, list) else [to]
            update_payload["toRecipients"] = [
                {"emailAddress": {"address": address}} for address in recipients
            ]

        updated = graph_json(graph_client.patch(
            f"/users/{mailbox}/messages/{draft_id}",
            json=update_payload
        ))

        return jsonify({
            "draftId": draft_id,
            "subject": updated.get("subject"),
            "draftUrl": updated.get("webLink", "")
        }), 200
    except GraphError as e:
        logging.error(f"Error updating draft (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error updating draft: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/send", methods=["POST"])
def send_message():
    """Send a new (non-reply) message from the shared mailbox"""
    try:
        data = request.json
        mailbox = data.get("mailboxAddress")
        to = data.get("to")
        subject = data.get("subject")
        body = data.get("body")

        if not all([mailbox, to, subject, body]):
            return jsonify({"error": "mailboxAddress, to, subject, body required"}), 400

        # Call Microsoft Graph API sendMail action
        check_graph_response(graph_client.post(
            f"/users/{mailbox}/sendMail",
            json={
                "message": {
                    "subject": subject,
                    "body": {"contentType": "Text", "content": body},
                    "toRecipients": [{"emailAddress": {"address": to}}]
                },
                "saveToSentItems": "true"
            }
        ))

        return jsonify({"status": "sent"}), 200
    except GraphError as e:
        logging.error(f"Error sending message (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error sending message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/drafts/<draft_id>/send", methods=["POST"])
def send_draft_message(draft_id):
    """Send an existing draft (e.g. one created via CreateDraft)"""
    try:
        data = request.json or {}
        mailbox = data.get("mailboxAddress")

        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400

        # Call Microsoft Graph API to send the draft message as-is
        check_graph_response(graph_client.post(f"/users/{mailbox}/messages/{draft_id}/send", json={}))

        return jsonify({"status": "sent", "draftId": draft_id}), 200
    except GraphError as e:
        logging.error(f"Error sending draft message (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error sending draft message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/<message_id>/categories", methods=["PATCH"])
def update_message_categories(message_id):
    """Set/replace a message's Outlook categories (e.g. tag with a department
    name after classification), so routing decisions are visible directly in
    Outlook, not just in Dataverse.

    Graph categories are a full replace, not a merge - callers that want to
    add a category to existing ones must first GET the message and include
    its current categories in the list they send here.
    """
    try:
        data = request.json or {}
        mailbox = data.get("mailboxAddress")
        categories = data.get("categories")

        if not mailbox or categories is None:
            return jsonify({"error": "mailboxAddress, categories required"}), 400
        if not isinstance(categories, list):
            return jsonify({"error": "categories must be an array of strings"}), 400

        updated = graph_json(graph_client.patch(
            f"/users/{mailbox}/messages/{message_id}",
            json={"categories": categories}
        ))

        return jsonify({
            "messageId": message_id,
            "categories": updated.get("categories", [])
        }), 200
    except GraphError as e:
        logging.error(f"Error updating message categories (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error updating message categories: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/folders", methods=["GET"])
def get_mail_folders():
    """List mail folders in the shared mailbox, so callers can discover the
    folderId to pass as MoveMessage's destinationId.

    Well-known folder names (e.g. "archive", "deleteditems", "drafts",
    "sentitems", "junkemail", "inbox") work directly in destinationId
    without calling this at all. This endpoint exists for everything else -
    custom department subfolders don't have a well-known name, so their
    real Graph folder id has to be looked up first.

    Without parentFolderId, lists top-level folders (Inbox, Archive, Sent
    Items, any custom top-level folders, etc.). Graph's mailFolders
    endpoint returns only one level at a time (it does not recurse), so to
    reach a subfolder (e.g. a department folder nested under Inbox), pass
    parentFolderId = the parent's id from a previous call to list its
    childFolders, and repeat until you reach the target folder.
    """
    try:
        mailbox = request.args.get("mailboxAddress")
        parent_folder_id = request.args.get("parentFolderId")
        top = request.args.get("top", 50, type=int)

        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400

        path = (
            f"/users/{mailbox}/mailFolders/{parent_folder_id}/childFolders"
            if parent_folder_id
            else f"/users/{mailbox}/mailFolders"
        )
        response = graph_client.get(
            f"{path}?$top={top}&$select=id,displayName,parentFolderId,childFolderCount"
        )
        return jsonify(graph_json(response)), 200
    except GraphError as e:
        logging.error(f"Error listing mail folders (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error listing mail folders: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/<message_id>/move", methods=["POST"])
def move_message(message_id):
    """Move a message to a different mail folder (e.g. route to a department
    subfolder after classification).

    Graph's move action returns the message under a NEW id in the
    destination folder - the original messageId stops resolving once the
    move completes. Callers must switch to movedMessageId for any further
    operation on this message (categories, extended properties, etc.).
    destinationId accepts either a real folder id or a Graph well-known
    folder name (e.g. "deleteditems", "archive").
    """
    try:
        data = request.json or {}
        mailbox = data.get("mailboxAddress")
        destination_id = data.get("destinationId")

        if not mailbox or not destination_id:
            return jsonify({"error": "mailboxAddress, destinationId required"}), 400

        moved = graph_json(graph_client.post(
            f"/users/{mailbox}/messages/{message_id}/move",
            json={"destinationId": destination_id}
        ))

        return jsonify({
            "movedMessageId": moved.get("id"),
            "destinationId": destination_id
        }), 200
    except GraphError as e:
        logging.error(f"Error moving message (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error moving message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/delta", methods=["GET"])
def get_messages_delta():
    """Delta query for change tracking on the Inbox (new/changed/deleted
    messages since a checkpoint), for incremental sync use cases.

    This is a NEW, separate capability from /api/mailbox/messages/poll above
    - poll uses a plain receivedDateTime > since filter (simple, but misses
    edits/deletes and can duplicate/skip around clock skew), while this uses
    Graph's real delta token protocol. Do not replace poll with this; both
    are kept.

    First call: omit deltaLink to start a fresh delta over the Inbox. Graph
    returns @odata.nextLink while paging through the initial result set, and
    a final @odata.deltaLink once caught up - callers should persist
    whichever link comes back and pass it as deltaLink on the next call to
    resume from that checkpoint. Both links are full, absolute Graph URLs,
    which msgraph-core's GraphClient (built on requests.Session) passes
    through unchanged instead of re-prefixing with the base Graph URL.
    """
    try:
        mailbox = request.args.get("mailboxAddress")
        delta_link = request.args.get("deltaLink")

        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400

        request_url = delta_link or (
            f"/users/{mailbox}/mailFolders/inbox/messages/delta"
            f"?$select=id,subject,from,receivedDateTime,bodyPreview"
        )

        response = graph_client.get(request_url)
        return jsonify(graph_json(response)), 200
    except GraphError as e:
        logging.error(f"Error querying messages delta (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error querying messages delta: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/<message_id>/attachments", methods=["GET"])
def get_attachments(message_id):
    """List a message's attachments (metadata only - id, name, contentType,
    size; no contentBytes). Use get_attachment below to fetch a single
    attachment's content."""
    try:
        mailbox = request.args.get("mailboxAddress")
        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400

        response = graph_client.get(
            f"/users/{mailbox}/messages/{message_id}/attachments"
            f"?$select=id,name,contentType,size"
        )
        return jsonify(graph_json(response)), 200
    except GraphError as e:
        logging.error(f"Error fetching attachments (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error fetching attachments: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/<message_id>/attachments/<attachment_id>", methods=["GET"])
def get_attachment(message_id, attachment_id):
    """Fetch a single attachment, including its base64 contentBytes for file
    attachments (contentBytes is absent for other attachment types, e.g.
    itemAttachment/referenceAttachment)."""
    try:
        mailbox = request.args.get("mailboxAddress")
        if not mailbox:
            return jsonify({"error": "mailboxAddress parameter required"}), 400

        response = graph_client.get(
            f"/users/{mailbox}/messages/{message_id}/attachments/{attachment_id}"
        )
        return jsonify(graph_json(response)), 200
    except GraphError as e:
        logging.error(f"Error fetching attachment (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error fetching attachment: {e}")
        return jsonify({"error": str(e)}), 500

def _extended_property_id(property_guid, property_name):
    """Builds the Graph singleValueExtendedProperties id string, e.g.
    'String {12345678-1234-1234-1234-123456789012} Name RoutingDepartment'.
    Always uses the String property type - sufficient for the routing/
    classification metadata values this API is meant for."""
    return f"String {{{property_guid}}} Name {property_name}"

@app.route("/api/mailbox/messages/<message_id>/extended-properties", methods=["GET"])
def get_extended_property(message_id):
    """Reads a single Graph MAPI extended property stashed on a message (e.g.
    internal routing/classification metadata written by set_extended_property
    below), via $expand=singleValueExtendedProperties($filter=...).

    propertyGuid/propertyName together identify the property - Graph has no
    concept of a bare property name, every extended property is namespaced by
    a GUID the caller chooses (any stable GUID works; pick one per logical
    property and reuse it for both reads and writes).
    """
    try:
        mailbox = request.args.get("mailboxAddress")
        property_guid = request.args.get("propertyGuid")
        property_name = request.args.get("propertyName")

        if not all([mailbox, property_guid, property_name]):
            return jsonify({"error": "mailboxAddress, propertyGuid, propertyName required"}), 400

        property_id = _extended_property_id(property_guid, property_name)
        response = graph_client.get(
            f"/users/{mailbox}/messages/{message_id}"
            f"?$expand=singleValueExtendedProperties($filter=id eq '{property_id}')"
        )
        message = graph_json(response)
        properties = message.get("singleValueExtendedProperties") or []
        value = properties[0].get("value") if properties else None

        return jsonify({
            "messageId": message_id,
            "propertyId": property_id,
            "value": value
        }), 200
    except GraphError as e:
        logging.error(f"Error reading extended property (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error reading extended property: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/mailbox/messages/<message_id>/extended-properties", methods=["PATCH"])
def set_extended_property(message_id):
    """Writes a single Graph MAPI extended property on a message - see
    get_extended_property above for the propertyGuid/propertyName pairing.
    Graph creates the property if it doesn't exist yet, or overwrites its
    value if it does."""
    try:
        data = request.json or {}
        mailbox = data.get("mailboxAddress")
        property_guid = data.get("propertyGuid")
        property_name = data.get("propertyName")
        value = data.get("value")

        if not all([mailbox, property_guid, property_name]) or value is None:
            return jsonify({"error": "mailboxAddress, propertyGuid, propertyName, value required"}), 400

        property_id = _extended_property_id(property_guid, property_name)
        graph_json(graph_client.patch(
            f"/users/{mailbox}/messages/{message_id}",
            json={"singleValueExtendedProperties": [{"id": property_id, "value": str(value)}]}
        ))

        return jsonify({
            "messageId": message_id,
            "propertyId": property_id,
            "value": value
        }), 200
    except GraphError as e:
        logging.error(f"Error setting extended property (Graph error {e.status_code}): {e}")
        return jsonify({"error": str(e)}), e.status_code
    except Exception as e:
        logging.error(f"Error setting extended property: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
