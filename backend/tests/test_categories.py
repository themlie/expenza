"""Kategori listesi tek kaynaktan (models.CategoryEnum) gelir; diğer kopyalar ona uymalı."""
from datetime import date, timedelta

from app import models
from app.database import SessionLocal
from app.ml import categorizer
from app.models import BudgetCategory, CategoryEnum
from ml_training.generate_data import DATA

NAMES = [c.value for c in CategoryEnum]


def test_total_is_a_budget_scope_not_a_category():
    assert "Toplam" not in NAMES
    assert [c.value for c in BudgetCategory] == NAMES + ["Toplam"]


def test_rule_keywords_cover_every_category_except_other():
    assert set(categorizer.KEYWORDS) == set(CategoryEnum) - {CategoryEnum.diger}


def test_training_data_generator_uses_the_same_labels():
    assert list(DATA) == NAMES


def test_trained_model_predicts_only_known_categories():
    # Kategori eklenir ya da çıkarılırsa model yeniden eğitilmeli; bu test hatırlatır.
    assert sorted(categorizer._active._pipe.classes_) == sorted(NAMES)


def test_categories_endpoint_matches_enum(client):
    assert client.get("/categories").json() == NAMES


def test_transactions_reject_total_as_category(client, user):
    r = client.post(
        "/transactions",
        json={"amount": 10, "category": "Toplam", "note": "x"},
        headers=user["headers"],
    )
    assert r.status_code == 422
    r = client.get("/transactions?category=Toplam", headers=user["headers"])
    assert r.status_code == 422


def test_total_budget_counts_every_category(client, user, add_tx):
    h = user["headers"]
    add_tx(h, amount=100, category="Yemek")
    add_tx(h, amount=40, category="Diğer")
    client.post("/budgets", json={"category": "Yemek", "monthly_limit": 500}, headers=h)
    client.post("/budgets", json={"category": "Toplam", "monthly_limit": 1000}, headers=h)
    spent = {b["category"]: b["spent"] for b in client.get("/budgets", headers=h).json()}
    assert spent == {"Yemek": 100, "Toplam": 140}


def test_budget_alert_message_for_total(client, user, add_tx):
    h = user["headers"]
    client.post("/budgets", json={"category": "Toplam", "monthly_limit": 100}, headers=h)
    alert = add_tx(h, amount=90, category="Sağlık")["budget_alerts"][0]
    assert alert["category"] == "Toplam"
    assert alert["message"] == "Aylık toplam bütçe: %90 kullanıldı."
    today = date.today()
    with SessionLocal() as db:
        u = db.query(models.User).filter(models.User.email == user["email"]).one()
        last = today.replace(day=1) - timedelta(days=1)
        # Başka bir ayın harcaması bu ayın toplamına girmez.
        db.add(models.Transaction(
            user_id=u.id, amount=500, type=models.TxType.expense,
            category=CategoryEnum.yemek, occurred_on=last,
        ))
        db.commit()
    assert client.get("/budgets", headers=h).json()[0]["spent"] == 90
