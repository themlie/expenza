"""Tasarruf hedefleri uçları — raporun çekirdek özelliği."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import coach, models, schemas
from ..auth import get_current_user
from ..database import get_db

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
    goal = models.Goal(
        user_id=user.id,
        title=payload.title,
        target_amount=payload.target_amount,
        deadline=payload.deadline,
    )
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return _to_out(goal)


@router.get("", response_model=list[schemas.GoalOut])
def list_goals(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    goals = (
        db.query(models.Goal)
        .filter(models.Goal.user_id == user.id)
        .order_by(models.Goal.created_at.desc())
        .all()
    )
    return [_to_out(g) for g in goals]


def _get_owned(db: Session, user_id: int, goal_id: int) -> models.Goal:
    goal = (
        db.query(models.Goal)
        .filter(models.Goal.id == goal_id, models.Goal.user_id == user_id)
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Hedef bulunamadı")
    return goal


@router.put("/{goal_id}", response_model=schemas.GoalOut)
def update_goal(
    goal_id: int,
    payload: schemas.GoalUpdate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Ad, hedef tutar ve son tarihi günceller. deadline: null son tarihi kaldırır."""
    goal = _get_owned(db, user.id, goal_id)
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        if value is not None or field == "deadline":
            setattr(goal, field, value)
    db.commit()
    db.refresh(goal)
    return _to_out(goal)


@router.post("/{goal_id}/contribute", response_model=schemas.GoalOut)
def contribute(
    goal_id: int,
    payload: schemas.GoalContribute,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    goal = _get_owned(db, user.id, goal_id)
    goal.current_amount += payload.amount
    db.commit()
    db.refresh(goal)
    return _to_out(goal)


@router.post("/{goal_id}/withdraw", response_model=schemas.GoalOut)
def withdraw(
    goal_id: int,
    payload: schemas.GoalContribute,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Hedefte biriken paradan geri alır."""
    goal = _get_owned(db, user.id, goal_id)
    if payload.amount > goal.current_amount:
        raise HTTPException(status_code=400, detail="Hedefte bu kadar birikim yok")
    goal.current_amount -= payload.amount
    db.commit()
    db.refresh(goal)
    return _to_out(goal)


@router.delete("/{goal_id}", status_code=204)
def delete_goal(
    goal_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    goal = _get_owned(db, user.id, goal_id)
    db.delete(goal)
    db.commit()
    return None
