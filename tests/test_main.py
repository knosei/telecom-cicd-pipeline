from app.main import app


def test_home():
    client = app.test_client()

    response = client.get("/")

    assert response.status_code == 200
    assert response.json["application"] == "Telecom Billing API"


def test_health():
    client = app.test_client()

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json["status"] == "healthy"


def test_billing():
    client = app.test_client()

    response = client.get("/billing/10001")

    assert response.status_code == 200
    assert response.json["customer_id"] == "10001"
    assert response.json["billing_status"] == "PAID"