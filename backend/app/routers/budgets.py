"""Bütçe limitleri ve harcanan tutar özeti (iş kuralları: app/services/budgets.py)."""
from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import models, schemas
from ..auth import get_current_user
from ..database import get_db
from ..money import ZERO
from ..services import budgets as service

router = APIRouter(prefix="/budgets", tags=["budgets"])


def _out(budget: models.Budget, spent: dict[str, Decimal]) -> schemas.BudgetOut:
    out = schemas.BudgetOut.model_validate(budget)
    out.spent = spent.get(budget.category.value, ZERO)
    return out


@router.post("", response_model=schemas.BudgetOut, status_code=201)
def upsert_budget(
    payload: schemas.BudgetCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    budget = service.upsert(db, user.id, payload)
    return _out(budget, service.spent_this_month(db, user.id))


@router.get("", response_model=list[schemas.BudgetOut])
def list_budgets(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    spent = service.spent_this_month(db, user.id)
    return [_out(b, spent) for b in service.list_for(db, user.id)]


@router.delete("/{budget_id}", status_code=204)
def delete_budget(
    budget_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    service.delete(db, user.id, budget_id)
    return None
