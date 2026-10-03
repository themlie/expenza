"""Bütçe limitleri ve harcanan tutar özeti."""
from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import coach, models, schemas
from ..auth import get_current_user
from ..database import get_db

router = APIRouter(prefix="/budgets", tags=["budgets"])


def _out(budget: models.Budget, spent: dict[str, float]) -> schemas.BudgetOut:
    out = schemas.BudgetOut.model_validate(budget)
    out.spent = spent.get(budget.category.value, 0.0)
    return out


def _this_month(db: Session, user_id: int) -> dict[str, float]:
    """İçinde bulunulan ayın kategori adına göre giderleri ("Toplam" dahil)."""
    today = date.today()
    return coach.month_spending(db, user_id, today.year, today.month)


@router.post("", response_model=schemas.BudgetOut, status_code=201)
def upsert_budget(
    payload: schemas.BudgetCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    # Kategori başına tek bütçe: varsa güncelle, yoksa oluştur.
    budget = (
        db.query(models.Budget)
        .filter(
            models.Budget.user_id == user.id,
            models.Budget.category == payload.category,
        )
        .first()
    )
    if budget:
        budget.monthly_limit = payload.monthly_limit
    else:
        budget = models.Budget(
            user_id=user.id,
            category=payload.category,
            monthly_limit=payload.monthly_limit,
        )
        db.add(budget)
    db.commit()
    db.refresh(budget)
    return _out(budget, _this_month(db, user.id))


@router.get("", response_model=list[schemas.BudgetOut])
def list_budgets(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    budgets = db.query(models.Budget).filter(models.Budget.user_id == user.id).all()
    spent = _this_month(db, user.id)
    return [_out(b, spent) for b in budgets]


@router.delete("/{budget_id}", status_code=204)
def delete_budget(
    budget_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    budget = (
        db.query(models.Budget)
        .filter(models.Budget.id == budget_id, models.Budget.user_id == user.id)
        .first()
    )
    if budget:
        db.delete(budget)
        db.commit()
    return None
