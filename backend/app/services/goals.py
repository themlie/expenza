"""Tasarruf hedefleri: oluşturma, güncelleme, para ekleme ve çekme."""
from decimal import Decimal

from sqlalchemy.orm import Session

from .. import models, schemas
from .errors import NotFound, RuleViolation


def get_owned(db: Session, user_id: int, goal_id: int) -> models.Goal:
    goal = (
        db.query(models.Goal)
        .filter(models.Goal.id == goal_id, models.Goal.user_id == user_id)
        .first()
    )
    if goal is None:
        raise NotFound("Hedef bulunamadı")
    return goal


def list_for(db: Session, user_id: int) -> list[models.Goal]:
    return (
        db.query(models.Goal)
        .filter(models.Goal.user_id == user_id)
        .order_by(models.Goal.created_at.desc())
        .all()
    )


def create(db: Session, user_id: int, payload: schemas.GoalCreate) -> models.Goal:
    goal = models.Goal(
        user_id=user_id,
        title=payload.title,
        target_amount=payload.target_amount,
        deadline=payload.deadline,
    )
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return goal


def update(
    db: Session, user_id: int, goal_id: int, payload: schemas.GoalUpdate
) -> models.Goal:
    """Ad, hedef tutar ve son tarihi günceller. deadline: null son tarihi kaldırır."""
    goal = get_owned(db, user_id, goal_id)
    for field, value in payload.model_dump(exclude_unset=True).items():
        if value is not None or field == "deadline":
            setattr(goal, field, value)
    db.commit()
    db.refresh(goal)
    return goal


def contribute(db: Session, user_id: int, goal_id: int, amount: Decimal) -> models.Goal:
    goal = get_owned(db, user_id, goal_id)
    goal.current_amount += amount
    db.commit()
    db.refresh(goal)
    return goal


def withdraw(db: Session, user_id: int, goal_id: int, amount: Decimal) -> models.Goal:
    """Hedefte biriken paradan geri alır; birikimden fazlası çekilemez."""
    goal = get_owned(db, user_id, goal_id)
    if amount > goal.current_amount:
        raise RuleViolation("Hedefte bu kadar birikim yok")
    goal.current_amount -= amount
    db.commit()
    db.refresh(goal)
    return goal


def delete(db: Session, user_id: int, goal_id: int) -> None:
    db.delete(get_owned(db, user_id, goal_id))
    db.commit()
