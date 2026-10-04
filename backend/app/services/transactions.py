"""İşlemler: kayıt, güncelleme, silme, listeleme ve özetler."""
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from sqlalchemy import extract, func
from sqlalchemy.orm import Query, Session

from .. import coach, models, recurring, schemas
from ..ml import categorizer
from ..money import ZERO
from .errors import NotFound, RuleViolation

Tx = models.Transaction


def month_filter(year: int, month: int) -> tuple:
    return (
        extract("year", Tx.occurred_on) == year,
        extract("month", Tx.occurred_on) == month,
    )


def get_owned(db: Session, user_id: int, tx_id: int) -> models.Transaction:
    tx = db.query(Tx).filter(Tx.id == tx_id, Tx.user_id == user_id).first()
    if tx is None:
        raise NotFound("İşlem bulunamadı")
    return tx


def create(
    db: Session, user: models.User, payload: schemas.TransactionCreate
) -> tuple[models.Transaction, list[schemas.BudgetAlert]]:
    """İşlemi kaydeder; kayıttan sonra oluşan bütçe uyarılarıyla birlikte döner.

    Kategori verilmeyen gider yerel modelle kategorilenir (kullanıcı doğrulamamıştır).
    """
    category = payload.category
    auto = False
    suggested = payload.suggested_category
    confidence = payload.suggestion_confidence
    model_name = payload.suggestion_model
    if category is None and payload.type == models.TxType.expense:
        category, confidence, model_name = categorizer.categorize(payload.note)
        suggested = category
        auto = True
    elif category is None:
        category = models.CategoryEnum.diger

    tx = models.Transaction(
        user_id=user.id,
        amount=payload.amount,
        type=payload.type,
        category=category,
        auto_categorized=auto,
        suggested_category=suggested,
        suggestion_confidence=confidence,
        suggestion_model=model_name,
        note=payload.note,
        occurred_on=payload.occurred_on,
    )
    db.add(tx)
    if payload.is_recurring:
        # Geçmiş bir tarihle başlatılan seride aradaki aylar da hemen eklenir.
        recurring.materialize(db, recurring.start_series(db, tx))
    db.commit()
    db.refresh(tx)
    return tx, coach.budget_alerts_after_save(db, user, tx)


def update(
    db: Session, user: models.User, tx_id: int, payload: schemas.TransactionUpdate
) -> tuple[models.Transaction, list[schemas.BudgetAlert]]:
    """Gönderilen alanları günceller (null gönderilen alan değişmez).

    is_recurring: false seriyi durdurur, true işlemi yeni bir serinin başlangıcı yapar.
    Aktif bir seriye ait işlemde tutar, tür, kategori veya not değişirse sonraki aylar
    da yeni değerle üretilir.
    """
    tx = get_owned(db, user.id, tx_id)
    data = {k: v for k, v in payload.model_dump(exclude_unset=True).items() if v is not None}
    wants_recurring = data.pop("is_recurring", None)
    previous = (tx.category, tx.type, tx.amount, tx.occurred_on)
    for field, value in data.items():
        setattr(tx, field, value)

    series = tx.series
    active = series is not None and series.active
    if wants_recurring is False and active:
        recurring.stop_series(db, series)
    elif wants_recurring is True and not active:
        if tx.occurred_on < date.today() - timedelta(days=schemas.MAX_RECURRING_PAST_DAYS):
            raise RuleViolation("Tekrarlayan işlem en fazla 12 ay önceden başlatılabilir")
        recurring.materialize(db, recurring.start_series(db, tx))
    elif active and any(field in data for field in recurring.TEMPLATE_FIELDS):
        recurring.update_template(series, tx)

    db.commit()
    db.refresh(tx)
    return tx, coach.budget_alerts_after_save(db, user, tx, previous)


def delete(db: Session, user_id: int, tx_id: int) -> None:
    """İşlemi siler. Seriye aitse seri devam eder ama silinen ay yeniden üretilmez.
    Bulunamayan işlem sessizce yok sayılır."""
    tx = db.query(Tx).filter(Tx.id == tx_id, Tx.user_id == user_id).first()
    if tx is not None:
        db.delete(tx)
        db.commit()


def filtered(
    db: Session,
    user_id: int,
    *,
    category: Optional[models.CategoryEnum] = None,
    type: Optional[models.TxType] = None,
    month: Optional[tuple[int, int]] = None,
    q: Optional[str] = None,
) -> Query:
    query = db.query(Tx).filter(Tx.user_id == user_id)
    if category is not None:
        query = query.filter(Tx.category == category)
    if type is not None:
        query = query.filter(Tx.type == type)
    if month:
        query = query.filter(*month_filter(*month))
    if q:
        query = query.filter(Tx.note.ilike(f"%{q}%"))
    return query


def newest_first(query: Query) -> Query:
    return query.order_by(Tx.occurred_on.desc(), Tx.id.desc())


def month_totals(db: Session, user_id: int) -> list[schemas.MonthSummary]:
    """İşlem olan aylar (yeniden eskiye) ve her ayın gelir/gider toplamı."""
    year = extract("year", Tx.occurred_on)
    month = extract("month", Tx.occurred_on)
    rows = (
        db.query(year, month, Tx.type, func.sum(Tx.amount), func.count(Tx.id))
        .filter(Tx.user_id == user_id)
        .group_by(year, month, Tx.type)
        .all()
    )
    months: dict[tuple[int, int], dict] = {}
    for y, m, kind, total, count in rows:
        item = months.setdefault(
            (int(y), int(m)), {"income": ZERO, "expense": ZERO, "count": 0}
        )
        item["income" if kind == models.TxType.income else "expense"] += total
        item["count"] += count
    return [
        schemas.MonthSummary(
            month=f"{y:04d}-{m:02d}",
            income=v["income"],
            expense=v["expense"],
            count=v["count"],
        )
        for (y, m), v in sorted(months.items(), reverse=True)
    ]


def summary(db: Session, user_id: int, year: int, mon: int) -> schemas.TransactionSummary:
    """Bakiye ve toplamlar (tüm işlemler) ile istenen ayın kategori dağılımı."""
    total = func.coalesce(func.sum(Tx.amount), ZERO)
    this_month = month_filter(year, mon)

    def totals_by_type(*filters) -> dict[models.TxType, Decimal]:
        rows = (
            db.query(Tx.type, total)
            .filter(Tx.user_id == user_id, *filters)
            .group_by(Tx.type)
            .all()
        )
        return {kind: amount for kind, amount in rows}

    all_time = totals_by_type()
    month = totals_by_type(*this_month)
    by_category = (
        db.query(Tx.category, total)
        .filter(Tx.user_id == user_id, Tx.type == models.TxType.expense, *this_month)
        .group_by(Tx.category)
        .order_by(total.desc())
        .all()
    )

    income = all_time.get(models.TxType.income, ZERO)
    expense = all_time.get(models.TxType.expense, ZERO)
    return schemas.TransactionSummary(
        balance=income - expense,
        total_income=income,
        total_expense=expense,
        month=f"{year:04d}-{mon:02d}",
        month_income=month.get(models.TxType.income, ZERO),
        month_expense=month.get(models.TxType.expense, ZERO),
        month_by_category=[
            schemas.CategoryTotal(category=cat.value, total=amount)
            for cat, amount in by_category
        ],
    )
