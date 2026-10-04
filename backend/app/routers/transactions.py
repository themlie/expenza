"""İşlem (gelir/gider) uçları. Kategori verilmezse hero model otomatik atar.

İş kuralları app/services/transactions.py'de; burada istek ve cevap biçimi var.
"""
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.orm import Session

from .. import export, models, schemas
from ..auth import get_current_user
from ..database import get_db
from ..services import transactions as service

router = APIRouter(prefix="/transactions", tags=["transactions"])


def _parse_month(month: Optional[str]) -> Optional[tuple[int, int]]:
    """'YYYY-MM' -> (yıl, ay). Boşsa None; biçim hatalıysa 400."""
    if not month:
        return None
    try:
        year_s, mon_s = month.split("-")
        year, mon = int(year_s), int(mon_s)
        if not 1 <= mon <= 12:
            raise ValueError
        return year, mon
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="month formatı YYYY-MM olmalı")


def _saved(tx: models.Transaction, alerts: list) -> schemas.TransactionSaved:
    out = schemas.TransactionSaved.model_validate(tx, from_attributes=True)
    out.budget_alerts = alerts
    return out


@router.post("", response_model=schemas.TransactionSaved, status_code=201)
def create_transaction(
    payload: schemas.TransactionCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return _saved(*service.create(db, user, payload))


@router.get("", response_model=list[schemas.TransactionOut])
def list_transactions(
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),  # sayfalama: atlanacak kayıt sayısı
    category: Optional[models.CategoryEnum] = None,
    type: Optional[models.TxType] = None,
    month: Optional[str] = None,  # "YYYY-MM"
    q: Optional[str] = None,      # not metninde arama
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    query = service.filtered(
        db, user.id, category=category, type=type, month=_parse_month(month), q=q
    )
    return service.newest_first(query).offset(offset).limit(limit).all()


@router.get("/export", response_class=Response)
def export_transactions(
    month: Optional[str] = None,  # "YYYY-MM"; boşsa bütün işlemler
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """İşlemleri (eskiden yeniye) CSV dosyası olarak indirir."""
    parsed = _parse_month(month)
    rows = (
        service.filtered(db, user.id, month=parsed)
        .order_by(models.Transaction.occurred_on, models.Transaction.id)
        .all()
    )
    suffix = f"-{parsed[0]:04d}-{parsed[1]:02d}" if parsed else ""
    return Response(
        content=export.transactions_csv(rows),
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="expenza-islemler{suffix}.csv"'
        },
    )


@router.get("/months", response_model=list[schemas.MonthSummary])
def transaction_months(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """İşlem olan aylar (yeniden eskiye) ve her ayın gelir/gider toplamı."""
    return service.month_totals(db, user.id)


@router.get("/summary", response_model=schemas.TransactionSummary)
def transaction_summary(
    month: Optional[str] = None,  # "YYYY-MM"; boşsa içinde bulunulan ay
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Bakiye ve toplamlar (tüm işlemler) ile istenen ayın kategori dağılımı."""
    today = date.today()
    year, mon = _parse_month(month) or (today.year, today.month)
    return service.summary(db, user.id, year, mon)


@router.put("/{tx_id}", response_model=schemas.TransactionSaved)
def update_transaction(
    tx_id: int,
    payload: schemas.TransactionUpdate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Gönderilen alanları günceller (null gönderilen alan değişmez).

    is_recurring: false seriyi durdurur, true işlemi yeni bir serinin başlangıcı yapar.
    """
    return _saved(*service.update(db, user, tx_id, payload))


@router.delete("/{tx_id}", status_code=204)
def delete_transaction(
    tx_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """İşlemi siler. Seriye aitse seri devam eder ama silinen ay yeniden üretilmez."""
    service.delete(db, user.id, tx_id)
    return None
