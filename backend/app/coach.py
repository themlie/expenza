"""Proaktif finans koçu: bütçe uyarıları, bütçe hızı tahmini ve hedef planı.

Uyarılar saklanmaz, her istekte o anki verilerden hesaplanır. Kullanıcının kapattığı
uyarılar dismissed_alerts tablosunda tutulur. Mesajlarda tutar yazılmaz; tutar ayrı
alanda döner ve istemci kendi para biriminde gösterir.
"""
import calendar
import math
from datetime import date, timedelta
from typing import Optional

from sqlalchemy import extract, func
from sqlalchemy.orm import Session

from . import models, recurring, schemas
from .ml import analytics

WARN_RATIO = 0.8
# Ayın ilk günlerinde günlük ortalama çok oynak; bütçe hızı bu günden sonra tahmin edilir.
PACE_MIN_DAY = 5
GOAL_SOON_DAYS = 30
RECURRING_SOON_DAYS = 3
ANOMALY_RECENT_DAYS = 7
# Hedefte beklenen ilerlemenin bu kadar gerisi "geride" sayılır.
GOAL_BEHIND_TOLERANCE = 0.05

Tx = models.Transaction
# Harcama sözlükleri ve bütçeler kategori adıyla ("Yemek", "Toplam") eşleştirilir.
TOTAL = models.TOTAL_BUDGET.value


def _pct(ratio: float) -> int:
    return int(round(ratio * 100))


def _label(category: str) -> str:
    return "Aylık toplam bütçe" if category == TOTAL else f"{category} bütçesi"


def _month_filter(year: int, month: int):
    return (
        extract("year", Tx.occurred_on) == year,
        extract("month", Tx.occurred_on) == month,
    )


def month_spending(
    db: Session, user_id: int, year: int, month: int, fixed_only: bool = False
) -> dict[str, float]:
    """Ayın kategori adına göre giderleri; "Toplam" anahtarı hepsinin toplamıdır.

    fixed_only: yalnızca tekrarlayan serilerden gelen giderler.
    """
    query = db.query(Tx.category, func.coalesce(func.sum(Tx.amount), 0.0)).filter(
        Tx.user_id == user_id,
        Tx.type == models.TxType.expense,
        *_month_filter(year, month),
    )
    if fixed_only:
        query = query.filter(Tx.series_id.isnot(None))
    spent = {cat.value: float(total) for cat, total in query.group_by(Tx.category)}
    spent[TOTAL] = sum(spent.values())
    return spent


def _budgets(db: Session, user_id: int) -> list[models.Budget]:
    return db.query(models.Budget).filter(models.Budget.user_id == user_id).all()


# ---- İşlem kaydedilince ----
def budget_alerts_after_save(
    db: Session,
    user: models.User,
    tx: models.Transaction,
    previous: Optional[tuple[models.CategoryEnum, models.TxType, float, date]] = None,
    today: Optional[date] = None,
) -> list[schemas.BudgetAlert]:
    """Kaydedilen gider bu ayın bir bütçesini %80'in üstüne çıkardıysa uyarı döner.

    previous: güncellemede işlemin eski (kategori, tür, tutar, tarih) değerleri; "eşik
    bu işlemle mi geçildi" sorusunu cevaplamak için kullanılır.
    """
    today = today or date.today()
    if not user.alerts_enabled or tx.type != models.TxType.expense:
        return []
    if (tx.occurred_on.year, tx.occurred_on.month) != (today.year, today.month):
        return []

    spent = month_spending(db, user.id, today.year, today.month)

    def counted_before(category: str) -> float:
        """Bu kayıttan önce kategoriye sayılan tutar (güncellemede eski değer)."""
        if previous is None:
            return 0.0
        old_cat, old_type, old_amount, old_day = previous
        same_month = (old_day.year, old_day.month) == (today.year, today.month)
        if old_type != models.TxType.expense or not same_month:
            return 0.0
        return old_amount if category in (old_cat.value, TOTAL) else 0.0

    alerts = []
    for budget in _budgets(db, user.id):
        key = budget.category.value
        if key not in (tx.category.value, TOTAL) or budget.monthly_limit <= 0:
            continue
        after = spent.get(key, 0.0)
        before = after - tx.amount + counted_before(key)
        ratio = after / budget.monthly_limit
        if ratio < WARN_RATIO:
            continue
        exceeded = ratio >= 1
        threshold = 1.0 if exceeded else WARN_RATIO
        label = _label(key)
        alerts.append(
            schemas.BudgetAlert(
                category=key,
                limit=budget.monthly_limit,
                spent=round(after, 2),
                ratio=round(ratio, 3),
                level="exceeded" if exceeded else "warning",
                crossed=before / budget.monthly_limit < threshold,
                message=(
                    f"{label} aşıldı: %{_pct(ratio)}."
                    if exceeded
                    else f"{label}: %{_pct(ratio)} kullanıldı."
                ),
            )
        )
    # Önce kategori, sonra toplam bütçe.
    alerts.sort(key=lambda a: a.category == TOTAL)
    return alerts


# ---- Bütçe hızı ----
def _upcoming_recurring(
    db: Session, user_id: int, today: date
) -> list[tuple[date, models.RecurringSeries]]:
    """Aktif gider serilerinin bugünden sonraki ilk tarihi."""
    series = (
        db.query(models.RecurringSeries)
        .filter(
            models.RecurringSeries.user_id == user_id,
            models.RecurringSeries.active.is_(True),
            models.RecurringSeries.type == models.TxType.expense,
        )
        .all()
    )
    result = []
    for s in series:
        due = recurring.next_occurrence(s, today)
        if due is not None:
            result.append((due, s))
    return result


def pace_exceed_day(
    limit: float,
    fixed: float,
    variable: float,
    upcoming: list[tuple[date, float]],
    today: date,
) -> Optional[int]:
    """Bu harcama hızıyla bütçenin ayın kaçıncı günü aşılacağı (aşılmayacaksa None).

    Tekrarlayan ödemeler (kira, abonelik) günlük ortalamayı şişirmesin diye ayrı tutulur:
    gerçekleşenler sabit, bu ay kalanlar kendi günlerinde eklenir. Geri kalan harcama
    bugüne kadarki günlük ortalamayla devam ettirilir.
    """
    days = calendar.monthrange(today.year, today.month)[1]
    daily = variable / today.day
    for day in range(today.day + 1, days + 1):
        due = sum(amount for when, amount in upcoming if when.day <= day)
        if fixed + due + daily * day > limit:
            return day
    return None


def _pace_alerts(
    db: Session, user_id: int, today: date, spent: dict, budgets: list
) -> list[schemas.AlertOut]:
    if today.day < PACE_MIN_DAY:
        return []
    fixed = month_spending(db, user_id, today.year, today.month, fixed_only=True)
    this_month = [
        (due, s)
        for due, s in _upcoming_recurring(db, user_id, today)
        if (due.year, due.month) == (today.year, today.month)
    ]
    alerts = []
    for b in budgets:
        key = b.category.value
        total = spent.get(key, 0.0)
        if b.monthly_limit <= 0 or total / b.monthly_limit >= WARN_RATIO:
            continue  # zaten bütçe uyarısı var
        fixed_part = fixed.get(key, 0.0)
        upcoming = [
            (due, s.amount)
            for due, s in this_month
            if key == TOTAL or s.category.value == key
        ]
        day = pace_exceed_day(
            b.monthly_limit, fixed_part, total - fixed_part, upcoming, today
        )
        if day is None:
            continue
        days = calendar.monthrange(today.year, today.month)[1]
        projected = (
            total
            + sum(amount for _, amount in upcoming)
            + (total - fixed_part) / today.day * (days - today.day)
        )
        alerts.append(
            schemas.AlertOut(
                id=f"pace:{key}:{today:%Y-%m}",
                kind="budget_pace",
                level="warning",
                title=f"{_label(key)} bu hızla aşılacak",
                message=f"Bu harcama hızıyla bütçe ayın {day}. günü dolacak.",
                category=key,
                amount=round(projected, 2),
            )
        )
    return alerts


# ---- Hedef planı ----
def goal_plan(goal: models.Goal, today: Optional[date] = None) -> dict:
    """Hedef kartı için hesaplanan alanlar (bkz. schemas.GoalOut)."""
    today = today or date.today()
    target = goal.target_amount
    progress = 0.0 if target <= 0 else min(goal.current_amount / target, 1.0)
    remaining = max(target - goal.current_amount, 0.0)
    plan = {
        "progress": progress,
        "remaining": round(remaining, 2),
        "days_left": None,
        "months_left": None,
        "monthly_needed": None,
        "status": "no_deadline",
    }
    if goal.deadline is not None:
        days_left = (goal.deadline - today).days
        plan["days_left"] = days_left
        if days_left >= 0:
            months_left = max(1, math.ceil(days_left / 30.4375))
            plan["months_left"] = months_left
            plan["monthly_needed"] = round(remaining / months_left, 2)
    if remaining <= 0:
        plan["status"] = "completed"
    elif goal.deadline is None:
        plan["status"] = "no_deadline"
    elif goal.deadline < today:
        plan["status"] = "overdue"
    else:
        start = goal.created_at.date() if goal.created_at else today
        total_days = (goal.deadline - start).days
        elapsed = (today - start).days
        expected = 1.0 if total_days <= 0 else min(max(elapsed / total_days, 0.0), 1.0)
        plan["status"] = (
            "behind" if progress + GOAL_BEHIND_TOLERANCE < expected else "on_track"
        )
    return plan


def _goal_alerts(db: Session, user_id: int, today: date) -> list[schemas.AlertOut]:
    goals = (
        db.query(models.Goal)
        .filter(models.Goal.user_id == user_id, models.Goal.deadline.isnot(None))
        .all()
    )
    alerts = []
    for g in goals:
        plan = goal_plan(g, today)
        pct = _pct(plan["progress"])
        if plan["status"] == "overdue":
            alerts.append(
                schemas.AlertOut(
                    id=f"goal-overdue:{g.id}",
                    kind="goal",
                    level="danger",
                    title=f"{g.title} hedefinin süresi doldu",
                    message=f"Tamamlanan: %{pct}. Son tarihi uzatabilir ya da hedefi güncelleyebilirsin.",
                    amount=plan["remaining"],
                    ref_id=g.id,
                    due_on=g.deadline,
                )
            )
        elif plan["status"] == "behind" and plan["days_left"] <= GOAL_SOON_DAYS:
            days = plan["days_left"]
            alerts.append(
                schemas.AlertOut(
                    id=f"goal-soon:{g.id}:{g.deadline.isoformat()}",
                    kind="goal",
                    level="warning",
                    title=(
                        f"{g.title} hedefinin son günü bugün"
                        if days == 0
                        else f"{g.title} hedefine {days} gün kaldı"
                    ),
                    message=f"Tamamlanan: %{pct}, plana göre gerideysin.",
                    amount=plan["monthly_needed"],
                    ref_id=g.id,
                    due_on=g.deadline,
                )
            )
    return alerts


# ---- Diğer uyarılar ----
def _budget_alerts(spent: dict, budgets: list, today: date) -> list[schemas.AlertOut]:
    alerts = []
    for b in budgets:
        if b.monthly_limit <= 0:
            continue
        key = b.category.value
        total = spent.get(key, 0.0)
        ratio = total / b.monthly_limit
        if ratio < WARN_RATIO:
            continue
        exceeded = ratio >= 1
        label = _label(key)
        alerts.append(
            schemas.AlertOut(
                id=f"budget:{key}:{today:%Y-%m}:{100 if exceeded else 80}",
                kind="budget",
                level="danger" if exceeded else "warning",
                title=f"{label} aşıldı" if exceeded else f"{label} dolmak üzere",
                message=f"Bu ay limitin %{_pct(ratio)} seviyesine ulaştın.",
                category=key,
                amount=round(total, 2),
            )
        )
    return alerts


def _anomaly_alerts(db: Session, user_id: int, today: date) -> list[schemas.AlertOut]:
    rows = (
        db.query(Tx.id, Tx.amount, Tx.type, Tx.category, Tx.note, Tx.occurred_on)
        .filter(Tx.user_id == user_id, Tx.type == models.TxType.expense)
        .all()
    )
    since = today - timedelta(days=ANOMALY_RECENT_DAYS)
    alerts = []
    for a in analytics.detect_anomalies(rows):
        if date.fromisoformat(a["occurred_on"]) < since:
            continue
        alerts.append(
            schemas.AlertOut(
                id=f"anomaly:{a['transaction_id']}",
                kind="anomaly",
                level="warning" if a["severity"] == "high" else "info",
                title="Olağandışı harcama",
                message=(
                    f"{a['note'] or a['category']}: {a['category']} kategorisindeki "
                    "olağan harcamalarının çok üstünde."
                ),
                category=a["category"],
                amount=a["amount"],
                ref_id=a["transaction_id"],
                due_on=date.fromisoformat(a["occurred_on"]),
            )
        )
    return alerts


def _recurring_alerts(db: Session, user_id: int, today: date) -> list[schemas.AlertOut]:
    alerts = []
    for due, s in _upcoming_recurring(db, user_id, today):
        days = (due - today).days
        if days > RECURRING_SOON_DAYS:
            continue
        alerts.append(
            schemas.AlertOut(
                id=f"recurring:{s.id}:{due.isoformat()}",
                kind="recurring",
                level="info",
                title=f"{s.note or s.category.value} ödemesi yaklaşıyor",
                message=(
                    "Yarın otomatik olarak eklenecek."
                    if days == 1
                    else f"{days} gün sonra otomatik olarak eklenecek."
                ),
                category=s.category.value,
                amount=s.amount,
                ref_id=s.id,
                due_on=due,
            )
        )
    return alerts


LEVEL_ORDER = {"danger": 0, "warning": 1, "info": 2}


def collect_alerts(
    db: Session, user: models.User, today: Optional[date] = None
) -> list[schemas.AlertOut]:
    """Kullanıcının o anki uyarıları, önemliden önemsize. Kapatılanlar dahil edilmez."""
    if not user.alerts_enabled:
        return []
    today = today or date.today()
    spent = month_spending(db, user.id, today.year, today.month)
    budgets = _budgets(db, user.id)
    alerts = (
        _budget_alerts(spent, budgets, today)
        + _pace_alerts(db, user.id, today, spent, budgets)
        + _goal_alerts(db, user.id, today)
        + _anomaly_alerts(db, user.id, today)
        + _recurring_alerts(db, user.id, today)
    )
    dismissed = {
        alert_id
        for (alert_id,) in db.query(models.DismissedAlert.alert_id).filter(
            models.DismissedAlert.user_id == user.id
        )
    }
    alerts = [a for a in alerts if a.id not in dismissed]
    alerts.sort(key=lambda a: LEVEL_ORDER[a.level])
    return alerts
