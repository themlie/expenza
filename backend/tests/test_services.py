"""Servis katmanı HTTP olmadan da kullanılabilir; kural ihlalleri istisnadır (KOD-03)."""
from decimal import Decimal

import pytest

from app import models, schemas
from app.database import SessionLocal
from app.services import accounts, goals, transactions
from app.services.errors import NotFound, RuleViolation


@pytest.fixture
def db():
    with SessionLocal() as session:
        yield session


def _user(db, email):
    return accounts.register(
        db, schemas.UserCreate(email=email, password="parola123", display_name="Test")
    )


def test_goal_rules_raise_service_errors(db):
    owner, other = _user(db, "sahip@example.com"), _user(db, "baska@example.com")
    goal = goals.create(db, owner.id, schemas.GoalCreate(title="Tatil", target_amount=100))
    goals.contribute(db, owner.id, goal.id, Decimal("30"))

    with pytest.raises(RuleViolation):
        goals.withdraw(db, owner.id, goal.id, Decimal("30.01"))
    with pytest.raises(NotFound):
        goals.get_owned(db, other.id, goal.id)
    assert goals.withdraw(db, owner.id, goal.id, Decimal("30")).current_amount == 0


def test_transaction_service_creates_and_summarizes(db):
    user = _user(db, "islem@example.com")
    payload = schemas.TransactionCreate(amount=0.1, type="expense", category="Yemek", note="çay")
    for _ in range(3):
        tx, alerts = transactions.create(db, user, payload)
    assert alerts == [] and tx.amount == Decimal("0.10")

    summary = transactions.summary(db, user.id, tx.occurred_on.year, tx.occurred_on.month)
    assert summary.month_expense == pytest.approx(0.3)
    with pytest.raises(NotFound):
        transactions.get_owned(db, user.id + 999, tx.id)


def test_account_delete_removes_user_data(db):
    user = _user(db, "silinecek@example.com")
    goals.create(db, user.id, schemas.GoalCreate(title="Araba", target_amount=10))
    accounts.delete(db, user)
    assert db.query(models.Goal).count() == 0
    assert not accounts.email_taken(db, "silinecek@example.com")
