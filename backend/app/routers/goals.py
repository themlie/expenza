"""Tasarruf hedefleri uçları — raporun çekirdek özelliği.

İş kuralları app/services/goals.py'de; plan alanları (ilerleme, ayda gereken) coach'tan.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import coach, models, schemas
from ..auth import get_current_user
from ..database import get_db
from ..services import goals as service

router = APIRouter(prefix="/goals", tags=["goals"])


def _to_out(g: models.Goal) -> schemas.GoalOut:
    out = schemas.GoalOut.model_validate(g)
    for field, value in coach.goal_plan(g).items():
        setattr(out, field, value)
    return out


@router.post("", response_model=schemas.GoalOut, status_code=201)
def create_goal(
    payload: schemas.GoalCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return _to_out(service.create(db, user.id, payload))


@router.get("", response_model=list[schemas.GoalOut])
def list_goals(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return [_to_out(g) for g in service.list_for(db, user.id)]


@router.put("/{goal_id}", response_model=schemas.GoalOut)
def update_goal(
    goal_id: int,
    payload: schemas.GoalUpdate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Ad, hedef tutar ve son tarihi günceller. deadline: null son tarihi kaldırır."""
    return _to_out(service.update(db, user.id, goal_id, payload))


@router.post("/{goal_id}/contribute", response_model=schemas.GoalOut)
def contribute(
    goal_id: int,
    payload: schemas.GoalContribute,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return _to_out(service.contribute(db, user.id, goal_id, payload.amount))


@router.post("/{goal_id}/withdraw", response_model=schemas.GoalOut)
def withdraw(
    goal_id: int,
    payload: schemas.GoalContribute,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Hedefte biriken paradan geri alır."""
    return _to_out(service.withdraw(db, user.id, goal_id, payload.amount))


@router.delete("/{goal_id}", status_code=204)
def delete_goal(
    goal_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    service.delete(db, user.id, goal_id)
    return None
