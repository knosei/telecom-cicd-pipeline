import os
from flask import Flask, jsonify

app = Flask(__name__)

# Read configuration from environment variables
APP_NAME = os.getenv("APP_NAME", "Telecom Billing API")
BILLING_STATUS = os.getenv("BILLING_STATUS", "PAID")
BILLING_AMOUNT = float(os.getenv("BILLING_AMOUNT", "125.50"))
CURRENCY = os.getenv("CURRENCY", "GHS")

# Sensitive values retrieved from AWS Secrets Manager
DB_USERNAME = os.getenv("DB_USERNAME")
DB_PASSWORD = os.getenv("DB_PASSWORD")
BILLING_API_KEY = os.getenv("BILLING_API_KEY")


@app.route("/")
def home():
    return jsonify({
        "application": APP_NAME,
        "status": "running"
    })


@app.route("/health")
def health():
    return jsonify({
        "status": "healthy"
    }), 200


@app.route("/billing/<customer_id>")
def billing(customer_id):
    return jsonify({
        "customer_id": customer_id,
        "billing_status": BILLING_STATUS,
        "amount": BILLING_AMOUNT,
        "currency": CURRENCY
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
