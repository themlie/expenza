"""Bir kullanıcı başka bir kullanıcının verisini göremez ve değiştiremez."""
import pytest

PROTECTED = [
    ("get", "/auth/me"),
    ("put", "/auth/me"),
    ("delete", "/auth/me"),
    ("post", "/auth/change-password"),
    ("get", "/transactions/months"),
    ("get", "/transactions/summary"),
    ("get", "/transactions"),
    ("post", "/transactions"),
    ("put", "/transactions/1"),
    ("delete", "/transactions/1"),
    ("get", "/budgets"),
    ("post", "/budgets"),
    ("delete", "/budgets/1"),
    ("get", "/goals"),
    ("post", "/goals"),
    ("post", "/goals/1/contribute"),
    ("post", "/goals/1/withdraw"),
    ("put", "/goals/1"),
    ("delete", "/goals/1"),
    ("get", "/analytics/forecast"),
    ("get", "/analytics/anomalies"),
    ("get", "/analytics/insights"),
    ("post", "/ml/categorize"),
    ("post", "/chat"),
    ("get", "/alerts"),
    ("post", "/alerts/dismiss"),
]


@pytest.mark.parametrize("method,path", PROTECTED)
def test_protected_endpoints_require_token(client, method, path):
    assert getattr(client, method)(path).status_code == 401


def test_transactions_are_isolated(client, make_user, add_tx):
    a, b = make_user(), make_user()
    tx = add_tx(a["headers"])

    assert client.get("/transactions", headers=b["headers"]).json() == []
    r = client.put(f"/transactions/{tx['id']}", json={"amount": 1}, headers=b["headers"])
    assert r.status_code == 404
    client.delete(f"/transactions/{tx['id']}", headers=b["headers"])

    mine = client.get("/transactions", headers=a["headers"]).json()
    assert len(mine) == 1 and mine[0]["amount"] == 100


def test_budgets_are_isolated(client, make_user):
    a, b = make_user(), make_user()
    budget = client.post(
        "/budgets", json={"category": "Yemek", "monthly_limit": 500}, headers=a["headers"]
    ).json()

    assert client.get("/budgets", headers=b["headers"]).json() == []
    client.delete(f"/budgets/{budget['id']}", headers=b["headers"])
    assert len(client.get("/budgets", headers=a["headers"]).json()) == 1


def test_goals_are_isolated(client, make_user):
    a, b = make_user(), make_user()
    goal = client.post(
        "/goals", json={"title": "Tatil", "target_amount": 1000}, headers=a["headers"]
    ).json()

    assert client.get("/goals", headers=b["headers"]).json() == []
    r = client.post(f"/goals/{goal['id']}/contribute", json={"amount": 100}, headers=b["headers"])
    assert r.status_code == 404
    r = client.put(f"/goals/{goal['id']}", json={"title": "Benim"}, headers=b["headers"])
    assert r.status_code == 404
    r = client.post(f"/goals/{goal['id']}/withdraw", json={"amount": 1}, headers=b["headers"])
    assert r.status_code == 404
    assert client.delete(f"/goals/{goal['id']}", headers=b["headers"]).status_code == 404
    mine = client.get("/goals", headers=a["headers"]).json()[0]
    assert mine["current_amount"] == 0 and mine["title"] == "Tatil"


def test_analytics_only_counts_own_spending(client, make_user, add_tx):
    a, b = make_user(), make_user()
    add_tx(a["headers"], amount=900)
    r = client.get("/analytics/forecast", headers=b["headers"])
    assert r.json()["current_month_spent"] == 0


def test_month_list_and_alerts_are_isolated(client, make_user, add_tx):
    a, b = make_user(), make_user()
    add_tx(a["headers"], amount=900)
    client.post("/budgets", json={"category": "Yemek", "monthly_limit": 100}, headers=a["headers"])

    assert client.get("/transactions/months", headers=b["headers"]).json() == []
    assert client.get("/alerts", headers=b["headers"]).json() == []
    assert len(client.get("/alerts", headers=a["headers"]).json()) == 1
