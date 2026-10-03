"""Analitik uçları SQL toplamlarıyla hesaplar; sonuç, işlem listesinden hesaplananla aynı olmalı."""
from datetime import date, timedelta

from app import models
from app.database import SessionLocal
from app.ml import analytics, insights


def _seed(add_tx, headers):
    today = date.today()
    first = today.replace(day=1)
    previous = first - timedelta(days=1)
    two_ago = previous.replace(day=1) - timedelta(days=1)
    for day, amount, category in [
        (two_ago, 300, "Yemek"), (two_ago, 120, "Ulaşım"),
        (previous, 450, "Yemek"), (previous, 80, "Eğlence"),
        (first, 200, "Yemek"), (first, 60, "Ulaşım"), (first, 2500, "Alışveriş"),
    ]:
        add_tx(headers, amount=amount, category=category, occurred_on=day.isoformat())
    # 2500'lük alışverişin anomali sayılması için yeterli sayıda olağan alışveriş.
    for amount in [40, 42, 45, 48, 50, 52, 55, 58, 60]:
        add_tx(headers, amount=amount, category="Alışveriş", occurred_on=previous.isoformat())
    add_tx(headers, amount=9000, type="income", category="Diğer", occurred_on=first.isoformat())


def _all_transactions(email):
    with SessionLocal() as db:
        user_id = db.query(models.User.id).filter(models.User.email == email).scalar()
        return db.query(models.Transaction).filter(models.Transaction.user_id == user_id).all()


def test_forecast_endpoint_matches_list_based_calculation(client, user, add_tx):
    _seed(add_tx, user["headers"])
    expected = analytics.forecast_spending(_all_transactions(user["email"]))
    assert client.get("/analytics/forecast", headers=user["headers"]).json() == expected


def test_anomalies_endpoint_matches_list_based_calculation(client, user, add_tx):
    _seed(add_tx, user["headers"])
    expected = analytics.detect_anomalies(_all_transactions(user["email"]))
    actual = client.get("/analytics/anomalies", headers=user["headers"]).json()
    assert actual == expected and len(actual) == 1


def test_insights_endpoint_matches_list_based_calculation(client, user, add_tx):
    _seed(add_tx, user["headers"])
    expected = insights.generate_insights(_all_transactions(user["email"]))
    assert client.get("/analytics/insights", headers=user["headers"]).json() == expected
