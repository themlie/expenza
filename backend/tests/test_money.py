"""Para tutarları Decimal olarak hesaplanır (KOD-01)."""
from decimal import Decimal

import pytest

from app.money import to_money


def test_to_money_rounds_half_up_to_cents():
    assert to_money(0.1) == Decimal("0.10")
    assert to_money(2.675) == Decimal("2.68")  # float olarak 2.67499999... ama metni 2.675
    assert to_money("10.005") == Decimal("10.01")
    assert to_money(3) == Decimal("3.00")


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), "abc", True, None, [1]])
def test_to_money_rejects_non_numbers(bad):
    with pytest.raises(ValueError):
        to_money(bad)


def test_sums_have_no_float_drift(client, user, add_tx):
    h = user["headers"]
    for amount in (0.1, 0.2, 0.7):
        add_tx(h, amount=amount)
    add_tx(h, amount=1, type="income", category="Diğer")
    summary = client.get("/transactions/summary", headers=h).json()
    assert summary["total_expense"] == 1.0  # float ile 0.9999999999999999
    assert summary["balance"] == 0.0


def test_amounts_are_rounded_to_cents_and_validated(client, user, add_tx):
    h = user["headers"]
    tx = add_tx(h, amount=3300.330033)  # istemcide kur çevirisinden gelen tutar
    assert tx["amount"] == 3300.33
    for bad in (0.004, "abc", True):
        r = client.post("/transactions", json={"amount": bad, "type": "expense"}, headers=h)
        assert r.status_code == 422, bad


def test_goal_contributions_add_up_exactly(client, user):
    h = user["headers"]
    goal = client.post("/goals", json={"title": "Tatil", "target_amount": 0.3}, headers=h).json()
    for _ in range(3):
        r = client.post(f"/goals/{goal['id']}/contribute", json={"amount": 0.1}, headers=h)
    body = r.json()
    assert body["current_amount"] == 0.3
    assert body["status"] == "completed" and body["remaining"] == 0
