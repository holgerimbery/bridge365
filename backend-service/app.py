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
        
        # Call Microsoft Graph API
        response = graph_client.get(
            f"/users/{mailbox}/messages?$top={top}&$select=id,subject,from,receivedDateTime,bodyPreview"
        )
        return jsonify(response.json()), 200
    except Exception as e:
        logging.error(f"Error fetching messages: {e}")
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
        return jsonify(response.json()), 200
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
    """Create reply draft"""
    try:
        data = request.json
        message_id = data.get("messageId")
        subject = data.get("subject")
        body = data.get("body")
        
        if not all([message_id, subject, body]):
            return jsonify({"error": "messageId, subject, body required"}), 400
        
        # Placeholder: Create draft via Graph API (Phase 3)
        
        return jsonify({
            "draftId": "draft-placeholder",
            "draftUrl": "https://outlook.office.com/mail/..."
        }), 200
    except Exception as e:
        logging.error(f"Error creating draft: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
