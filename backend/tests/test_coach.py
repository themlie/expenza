"""Proaktif koç: kayıt anındaki bütçe uyarıları, uyarı listesi ve hedef planı."""
from datetime import date, datetime, timedelta

from app import coach, models
from app.database import SessionLocal


def _budget(client, h, category, limit):
    client.post("/budgets", json={"category": category, "monthly_limit": limit}, headers=h)


def _user(email):
    with SessionLocal() as db:
        u = db.query(models.User).filter(models.User.email == email).one()
        db.expunge(u)
        return u


# ---- Kayıt anındaki bütçe uyarısı ----
def test_save_reports_budget_threshold_crossings(client, user, add_tx):
    h = user["headers"]
    _budget(client, h, "Yemek", 100)

    assert add_tx(h, amount=50)["budget_alerts"] == []

    alert = add_tx(h, amount=35)["budget_alerts"][0]
    assert alert["category"] == "Yemek" and alert["level"] == "warning"
    assert alert["crossed"] is True and alert["ratio"] == 0.85
    assert alert["message"] == "Yemek bütçesi: %85 kullanıldı."

    alert = add_tx(h, amount=5)["budget_alerts"][0]
    assert alert["crossed"] is False  # eşik zaten geçilmişti

    alert = add_tx(h, amount=20)["budget_alerts"][0]
    assert alert["level"] == "exceeded" and alert["crossed"] is True
    assert alert["spent"] == 110
    assert "₺" not in alert["message"]


def test_total_budget_and_other_categories(client, user, add_tx):
    h = user["headers"]
    _budget(client, h, "Toplam", 100)
    _budget(client, h, "Ulaşım", 1000)
    alerts = add_tx(h, amount=90, category="Yemek")["budget_alerts"]
    assert [a["category"] for a in alerts] == ["Toplam"]
    assert alerts[0]["message"].startswith("Aylık toplam bütçe")


def test_no_alert_for_income_other_months_or_when_disabled(client, user, add_tx):
    h = user["headers"]
    _budget(client, h, "Yemek", 100)
    last_month = date.today().replace(day=1) - timedelta(days=1)
    assert add_tx(h, amount=500, occurred_on=last_month.isoformat())["budget_alerts"] == []
    assert add_tx(h, amount=500, type="income")["budget_alerts"] == []

    client.put("/auth/me", json={"alerts_enabled": False}, headers=h)
    assert add_tx(h, amount=500)["budget_alerts"] == []
    assert client.get("/alerts", headers=h).json() == []


def test_update_that_crosses_threshold_is_reported(client, user, add_tx):
    h = user["headers"]
    _budget(client, h, "Yemek", 100)
    tx = add_tx(h, amount=50)
    r = client.put(f"/transactions/{tx['id']}", json={"amount": 90}, headers=h)
    alert = r.json()["budget_alerts"][0]
    assert alert["crossed"] is True and alert["spent"] == 90

    # Not değişikliği eşiği yeniden "geçmiş" saymaz.
    r = client.put(f"/transactions/{tx['id']}", json={"note": "akşam"}, headers=h)
    assert r.json()["budget_alerts"][0]["crossed"] is False


# ---- Uyarı listesi ----
def test_budget_alerts_and_dismiss(client, user, add_tx):
    h = user["headers"]
    _budget(client, h, "Yemek", 100)
    add_tx(h, amount=85)
    month = f"{date.today():%Y-%m}"

    alerts = client.get("/alerts", headers=h).json()
    assert [a["id"] for a in alerts] == [f"budget:Yemek:{month}:80"]
    assert alerts[0]["level"] == "warning" and alerts[0]["amount"] == 85

    assert client.post("/alerts/dismiss", json={"id": alerts[0]["id"]}, headers=h).status_code == 204
    # İkinci kez kapatmak hata vermez.
    assert client.post("/alerts/dismiss", json={"id": alerts[0]["id"]}, headers=h).status_code == 204
    assert client.get("/alerts", headers=h).json() == []

    # Bütçe aşılınca yeni (farklı kimlikli) uyarı gelir.
    add_tx(h, amount=30)
    alerts = client.get("/alerts", headers=h).json()
    assert [(a["id"], a["level"]) for a in alerts] == [(f"budget:Yemek:{month}:100", "danger")]


def test_pace_exceed_day():
    today = date(2026, 10, 10)
    # Günde 10 harcanıyor: 300'lük bütçe 31'inde aşılır (30 * 10 = 300 henüz aşmıyor).
    assert coach.pace_exceed_day(300, 0, 100, [], today) == 31
    assert coach.pace_exceed_day(295, 0, 100, [], today) == 30
    assert coach.pace_exceed_day(400, 0, 100, [], today) is None
    # Kira ayın 15'inde gelecek: günlük ortalamaya katılmaz ama o gün eklenir.
    assert coach.pace_exceed_day(500, 0, 100, [(date(2026, 10, 15), 400)], today) == 15


def test_pace_alert_ignores_rent_in_daily_average(client, user, add_tx):
    h = user["headers"]
    today = date.today()
    _budget(client, h, "Faturalar", 5000)
    # Ayın başında ödenen kira tekrarlayan bir seriden geliyor: günlük ortalamayı şişirmemeli.
    add_tx(h, amount=2000, category="Faturalar", occurred_on=today.replace(day=1).isoformat(),
           is_recurring=True)
    add_tx(h, amount=100, category="Faturalar", occurred_on=today.replace(day=1).isoformat())

    with SessionLocal() as db:
        u = db.query(models.User).filter(models.User.email == user["email"]).one()
        mid = today.replace(day=10)
        assert coach.collect_alerts(db, u, mid) == []
        # Değişken harcama artınca bütçe bu hızla aşılacak.
        db.add(models.Transaction(
            user_id=u.id, amount=1100, type=models.TxType.expense,
            category=models.CategoryEnum.faturalar, occurred_on=today.replace(day=2),
        ))
        db.commit()
        alerts = coach.collect_alerts(db, u, mid)
    assert [a.kind for a in alerts] == ["budget_pace"]
    assert alerts[0].message.startswith("Bu harcama hızıyla bütçe ayın ")


def test_upcoming_recurring_payment_alert(client, user):
    today = date.today()
    mid = today.replace(day=10)
    prev = today.replace(day=1) - timedelta(days=1)
    with SessionLocal() as db:
        u = db.query(models.User).filter(models.User.email == user["email"]).one()
        db.add(models.RecurringSeries(
            user_id=u.id, amount=7500, type=models.TxType.expense,
            category=models.CategoryEnum.faturalar, note="Kira", day_of_month=12,
            start_on=prev.replace(day=12), last_generated_on=prev.replace(day=12),
        ))
        db.commit()
        alerts = coach.collect_alerts(db, u, mid)
    assert len(alerts) == 1
    a = alerts[0]
    assert a.kind == "recurring" and a.title == "Kira ödemesi yaklaşıyor"
    assert a.message == "2 gün sonra otomatik olarak eklenecek."
    assert a.amount == 7500 and a.due_on == today.replace(day=12)


def test_goal_alerts_for_overdue_and_behind(client, user):
    h = user["headers"]
    today = date.today()
    overdue = client.post("/goals", json={"title": "Telefon", "target_amount": 1000}, headers=h).json()
    behind = client.post(
        "/goals",
        json={"title": "Tatil", "target_amount": 1000,
              "deadline": (today + timedelta(days=10)).isoformat()},
        headers=h,
    ).json()
    with SessionLocal() as db:
        db.get(models.Goal, overdue["id"]).deadline = today - timedelta(days=1)
        # 100 gün önce başlamış, %0'da: plana göre geride.
        db.get(models.Goal, behind["id"]).created_at = datetime.now() - timedelta(days=100)
        db.commit()

    alerts = client.get("/alerts", headers=h).json()
    assert [(a["kind"], a["level"], a["ref_id"]) for a in alerts] == [
        ("goal", "danger", overdue["id"]),
        ("goal", "warning", behind["id"]),
    ]
    assert alerts[1]["title"] == "Tatil hedefine 10 gün kaldı"


# ---- Hedef planı ----
def _goal(current, target=1200, deadline=None, created=None):
    return models.Goal(
        title="X", target_amount=target, current_amount=current, deadline=deadline,
        created_at=created or datetime(2026, 1, 1),
    )


def test_goal_plan_statuses():
    today = date(2026, 7, 1)
    assert coach.goal_plan(_goal(1200), today)["status"] == "completed"
    assert coach.goal_plan(_goal(0), today)["status"] == "no_deadline"
    assert coach.goal_plan(_goal(0, deadline=date(2026, 6, 1)), today)["status"] == "overdue"
    # Ocak'tan Aralık sonuna: Temmuz başında yaklaşık %50 beklenir.
    year_end = date(2026, 12, 31)
    assert coach.goal_plan(_goal(600, deadline=year_end), today)["status"] == "on_track"
    assert coach.goal_plan(_goal(300, deadline=year_end), today)["status"] == "behind"


def test_goal_plan_monthly_needed():
    plan = coach.goal_plan(_goal(200, target=1200, deadline=date(2026, 10, 30)), date(2026, 7, 1))
    assert plan["remaining"] == 1000
    assert plan["days_left"] == 121 and plan["months_left"] == 4
    assert plan["monthly_needed"] == 250


def test_goal_update_and_withdraw(client, user):
    h = user["headers"]
    deadline = (date.today() + timedelta(days=90)).isoformat()
    goal = client.post("/goals", json={"title": "Tatil", "target_amount": 1000}, headers=h).json()
    assert goal["status"] == "no_deadline" and goal["monthly_needed"] is None

    r = client.put(f"/goals/{goal['id']}",
                   json={"title": "Yaz tatili", "target_amount": 1500, "deadline": deadline},
                   headers=h)
    body = r.json()
    assert body["title"] == "Yaz tatili" and body["deadline"] == deadline
    assert body["months_left"] == 3 and body["monthly_needed"] == 500

    # Yalnızca gönderilen alan değişir; deadline: null son tarihi kaldırır.
    body = client.put(f"/goals/{goal['id']}", json={"title": "Tatil"}, headers=h).json()
    assert body["deadline"] == deadline and body["target_amount"] == 1500
    body = client.put(f"/goals/{goal['id']}", json={"deadline": None}, headers=h).json()
    assert body["deadline"] is None

    client.post(f"/goals/{goal['id']}/contribute", json={"amount": 400}, headers=h)
    r = client.post(f"/goals/{goal['id']}/withdraw", json={"amount": 500}, headers=h)
    assert r.status_code == 400
    body = client.post(f"/goals/{goal['id']}/withdraw", json={"amount": 150}, headers=h).json()
    assert body["current_amount"] == 250


def test_goal_deadline_cannot_be_in_the_past(client, user):
    past = (date.today() - timedelta(days=1)).isoformat()
    r = client.post("/goals", json={"title": "X", "target_amount": 10, "deadline": past},
                    headers=user["headers"])
    assert r.status_code == 422
