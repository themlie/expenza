"""Analitik uçları (İP-4) — harcama tahmini, anomali tespiti ve içgörüler.

Toplamlar veritabanında hesaplanır ve yalnızca gereken sütunlar okunur. Önceki sürüm
kullanıcının bütün işlemlerini ORM nesnesi olarak belleğe alıyordu; 5.000 işlemli bir
kullanıcıda tahmin ucu p50 1,1 saniyeye çıkıyordu (tools/load_test.py).
"""
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import extract, func
from sqlalchemy.orm import Session

from .. import models, schemas
from ..auth import get_current_user
from ..database import get_db
from ..ml import analytics, insights

router = APIRouter(prefix="/analytics", tags=["analytics"])

Tx = models.Transaction


@router.get("/forecast", response_model=schemas.ForecastResponse)
def forecast(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    today = date.today()
    year = extract("year", Tx.occurred_on)
    month = extract("month", Tx.occurred_on)
    expenses = (Tx.user_id == user.id, Tx.type == models.TxType.expense)

    monthly = {
        (int(y), int(m)): float(total)
        for y, m, total in db.query(year, month, func.sum(Tx.amount))
        .filter(*expenses)
        .group_by(year, month)
    }
    cur_by_cat = {
        category.value: float(total)
        for category, total in db.query(Tx.category, func.sum(Tx.amount))
        .filter(*expenses, year == today.year, month == today.month)
        .group_by(Tx.category)
    }
    return analytics.forecast_from_totals(monthly, cur_by_cat, today)


@router.get("/anomalies", response_model=list[schemas.AnomalyItem])
def anomalies(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    # Z-skoru her harcamaya bakar; yine de yalnızca gereken sütunlar okunur.
    rows = (
        db.query(Tx.id, Tx.amount, Tx.type, Tx.category, Tx.note, Tx.occurred_on)
        .filter(Tx.user_id == user.id, Tx.type == models.TxType.expense)
        .all()
    )
    return analytics.detect_anomalies(rows)


@router.get("/insights", response_model=list[schemas.InsightItem])
def get_insights(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    # İçgörüler bu ay ile geçen ayı karşılaştırır; daha eski kayıtlar okunmaz.
    previous_month_start = (date.today().replace(day=1) - timedelta(days=1)).replace(day=1)
    rows = (
        db.query(Tx.type, Tx.amount, Tx.category, Tx.occurred_on)
        .filter(Tx.user_id == user.id, Tx.occurred_on >= previous_month_start)
        .all()
    )
    return insights.generate_insights(rows)
