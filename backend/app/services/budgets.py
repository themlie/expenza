"""Bütçe limitleri: kategori başına tek bütçe ve bu ayın harcaması."""
from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session

from .. import coach, models, schemas


def list_for(db: Session, user_id: int) -> list[models.Budget]:
    return db.query(models.Budget).filter(models.Budget.user_id == user_id).all()


def upsert(db: Session, user_id: int, payload: schemas.BudgetCreate) -> models.Budget:
    """Kategori başına tek bütçe: varsa limiti güncellenir, yoksa oluşturulur."""
    budget = (
        db.query(models.Budget)
        .filter(models.Budget.user_id == user_id, models.Budget.category == payload.category)
        .first()
    )
    if budget:
        budget.monthly_limit = payload.monthly_limit
    else:
        budget = models.Budget(
            user_id=user_id, category=payload.category, monthly_limit=payload.monthly_limit
        )
        db.add(budget)
    db.commit()
    db.refresh(budget)
    return budget


def delete(db: Session, user_id: int, budget_id: int) -> None:
    """Bütçeyi siler; bulunamayan bütçe sessizce yok sayılır."""
    budget = (
        db.query(models.Budget)
        .filter(models.Budget.id == budget_id, models.Budget.user_id == user_id)
        .first()
    )
    if budget:
        db.delete(budget)
        db.commit()


def spent_this_month(db: Session, user_id: int) -> dict[str, Decimal]:
    """İçinde bulunulan ayın kategori adına göre giderleri ("Toplam" dahil)."""
    today = date.today()
    return coach.month_spending(db, user_id, today.year, today.month)
