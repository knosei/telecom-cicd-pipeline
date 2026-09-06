from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def home():
    return jsonify({
        "application": "Telecom Billing API",
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
        "billing_status": "PAID",
        "amount": 125.50,
        "currency": "GHS"
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)