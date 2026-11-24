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


def test_version():
    with app.test_client() as client:
        response = client.get('/version')

        assert response.status_code == 200

        data = response.get_json()

        assert data['application'] == 'Telecom Billing API'
        assert data['version'] == '1.1.0'
        assert data['release'] == 'Production CI/CD validation'