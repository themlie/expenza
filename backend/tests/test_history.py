"""İşlem tarihi sınırları, sayfalama, ay listesi ve aylık özet."""
from datetime import date, timedelta


def _month_start(day: date, back: int = 0) -> date:
    year, month = day.year, day.month - back
    while month < 1:
        year, month = year - 1, month + 12
    return date(year, month, 1)


def test_past_date_is_accepted(client, user, add_tx):
    day = date.today() - timedelta(days=40)
    tx = add_tx(user["headers"], occurred_on=day.isoformat())
    assert tx["occurred_on"] == day.isoformat()


def test_future_date_is_rejected(client, user):
    body = {"amount": 10, "category": "Yemek",
            "occurred_on": (date.today() + timedelta(days=3)).isoformat()}
    r = client.post("/transactions", json=body, headers=user["headers"])
    assert r.status_code == 422
    assert "ileri bir gün" in r.text


def test_tomorrow_is_allowed_for_time_zone_difference(client, user, add_tx):
    add_tx(user["headers"], occurred_on=(date.today() + timedelta(days=1)).isoformat())


def test_dates_older_than_ten_years_are_rejected(client, user):
    body = {"amount": 10, "category": "Yemek",
            "occurred_on": (date.today() - timedelta(days=3700)).isoformat()}
    assert client.post("/transactions", json=body, headers=user["headers"]).status_code == 422


def test_update_cannot_move_date_to_the_future(client, user, add_tx):
    tx = add_tx(user["headers"])
    r = client.put(
        f"/transactions/{tx['id']}",
        json={"occurred_on": (date.today() + timedelta(days=5)).isoformat()},
        headers=user["headers"],
    )
    assert r.status_code == 422


def test_recurring_start_is_limited_to_twelve_months(client, user, add_tx):
    old = (date.today() - timedelta(days=400)).isoformat()
    body = {"amount": 10, "type": "income", "occurred_on": old, "is_recurring": True}
    r = client.post("/transactions", json=body, headers=user["headers"])
    assert r.status_code == 422
    assert "12 ay" in r.text

    tx = add_tx(user["headers"], occurred_on=old)
    r = client.put(f"/transactions/{tx['id']}", json={"is_recurring": True},
                   headers=user["headers"])
    assert r.status_code == 400


def test_offset_pagination_walks_through_all_transactions(client, user, add_tx):
    h = user["headers"]
    for i in range(7):
        add_tx(h, amount=i + 1, occurred_on=(date.today() - timedelta(days=i)).isoformat())
    pages = [
        client.get(f"/transactions?limit=3&offset={offset}", headers=h).json()
        for offset in (0, 3, 6)
    ]
    assert [len(p) for p in pages] == [3, 3, 1]
    amounts = [t["amount"] for page in pages for t in page]
    assert amounts == [1, 2, 3, 4, 5, 6, 7]  # yeniden eskiye, tekrar yok


def test_month_filter_with_pagination(client, user, add_tx):
    h = user["headers"]
    prev = _month_start(date.today(), back=1)
    for _ in range(3):
        add_tx(h, occurred_on=prev.isoformat())
    add_tx(h)
    r = client.get(f"/transactions?month={prev:%Y-%m}&limit=2&offset=2", headers=h)
    assert len(r.json()) == 1


def test_bad_month_is_rejected(client, user):
    for bad in ("2026-13", "ekim", "2026"):
        r = client.get(f"/transactions?month={bad}", headers=user["headers"])
        assert r.status_code == 400, bad


def test_months_lists_totals_newest_first(client, user, add_tx):
    h = user["headers"]
    today = date.today()
    prev = _month_start(today, back=1)
    add_tx(h, amount=100)
    add_tx(h, amount=50, type="income")
    add_tx(h, amount=30, occurred_on=prev.isoformat())

    months = client.get("/transactions/months", headers=h).json()
    assert months == [
        {"month": f"{today:%Y-%m}", "income": 50, "expense": 100, "count": 2},
        {"month": f"{prev:%Y-%m}", "income": 0, "expense": 30, "count": 1},
    ]


def test_summary_for_a_given_month(client, user, add_tx):
    h = user["headers"]
    prev = _month_start(date.today(), back=1)
    add_tx(h, amount=100, category="Yemek")
    add_tx(h, amount=30, category="Ulaşım", occurred_on=prev.isoformat())

    s = client.get(f"/transactions/summary?month={prev:%Y-%m}", headers=h).json()
    assert s["month"] == f"{prev:%Y-%m}"
    assert s["month_expense"] == 30
    assert s["month_by_category"] == [{"category": "Ulaşım", "total": 30}]
    assert s["total_expense"] == 130  # bakiye her zaman tüm zamanlar


def test_categories_endpoint_excludes_total(client):
    cats = client.get("/categories").json()
    assert len(cats) == 8 and "Toplam" not in cats and cats[0] == "Yemek"
