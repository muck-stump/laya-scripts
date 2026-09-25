"""Demo: Support Ticket Triage using the TypeSafe SDK pointed at a self hosted system-one model.

No laya code here — just the official typesafe-sdk talking to our server.
Set ENDPOINT and API_KEY in .env (same values used by the test scripts).
"""

import os
from pathlib import Path
from dotenv import load_dotenv
from typesafe_sdk import TypeSafeClient, Choice, Score, Noul

load_dotenv(Path(__file__).parent / ".env")

# Map our env var names onto what the TypeSafe SDK expects
os.environ["TYPESAFE_API_KEY"] = os.environ["API_KEY"]
os.environ["TYPESAFE_BASE_URL"] = f"https://{os.environ['ENDPOINT']}"

TRIAGE_QUESTIONS = {
    "category": Choice(
        instructions="What kind of ticket is `ticket`?",
        criteria={
            "bug_report": "Something is broken, degraded, or throwing errors",
            "feature_request": "Asking for something that does not exist yet",
            "billing": "Charges, invoices, payment methods, refunds",
            "other": "General inquiries or uncategorized",
        },
    ),
    "bug_severity": Score(
        instructions="How severe is the issue in `ticket`?",
        criteria=[
            "Cosmetic; no impact on core functionality",
            "Broken or degraded feature, but a workaround exists",
            "Blocking issue; no workaround exists",
        ],
    ),
    "has_repro_steps": Noul(
        instructions="Does `ticket` say how to reproduce the problem?"
    ),
    "refund_requested": Noul(
        instructions="Does the customer ask for money back or a refund?"
    ),
    "frustration": Score(
        instructions="How frustrated is the author of `ticket`?",
        criteria=[
            "Calm, just stating facts",
            "Frustrated but civil",
            "Very angry, strong language, or threatening to leave",
        ],
    ),
}


def triage(client: TypeSafeClient, ticket: str) -> dict:
    resp = client.system_one(state={"ticket": ticket}, questions=TRIAGE_QUESTIONS)

    category = resp.choices["category"]
    severity = resp.scores["bug_severity"]
    has_repro = resp.nouls["has_repro_steps"]
    refund = resp.nouls["refund_requested"]
    frustration = resp.scores["frustration"]

    if category.confidence < 0.4:
        return {"route": "human", "reason": "unclear category"}

    if category.choice == "bug_report":
        if severity.score > 1.2 and has_repro.noul > 0.5:
            return {"route": "engineering", "priority": "high"}
        return {"route": "bug_backlog"}

    if category.choice == "billing":
        return {"route": "billing", "refund_likely": refund.noul > 0.6}

    if category.choice == "feature_request":
        return {"route": "product"}

    return {"route": "human", "flag": frustration.score > 1.2}


if __name__ == "__main__":
    with TypeSafeClient() as client:
        ticket1 = "The export button crashes the settings page in Safari. Steps: 1. Click Export 2. Browser freezes completely. Urgent!"
        print("Ticket 1 triage:", triage(client, ticket1))

        ticket2 = "I was charged $49 twice for order #982! Please refund the duplicate immediately."
        print("Ticket 2 triage:", triage(client, ticket2))
