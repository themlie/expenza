"""Profil güncelleme, parola değiştirme ve hesap silme."""
from app import models
from app.database import SessionLocal


def test_update_profile_name_and_alert_preference(client, user):
    h = user["headers"]
    r = client.put("/auth/me", json={"display_name": "  Sena  "}, headers=h)
    assert r.status_code == 200 and r.json()["display_name"] == "Sena"
    r = client.put("/auth/me", json={"alerts_enabled": False}, headers=h)
    body = r.json()
    assert body["alerts_enabled"] is False and body["display_name"] == "Sena"
    assert "created_at" in body


def test_change_password(client, user):
    other_device = client.post(
        "/auth/login", data={"username": user["email"], "password": "parola123"}
    ).json()
    r = client.post(
        "/auth/change-password",
        json={"current_password": "parola123", "new_password": "yeniparola9"},
        headers=user["headers"],
    )
    assert r.status_code == 200
    pair = r.json()

    # Eski erişim token'ları ve diğer cihazın oturumu hemen geçersiz.
    assert client.get("/auth/me", headers=user["headers"]).status_code == 401
    r = client.post("/auth/refresh", json={"refresh_token": other_device["refresh_token"]})
    assert r.status_code == 401
    # Bu cihaz yeni token'la devam eder.
    new_headers = {"Authorization": f"Bearer {pair['access_token']}"}
    assert client.get("/auth/me", headers=new_headers).status_code == 200
    # Yeni parolayla giriş yapılır, eskisiyle yapılamaz.
    login = lambda pw: client.post("/auth/login", data={"username": user["email"], "password": pw})
    assert login("yeniparola9").status_code == 200
    assert login("parola123").status_code == 401


def test_change_password_wrong_current_is_400_not_401(client, user):
    # 401 dönseydi istemci kullanıcıyı oturumdan atardı.
    r = client.post(
        "/auth/change-password",
        json={"current_password": "yanlis123", "new_password": "yeniparola9"},
        headers=user["headers"],
    )
    assert r.status_code == 400
    assert r.json()["detail"] == "Mevcut parola hatalı"


def test_change_password_attempts_are_limited(client, user):
    body = {"current_password": "yanlis123", "new_password": "yeniparola9"}
    codes = [
        client.post("/auth/change-password", json=body, headers=user["headers"]).status_code
        for _ in range(6)
    ]
    assert codes[:5] == [400] * 5 and codes[5] == 429


def test_new_password_must_follow_policy_and_differ(client, user):
    h = user["headers"]
    r = client.post(
        "/auth/change-password",
        json={"current_password": "parola123", "new_password": "kisa"},
        headers=h,
    )
    assert r.status_code == 422
    r = client.post(
        "/auth/change-password",
        json={"current_password": "parola123", "new_password": "parola123"},
        headers=h,
    )
    assert r.status_code == 400


def _count(model, user_id):
    with SessionLocal() as db:
        return db.query(model).filter(model.user_id == user_id).count()


def test_delete_account_removes_all_data(client, user, add_tx, make_user):
    h = user["headers"]
    keep = make_user()
    add_tx(keep["headers"])
    user_id = client.get("/auth/me", headers=h).json()["id"]
    add_tx(h)
    add_tx(h, type="income", is_recurring=True)
    client.post("/budgets", json={"category": "Yemek", "monthly_limit": 50}, headers=h)
    client.post("/goals", json={"title": "Tatil", "target_amount": 1000}, headers=h)
    client.post("/alerts/dismiss", json={"id": "x"}, headers=h)

    r = client.request("DELETE", "/auth/me", json={"password": "parola123"}, headers=h)
    assert r.status_code == 204

    for model in (
        models.Transaction,
        models.RecurringSeries,
        models.Budget,
        models.Goal,
        models.RefreshToken,
        models.DismissedAlert,
    ):
        assert _count(model, user_id) == 0, model.__name__
    with SessionLocal() as db:
        assert db.get(models.User, user_id) is None
    assert client.get("/auth/me", headers=h).status_code == 401
    # Diğer kullanıcının verisi duruyor.
    assert len(client.get("/transactions", headers=keep["headers"]).json()) == 1


def test_delete_account_requires_correct_password(client, user):
    r = client.request(
        "DELETE", "/auth/me", json={"password": "yanlis123"}, headers=user["headers"]
    )
    assert r.status_code == 400
    assert client.get("/auth/me", headers=user["headers"]).status_code == 200
